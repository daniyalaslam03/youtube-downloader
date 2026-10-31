@echo off
setlocal
 title Youtube Downloader
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0YouTubeDownloaderEngine.ps1"
if errorlevel 1 (
    echo.
    echo Youtube Downloader encountered an error.
    pause
)
endlocal
