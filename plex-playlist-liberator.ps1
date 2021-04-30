<#
.Synopsis
Provides functionality for managing playlists in m3u format and importing into/exporting from Plex.

.Description
Provides functionality for managing playlists in m3u format and importing into/exporting from Plex.

.Example
.\plex-playlist-liberator.ps1 -Backup -Destination $env:OneDrive\Music\Playlists\PlexBackup

Export audio playlists from Plex and save .m3u files to the destination folder.

.Example
.\plex-playlist-liberator.ps1 -ConvertToM3u -Source $env:OneDrive\Music\Playlists -Destination $env:OneDrive\Music\Playlists\converted -MusicFolder $env:OneDrive\Music

Convert the .wma playlists in the source folder to .m3u playlists and save to the destination folder.

If any lines in the .wma files do not include a file path, the title will be used to look for a file with a matching name in the specified music folder.

.Example
.\plex-playlist-liberator.ps1 -Sort -Source $env:OneDrive\Music\Playlists

Sort the contents of the .m3u playlists in the specified folder and write them back in place.
#>

param(
    # Display usage
    [Parameter(ParameterSetName = "Help", Position = 0)]
    [switch]$Help,
    # Export audio playlists from Plex
    [Parameter(ParameterSetName = "Backup", Mandatory, Position = 0)]
    [switch]$Backup,
    # Convert .wma playlists to .m3u
    [Parameter(ParameterSetName = "ConvertToM3u", Mandatory, Position = 0)]
    [switch]$ConvertToM3u,
    # Sort playlists
    [Parameter(ParameterSetName = "Sort", Mandatory, Position = 0)]
    [switch]$Sort,
    # The playlists folder to read from
    [Parameter(ParameterSetName = "ConvertToM3u", Mandatory, Position = 1)]
    [Parameter(ParameterSetName = "Sort", Mandatory, Position = 1)]
    [string]$Source,
    # The playlists folder to write to
    [Parameter(ParameterSetName = "Backup", Mandatory, Position = 1)]
    [Parameter(ParameterSetName = "ConvertToM3u", Mandatory, Position = 2)]
    [string]$Destination,
    # Where to look for music if file paths are missing in .wma playlists
    [Parameter(ParameterSetName = "ConvertToM3u", Position = 3)]
    [string]$MusicFolder)

if ((Get-Host).Version.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or greater."
    exit
}

##################################################
# Plex helpers

function GetAccessToken() {
    $product = "PlexPlaylistLiberator"
    $clientId = "PlexPlaylistLiberator-$env:ComputerName"

    $registryPath = "HKCU:\Software\$product"
    $registryPathAccessTokenKey = "AccessToken"
    if (!(Test-Path $registryPath)) {
        New-Item $registryPath -Force | Out-Null
    }
    $userAccessToken = Get-ItemPropertyValue $registryPath -Name $registryPathAccessTokenKey -ErrorAction Ignore

    try {
        $verifyAccessTokenResponse = iwr https://plex.tv/api/v2/user -Headers @{
            "Accept"                   = "application/json"
            "X-Plex-Product"           = $product
            "X-Plex-Client-Identifier" = $clientId
            "X-Plex-Token"             = $userAccessToken
        }

        if ($verifyAccessTokenResponse.StatusCode -eq 200) {
            return $userAccessToken
        }
        else {
            Write-Error "Unable to verify access token"
            return
        }
    }
    catch {
    }

    Write-Host "Generating access token"

    $pinResponse = iwr https://plex.tv/api/v2/pins -Method Post -Headers @{
        "Accept"                   = "application/json"
        "strong"                   = "true"
        "X-Plex-Product"           = $product
        "X-Plex-Client-Identifier" = $clientId
    } | ConvertFrom-Json

    start "https://app.plex.tv/auth#?clientID=$clientId&code=$($pinResponse.code)&context%5Bdevice%5D%5Bproduct%5D=Plex Web"

    $animationCounter = 0
    $animationFrames = 5
    Write-Host "Waiting for app approval...." -NoNewline

    do {
        $animationCounter++
        if ($animationCounter % $animationFrames -eq 0) {
            Write-Host ("`b `b" * $animationFrames) -NoNewline
        }
        Write-Host . -NoNewline
        sleep -m 500
        if ($animationCounter % $animationFrames -eq 0) {
            $pinCheckResponse = iwr https://plex.tv/api/v2/pins/$($pinResponse.id) -Headers @{
                "Accept"                   = "application/json"
                "code"                     = $pinResponse.code
                "X-Plex-Client-Identifier" = $clientId
            } | ConvertFrom-Json
        }
    } while (!$pinCheckResponse.authToken)

    Write-Host

    Set-ItemProperty $registryPath -Name $registryPathAccessTokenKey -Value $pinCheckResponse.authToken

    return $pinCheckResponse.authToken
}

function GetJson($route) {
    $trimmedRoute = $route.Trim('/')
    $queryStringAppender = $route.Contains("?") ? "&" : "?"
    $response = iwr "http://127.0.0.1:32400/${trimmedRoute}${queryStringAppender}X-Plex-Token=$accessToken" -Headers @{ "Accept" = "application/json" }
    $responseUtf8 = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::GetEncoding(28591).GetBytes($response.Content))
    ConvertFrom-Json $responseUtf8
}

##################################################
# Backup

function BackupPlaylists() {
    Write-Output "Backing up to $Destination"
    mkdir $Destination -Force | Out-Null
    $allPlaylistsResponse = GetJson "playlists?playlistType=audio"
    $allPlaylistsResponse.MediaContainer.Metadata | % { BackupPlaylist $_ }
}

function BackupPlaylist($metadata) {
    Write-Output `t$($metadata.title)
    $playlist = GetJson $metadata.key
    $files = $playlist.MediaContainer.Metadata.Media.Part.file ?? @("")
    # Set-Content writes BOM in PS 5, which prevents Plex from importing the first line
    [IO.File]::WriteAllLines("$Destination\$($metadata.title).m3u", $files)
}

##################################################
# ConvertToM3u

function ConvertPlaylistsToM3u() {
    Write-Output "Converting to $Destination"
    mkdir $Destination -Force | Out-Null
    Get-ChildItem $Source *.wpl | % { ConvertPlaylistToM3u $_ }
}

function ConvertPlaylistToM3u($wplFilename) {
    Write-Output `t$($wplFilename.BaseName)
    $playlist = Get-Content $wplFilename | Select-String "<media" | % { $_ -replace "^.+src=`"(.+?)`".+$", "`$1" }
    if ($MusicFolder) {
        $playlist = $playlist | % {
            if ($_ -like "*<media*" -and
                $_ -match "trackTitle=`"(?<title>.+?)`"" -and
                ($foundFile = Get-ChildItem $MusicFolder "*$(ReplaceInvalidFileNameCharsForSearch $Matches.title)*.mp3" -Recurse) -and
                ($foundFile.Count -eq 1)) {
                $foundFile
            }
            else {
                $_
            }
        }
    }
    $unparseable = $playlist | ? { $_ -like "*<media*" }
    if ($unparseable) {
        Write-Output "`t`tSome lines could not be parsed - look for <media> lines in the destination file"
    }
    Set-Content $Destination\$($wplFilename.BaseName).m3u $playlist
}

function ReplaceInvalidFileNameCharsForSearch($string) {
    [IO.Path]::GetInvalidFileNameChars() | % {
        $string = $string.Replace($_, "*")
    }
    $string
}

##################################################
# Sort

function SortPlaylists() {
    Write-Output "Sorting $Source"
    Get-ChildItem $Source *.m3u | % { SortPlaylist $_ }
}

function SortPlaylist($playlistFilename) {
    Write-Output `t$($playlistFilename.BaseName)
    Get-Content $playlistFilename |
    sort |
    Set-Content $playlistFilename
}

##################################################
# Run

if ($PSCmdlet.ParameterSetName -eq "Help") {
    Get-Help $PSCommandPath
}

if ($ConvertToM3u) { ConvertPlaylistsToM3u }
if ($Sort) { SortPlaylists }

$accessToken = GetAccessToken

if ($Backup) { BackupPlaylists }

return





$musicLibraryId = ((GetJson library/sections).MediaContainer.Directory | ? { $_.Location.path -contains "$OneDrive\Music" }).key

$playlistPath = "C:\BenLocal\playlists\BTest - Copy.m3u"
$encodedPlaylistPath = $playlistPath
# $encodedPlaylistPath = "$env:tmp\$(New-Guid).m3u"
# Set-Content $encodedPlaylistPath (Get-Content $playlistPath | % { [System.Web.HttpUtility]::UrlEncode($_) })
iwr "http://127.0.0.1:32400/playlists/upload?sectionID=$musicLibraryId&path=$encodedPlaylistPath&X-Plex-Token=$accessToken" -Method Post -Headers @{ "Accept" = "application/json" }
