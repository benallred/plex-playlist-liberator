# plex-playlist-liberator

Provides functionality for managing playlists in m3u format and importing into/exporting from Plex.

## Usage

Show usage

```powershell
.\plex-playlist-liberator.ps1 [-Help]
Get-Help .\plex-playlist-liberator.ps1
```

Export audio playlists from Plex and save .m3u files to the destination folder.

```powershell
.\plex-playlist-liberator.ps1 -Export -Destination $env:OneDrive\Music\Playlists\PlexBackup
```

Import audio playlists to Plex from .m3u files in the source folder.

```powershell
.\plex-playlist-liberator.ps1 -Import -Source $env:OneDrive\Music\Playlists
```

Convert the .wma playlists in the source folder to .m3u playlists and save to the destination folder.
If any lines in the .wma files do not include a file path, the title will be used to look for a file with a matching name in the specified music folder.

```powershell
.\plex-playlist-liberator.ps1 -ConvertToM3u -Source $env:OneDrive\Music\Playlists -Destination $env:OneDrive\Music\Playlists\converted -MusicFolder $env:OneDrive\Music
```

Sort the contents of the .m3u playlists in the specified folder and write them back in place.

```powershell
.\plex-playlist-liberator.ps1 -Sort -Source $env:OneDrive\Music\Playlists
```

Scan the music files in the specified music folder and report any that are not part of a playlist.

```powershell
.\plex-playlist-liberator.ps1 -ScanForOrphans -Source $env:OneDrive\Music\Playlists -MusicFolder $env:OneDrive\Music
```
