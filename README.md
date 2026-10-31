# YouTube Downloader

A Windows desktop application for downloading YouTube videos and playlists with quality selection, audio extraction, download history, and dependency management.

## Features

- Download individual YouTube videos.
- Download complete playlists.
- Select video quality (360p through 4K, or best available).
- Extract audio in supported formats.
- Choose a default download folder on first launch; the selection is saved for future launches.
- Re-prompt if the saved download folder is no longer available.
- Resume interrupted downloads and playlists.
- Keep track of download history and retry previous downloads.
- Manage application settings.
- Update bundled dependencies.

## Requirements

- Windows 10 or later.
- Internet connection.

## Installation

1. Visit the [Releases](https://github.com/daniyalaslam03/youtube-downloader/releases) page.
2. Download the latest installer, currently `YouTubeDownloader-Setup-1.0.1.exe`.
3. Run the installer.
4. Follow the installation instructions.
5. Launch YouTube Downloader and choose your default download folder when prompted.

## Default video container

The supplied settings use MP4 as the preferred merge container. This does not re-encode every download; it asks yt-dlp to use MP4 when merging compatible streams.

## Technology

- yt-dlp
- FFmpeg
- FFprobe
- Node.js
- PowerShell
- Windows Batch

## Disclaimer

This project is intended for downloading content that you own or are authorized to download. Users are responsible for complying with copyright laws and applicable platform terms.

## Support

For bug reports and feature requests, please use the repository's [Issues](https://github.com/daniyalaslam03/youtube-downloader/issues) page.

---

**YouTube Downloader — Version 1.0.1**
