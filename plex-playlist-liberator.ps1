<#

#>

param(
    [Parameter(ParameterSetName = "Backup", Mandatory, Position = 0)]
    [switch]$Backup,
    [Parameter(ParameterSetName = "ConvertToM3u", Mandatory, Position = 0)]
    [switch]$ConvertToM3u,
    [Parameter(ParameterSetName = "Sort", Mandatory, Position = 0)]
    [switch]$Sort,
    [Parameter(ParameterSetName = "ConvertToM3u", Mandatory, Position = 1)]
    [Parameter(ParameterSetName = "Sort", Mandatory, Position = 1)]
    [string]$Source,
    [Parameter(ParameterSetName = "Backup", Mandatory, Position = 1)]
    [Parameter(ParameterSetName = "ConvertToM3u", Mandatory, Position = 2)]
    [string]$Destination,
    [Parameter(ParameterSetName = "ConvertToM3u", Position = 3)]
    [string]$MusicFolder)

# .\plex-playlist-liberator.ps1 -Backup -Destination C:\BenLocal\playlists\backup
# .\plex-playlist-liberator.ps1 -Sort
# .\plex-playlist-liberator.ps1 -Sort -Source C:\BenLocal\playlists\converted
# OneDrive\Music\ .wma

$plexToken = ""

if ((Get-Host).Version.Major -lt 6) {
    Write-Error "Due to text encoding difficulties, it is highly recommended that you use PowerShell 6 or greater when running this script."
    exit
}

function GetJson($route) {
    $trimmedRoute = $route.Trim('/')
    $queryStringAppender = if ($route.Contains("?")) { "&" } else { "?" }
    $response = iwr "http://127.0.0.1:32400/${trimmedRoute}${queryStringAppender}X-Plex-Token=$plexToken" -Headers @{ "Accept" = "application/json" }
    $responseUtf8 = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::GetEncoding(28591).GetBytes($response.Content))
    ConvertFrom-Json $responseUtf8
}

function BackupPlaylist($metadata, $backupFolder) {
    Write-Output `t$($metadata.title)
    $playlist = GetJson $metadata.key
    $files = if ($playlist.MediaContainer.Metadata.Media.Part.file) { $playlist.MediaContainer.Metadata.Media.Part.file } else { @("") }
    # Set-Content writes BOM in PS 5, which prevents Plex from importing the first line
    [IO.File]::WriteAllLines("$backupFolder\$($metadata.title).m3u", $files)
}

function BackupPlaylists($backupFolder) {
    Write-Output "Backing up to $backupFolder"
    mkdir $backupFolder -Force | Out-Null
    $allPlaylistsResponse = GetJson "playlists?playlistType=audio"
    $allPlaylistsResponse.MediaContainer.Metadata | % { BackupPlaylist $_ $backupFolder }
}

# function ConvertPlaylistToM3u($wplFilename) {
#     Write-Output `t$($wplFilename.BaseName)
#     $playlist = Get-Content $wplFilename.FullName | Select-String "<media" | % { $_ -replace "^.*src=`"(.+?)`".*$", "`$1" }
#     Set-Content $Destination\$($wplFilename.BaseName).m3u $playlist
#     $unparseable = $playlist | ? { $_ -like "*<media*" }
#     if ($unparseable) {
#         Write-Output "`t`tSome lines could not be parsed - look for <media> lines in the destination files"
#         # Write-Output "`t`tThese lines could not be parsed"
#         # $unparseable | % { Write-Output `t`t$_ }
#     }
# }

function ReplaceInvalidFileNameCharsForSearch($string) {
    [IO.Path]::GetInvalidFileNameChars() | % {
        $string = $string.Replace($_, "*")
    }
    $string
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

function ConvertPlaylistsToM3u() {
    Write-Output "Converting to $Destination"
    mkdir $Destination -Force | Out-Null
    Get-ChildItem $Source *.wpl | % { ConvertPlaylistToM3u $_ }
}

function SortPlaylist($playlistFilename) {
    Write-Output `t$($playlistFilename.BaseName)
    Get-Content $playlistFilename |
    sort |
    Set-Content $playlistFilename
}

function SortPlaylists() {
    Write-Output "Sorting $Source"
    Get-ChildItem $Source *.m3u | % { SortPlaylist $_ }
}

if ($Backup) { BackupPlaylists $Destination }
if ($ConvertToM3u) { ConvertPlaylistsToM3u }
if ($Sort) { SortPlaylists }

return





$musicLibraryId = ((GetJson library/sections).MediaContainer.Directory | ? { $_.Location.path -contains "$OneDrive\Music" }).key

$playlistPath = "C:\BenLocal\playlists\BTest - Copy.m3u"
$encodedPlaylistPath = $playlistPath
# $encodedPlaylistPath = "$env:tmp\$(New-Guid).m3u"
# Set-Content $encodedPlaylistPath (Get-Content $playlistPath | % { [System.Web.HttpUtility]::UrlEncode($_) })
iwr "http://127.0.0.1:32400/playlists/upload?sectionID=$musicLibraryId&path=$encodedPlaylistPath&X-Plex-Token=$plexToken" -Method Post -Headers @{ "Accept" = "application/json" }
