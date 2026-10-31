
param([string]$ReplayPath = "")

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$ConfigDir = Join-Path $Root 'config'
$DataDir = Join-Path $Root 'data'
$LogDir = Join-Path $Root 'logs'
$BinDir = Join-Path $Root 'bin'
$SettingsPath = Join-Path $ConfigDir 'settings.json'
$HistoryPath = Join-Path $DataDir 'history.json'
$LastPath = Join-Path $DataDir 'last-download.json'

foreach ($p in @($ConfigDir,$DataDir,$LogDir,$BinDir)) {
    if (!(Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

function Write-Title {
    Clear-Host
    Write-Host '=================================================' -ForegroundColor Cyan
    Write-Host '              YOUTUBE DOWNLOADER' -ForegroundColor Cyan
    Write-Host '=================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Read-Settings {
    if (!(Test-Path -LiteralPath $SettingsPath)) {
        throw "Settings file missing: $SettingsPath"
    }
    return (Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json)
}

$Settings = Read-Settings

function Get-ToolPath([string]$Name) {
    $exe = if ($Name -eq 'yt-dlp') { 'yt-dlp.exe' } else { "$Name.exe" }
    $local = Join-Path $BinDir $exe

    if (Test-Path -LiteralPath $local) {
        return $local
    }

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    return $null
}

function Get-DownloadRoot {
    $configured = [string]$Settings.downloads.default_location

    if ([string]::IsNullOrWhiteSpace($configured)) {
        throw 'The default download folder has not been configured.'
    }

    return [Environment]::ExpandEnvironmentVariables($configured)
}

function Save-Json([object]$Object,[string]$Path) {
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

# -------------------------------------------------
# FIRST-RUN DOWNLOAD FOLDER SETUP
# -------------------------------------------------

function Select-DownloadFolder {
    Add-Type -AssemblyName System.Windows.Forms

    $downloadsFolder = Join-Path $env:USERPROFILE 'Downloads'

    if (!(Test-Path -LiteralPath $downloadsFolder -PathType Container)) {
        $downloadsFolder = $env:USERPROFILE
    }

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choose the default folder for your downloads.'
    $dialog.SelectedPath = $downloadsFolder
    $dialog.ShowNewFolderButton = $true

    try {
        $result = $dialog.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
        return $null
    }
    finally {
        $dialog.Dispose()
    }
}

function Ensure-DownloadLocation {
    $configured = [string]$Settings.downloads.default_location

    if (![string]::IsNullOrWhiteSpace($configured)) {
        $configured = [Environment]::ExpandEnvironmentVariables($configured)
        if (Test-Path -LiteralPath $configured -PathType Container) {
            return $true
        }
    }

    Write-Title
    Write-Host 'WELCOME TO YOUTUBE DOWNLOADER' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Choose where your downloaded videos and audio should be saved.'
    Write-Host 'The selected folder will be remembered for future launches.'
    Write-Host ''
    Write-Host 'The default selection is your Windows Downloads folder.'
    Write-Host ''

    while ($true) {
        $selectedFolder = Select-DownloadFolder

        if ([string]::IsNullOrWhiteSpace($selectedFolder)) {
            Write-Host ''
            Write-Host 'No download folder was selected.' -ForegroundColor Yellow
            Write-Host 'YouTube Downloader cannot continue without a download folder.' -ForegroundColor Red
            return $false
        }

        try {
            if (!(Test-Path -LiteralPath $selectedFolder -PathType Container)) {
                New-Item -ItemType Directory -Path $selectedFolder -Force | Out-Null
            }

            if ($null -eq $Settings.downloads) {
                $Settings | Add-Member -NotePropertyName downloads -NotePropertyValue ([pscustomobject]@{})
            }

            if ($null -eq $Settings.downloads.PSObject.Properties['default_location']) {
                $Settings.downloads | Add-Member -NotePropertyName default_location -NotePropertyValue $selectedFolder
            }
            else {
                $Settings.downloads.default_location = $selectedFolder
            }

            Save-Json -Object $Settings -Path $SettingsPath

            Write-Host ''
            Write-Host 'Default download folder saved successfully.' -ForegroundColor Green
            Write-Host $selectedFolder -ForegroundColor Gray
            Start-Sleep -Seconds 2
            return $true
        }
        catch {
            Write-Host ''
            Write-Host "Could not save the selected folder: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host 'Check application folder permissions, then try again.'
            Read-Host 'Press Enter to try again' | Out-Null
        }
    }
}

if (!(Ensure-DownloadLocation)) {
    exit 1
}

function Get-History {
    if (!(Test-Path -LiteralPath $HistoryPath)) {
        return @()
    }

    try {
        $h = Get-Content -LiteralPath $HistoryPath -Raw | ConvertFrom-Json
        if ($null -eq $h) { return @() }
        return @($h)
    }
    catch {
        return @()
    }
}

function Add-History([object]$Record) {
    if (!$Settings.history.enabled) { return }

    $h = @(Get-History)
    $h = @($Record) + $h
    Save-Json -Object $h -Path $HistoryPath
}

function Resolve-Tools {
    $script:YtDlp = Get-ToolPath 'yt-dlp'
    $script:Node = Get-ToolPath 'node'
    $script:Ffmpeg = Get-ToolPath 'ffmpeg'

    if (!$YtDlp) {
        throw 'yt-dlp.exe was not found. Place it in the application bin folder or install yt-dlp and add it to PATH.'
    }
}

function Invoke-Record([object]$Record) {
    Resolve-Tools

    $argsList = @($Record.Arguments)

    if ($Node) {
        $nodeArg = "node:$Node"

        if ($argsList -notcontains '--js-runtimes') {
            $argsList = @('--js-runtimes',$nodeArg) + $argsList
        }
        else {
            $idx = [array]::IndexOf($argsList,'--js-runtimes')
            if ($idx -ge 0 -and $idx+1 -lt $argsList.Count) {
                $argsList[$idx+1] = $nodeArg
            }
        }
    }

    if ($Ffmpeg -and $argsList -notcontains '--ffmpeg-location') {
        $argsList = @('--ffmpeg-location',(Split-Path -Parent $Ffmpeg)) + $argsList
    }

    if ($Settings.authentication.enabled -and $Settings.authentication.browser) {
        $argsList = @('--cookies-from-browser',[string]$Settings.authentication.browser) + $argsList
    }

    Write-Host "`nDestination: $($Record.Destination)" -ForegroundColor Gray
    Write-Host 'Starting yt-dlp...' -ForegroundColor Cyan

    Push-Location $Record.Destination

    try {
        & $YtDlp @argsList
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $runTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    if ($Record -is [System.Collections.IDictionary]) {
        $Record['LastRun'] = $runTime
        $Record['ExitCode'] = $code
        $Record['Status'] = if ($code -eq 0) { 'Completed' } else { 'Incomplete / errors' }
    }
    else {
        $Record | Add-Member -NotePropertyName LastRun -NotePropertyValue $runTime -Force
        $Record | Add-Member -NotePropertyName ExitCode -NotePropertyValue $code -Force
        $Record | Add-Member -NotePropertyName Status -NotePropertyValue $(if ($code -eq 0) { 'Completed' } else { 'Incomplete / errors' }) -Force
    }

    if ($Record.HistoryId) {
        $h = @(Get-History)

        foreach ($item in $h) {
            if ($item.HistoryId -eq $Record.HistoryId) {
                $item | Add-Member -NotePropertyName LastRun -NotePropertyValue $runTime -Force
                $item | Add-Member -NotePropertyName ExitCode -NotePropertyValue $code -Force
                $item | Add-Member -NotePropertyName Status -NotePropertyValue $Record.Status -Force
                $item | Add-Member -NotePropertyName Arguments -NotePropertyValue $Record.Arguments -Force
            }
        }

        Save-Json $h $HistoryPath
    }

    Hide-PlaylistSupportFiles $Record

    Write-Host ''

    if ($code -eq 0) {
        Write-Host 'Download process finished.' -ForegroundColor Green
    }
    else {
        Write-Host "yt-dlp exited with code $code. You can retry this entry from History." -ForegroundColor Yellow
    }
}

function Start-Saved([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) {
        Write-Host 'Saved download record not found.'
        return
    }

    $r = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    Invoke-Record $r
}

function Hide-PlaylistSupportFiles([object]$Record) {
    if ([string]$Record.Type -ne 'Playlist') { return }

    $folder = [string]$Record.Destination

    if ([string]::IsNullOrWhiteSpace($folder) -or !(Test-Path -LiteralPath $folder)) {
        return
    }

    foreach ($name in @('Download-Playlist.bat','download-archive.txt','download.json')) {
        $file = Join-Path $folder $name

        if (Test-Path -LiteralPath $file) {
            try {
                $item = Get-Item -LiteralPath $file -Force
                $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
            }
            catch {
                Write-Host "Could not hide support file: $name" -ForegroundColor Yellow
            }
        }
    }
}

function Safe-FolderName([string]$Name) {
    foreach ($c in [IO.Path]::GetInvalidFileNameChars()) {
        $Name = $Name.Replace([string]$c,'_')
    }

    return $Name.Trim()
}

function New-Download {
    Write-Title

    Write-Host 'DOWNLOAD TYPE'
    Write-Host '1. Single video'
    Write-Host '2. Complete playlist'
    Write-Host ''

    $type = Read-Host 'Select type'

    if ($type -notin @('1','2')) {
        Write-Host 'Invalid selection.' -ForegroundColor Red
        return
    }

    $url = (Read-Host 'Paste video or playlist URL').Trim()

    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-Host 'URL cannot be empty.' -ForegroundColor Red
        return
    }

    Write-Host "`nVIDEO QUALITY"
    Write-Host '1. 360p'
    Write-Host '2. 480p'
    Write-Host '3. 720p'
    Write-Host '4. 1080p'
    Write-Host '5. 1440p'
    Write-Host '6. 2160p (4K)'
    Write-Host '7. Best available'
    Write-Host '8. Audio only'

    $q = Read-Host 'Select quality'

    $heights = @{ '1'=360;'2'=480;'3'=720;'4'=1080;'5'=1440;'6'=2160 }

    if ($q -notin @('1','2','3','4','5','6','7','8')) {
        Write-Host 'Invalid quality.' -ForegroundColor Red
        return
    }

    $audioOnly = $q -eq '8'
    $audioFormat = 'original'

    if ($audioOnly) {
        Write-Host "`nAUDIO FORMAT"
        Write-Host '0. Original / best available'
        Write-Host '1. AAC'
        Write-Host '2. MP3'
        Write-Host '3. M4A'
        Write-Host '4. Opus'
        Write-Host '5. FLAC'

        $af = Read-Host 'Select format'

        $audioFormat = switch ($af) {
            '0' {'original'}
            '1' {'aac'}
            '2' {'mp3'}
            '3' {'m4a'}
            '4' {'opus'}
            '5' {'flac'}
            default {'INVALID'}
        }

        if ($audioFormat -eq 'INVALID') {
            Write-Host 'Invalid audio format.' -ForegroundColor Red
            return
        }
    }

    $base = Get-DownloadRoot

    if (!(Test-Path -LiteralPath $base)) {
        New-Item -ItemType Directory -Path $base -Force | Out-Null
    }

    if ($type -eq '2') {
        $folder = Safe-FolderName (Read-Host 'Playlist folder name')

        if (!$folder) {
            Write-Host 'Folder name required.' -ForegroundColor Red
            return
        }

        $dest = Join-Path $base $folder
    }
    else {
        $dest = $base
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    $argsList = @('--continue','--part','--windows-filenames','--no-mtime')

    if ($Settings.downloads.ignore_errors -and $type -eq '2') {
        $argsList += '--ignore-errors'
    }

    if ($type -eq '2') {
        $argsList += '--yes-playlist'

        if ($Settings.downloads.archive) {
            $argsList += @('--download-archive',(Join-Path $dest 'download-archive.txt'))
        }
    }
    elseif ($type -eq '1') {
        $argsList += '--no-playlist'
    }

    if ($audioOnly) {
        if ($audioFormat -eq 'original') {
            $argsList += @('-f','bestaudio')
        }
        else {
            $argsList += @('-x','--audio-format',$audioFormat,'--audio-quality','0')
        }
    }
    else {
        $limit = if ($q -eq '7') { '' } else { "[height<=$($heights[$q])]" }

        $codec = [string]$Settings.video.codec

        $codecFilter = switch ($codec) {
            'h264' {'[vcodec^=avc1]'}
            'vp9' {'[vcodec^=vp9]'}
            'av1' {'[vcodec^=av01]'}
            default {''}
        }

        $fmt = if ($q -eq '7') {
            "bestvideo$codecFilter+bestaudio/best"
        }
        else {
            "bestvideo$limit$codecFilter+bestaudio/best$limit$codecFilter/best[height<=$($heights[$q])]"
        }

        $argsList += @('-f',$fmt)

        if ($Settings.video.container -and $Settings.video.container -ne 'auto') {
            $argsList += @('--merge-output-format',[string]$Settings.video.container)
        }
    }

    if ($Settings.downloads.embed_thumbnail) {
        $argsList += '--embed-thumbnail'
    }

    if ($Settings.downloads.save_thumbnail) {
        $argsList += @('--write-thumbnail','--convert-thumbnails','jpg')
    }

    if ($type -eq '2') {
        $template = Join-Path $dest '%(playlist_index)03d.%(title)s.%(ext)s'
    }
    else {
        $template = Join-Path $dest '%(title)s.%(ext)s'
    }

    $argsList += @('-o',$template,$url)

    $id = [guid]::NewGuid().ToString()
    $recordType = if ($type -eq '2') { 'Playlist' } else { 'Single video' }

    $qualityLabel = if ($audioOnly) {
        "Audio: $audioFormat"
    }
    elseif ($q -eq '7') {
        'Best available'
    }
    else {
        "$($heights[$q])p maximum"
    }

    $record = [ordered]@{
        HistoryId=$id
        Url=$url
        Type=$recordType
        Quality=$qualityLabel
        Codec=$Settings.video.codec
        Destination=$dest
        CreatedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        LastRun=$null
        Status='Queued'
        ExitCode=$null
        Arguments=$argsList
    }

    Save-Json $record $LastPath
    Add-History $record

    Write-Host "`nSaved to history. Quality is a maximum; if the source lacks it, yt-dlp may select a lower available quality." -ForegroundColor Green

    if ($type -eq '2') {
        $playlistJson = Join-Path $dest 'download.json'
        Save-Json $record $playlistJson

        $playlistBat = Join-Path $dest 'Download-Playlist.bat'

        @(
            '@echo off'
            'title Resume Playlist - Youtube Downloader'
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Root\YouTubeDownloaderEngine.ps1`" -ReplayPath `"$playlistJson`""
            'pause'
        ) | Set-Content -LiteralPath $playlistBat -Encoding ASCII

        Write-Host "Playlist resume file created: $playlistBat" -ForegroundColor Gray
    }

    Invoke-Record $record
}

function Show-History {
    $h = @(Get-History)

    if (!$h.Count) {
        Write-Host 'No download history yet.' -ForegroundColor Yellow
        return
    }

    for ($i=0; $i -lt $h.Count; $i++) {
        $r=$h[$i]
        Write-Host ("{0}. [{1}] {2} | {3} | {4}" -f ($i+1),$r.Status,$r.Type,$r.Quality,$r.CreatedAt)
        Write-Host "   $($r.Destination)" -ForegroundColor Gray
    }

    $choice = Read-Host "`nEnter entry number to retry/resume, or press Enter to return"

    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $h.Count) {
        $r = $h[[int]$choice-1]

        $action = Read-Host '1. Resume / retry  2. Open folder  3. Delete history entry'

        if ($action -eq '1') {
            Invoke-Record $r
        }
        elseif ($action -eq '2') {
            if (Test-Path $r.Destination) {
                Start-Process explorer.exe -ArgumentList $r.Destination
            }
            else {
                Write-Host 'Folder not found.' -ForegroundColor Red
            }
        }
        elseif ($action -eq '3') {
            $h = @($h | Where-Object { $_.HistoryId -ne $r.HistoryId })
            Save-Json $h $HistoryPath
            Write-Host 'History entry deleted.' -ForegroundColor Green
        }
    }
}

function Show-Settings {
    Write-Host "`nCURRENT SETTINGS" -ForegroundColor Cyan
    Write-Host "Download folder: $(Get-DownloadRoot)"
    Write-Host "Codec preference: $($Settings.video.codec)"
    Write-Host "Container: $($Settings.video.container)"
    Write-Host "Embed thumbnail: $($Settings.downloads.embed_thumbnail)"
    Write-Host "Save thumbnail: $($Settings.downloads.save_thumbnail)"
    Write-Host "Browser cookies: $($Settings.authentication.enabled) ($($Settings.authentication.browser))"
    Write-Host "`nEdit config\settings.json to change these options."
}

function Update-Dependencies {
    $updater = Join-Path $Root 'UpdateDependencies.ps1'

    if (!(Test-Path -LiteralPath $updater)) {
        Write-Host 'Updater script is missing from the application folder.' -ForegroundColor Red
        return
    }

    Write-Host "`nThe updater will check yt-dlp, FFmpeg, FFprobe and Node.js." -ForegroundColor Cyan
    Write-Host 'Administrator permission may be required to update application files.'

    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$updater`""
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait
    }
    catch {
        Write-Host 'Update cancelled or administrator permission was denied.' -ForegroundColor Yellow
    }
}

if ($ReplayPath) {
    Start-Saved $ReplayPath
    exit
}

while ($true) {
    Write-Title

    Write-Host '1. New download'
    Write-Host '2. Download history'
    Write-Host '3. Settings / configuration'
    Write-Host '4. Update dependencies'
    Write-Host '5. Exit'
    Write-Host ''

    $choice = Read-Host 'Select option'

    switch ($choice) {
        '1' {
            try { New-Download }
            catch { Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red }
            Read-Host "`nPress Enter to continue" | Out-Null
        }
        '2' {
            try { Show-History }
            catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
            Read-Host "`nPress Enter to continue" | Out-Null
        }
        '3' {
            Show-Settings
            Read-Host "`nPress Enter to return" | Out-Null
        }
        '4' {
            Update-Dependencies
            Read-Host "`nPress Enter to return" | Out-Null
        }
        '5' {
            break
        }
        default {
            Write-Host 'Invalid option.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
