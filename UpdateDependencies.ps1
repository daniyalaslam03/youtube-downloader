<CodeBlock language="powershell" editable>
$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$BinDir = Join-Path $Root 'bin'
$BackupDir = Join-Path $BinDir 'update-backup'
$TempDir = Join-Path $env:TEMP ("YTDownloaderUpdate-" + [guid]::NewGuid())

function Get-InstalledVersion([string]$Name) {
    $exe = Join-Path $BinDir "$Name.exe"

if (!(Test-Path $exe)) {
        return 'Not installed'
    }

try {
        $output = switch ($Name) {
            'yt-dlp' { & $exe --version 2>&1 }
            'node' { & $exe --version 2>&1 }
            'ffmpeg' { & $exe -version 2>&1 }
            'ffprobe' { & $exe -version 2>&1 }
        }

return (($output | Select-Object -First 1).ToString().Trim())
    }
    catch {
        return 'Unknown'
    }
}

function Download-File([string]$Url,[string]$Destination) {
    Write-Host "Downloading: $([IO.Path]::GetFileName($Destination))"

    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing

if (!(Test-Path $Destination) -or (Get-Item $Destination).Length -lt 100KB) {
        throw "Download failed or file is unexpectedly small: $Url"
    }
}

function Test-Executable([string]$Path,[string[]]$Arguments) {
    & $Path @Arguments | Out-Null

if ($LASTEXITCODE -ne 0) {
        throw "Executable validation failed: $Path"
    }
}

try {
    Write-Host '=================================================' -ForegroundColor Cyan
    Write-Host '          YOUTUBE DOWNLOADER UPDATER' -ForegroundColor Cyan
    Write-Host '=================================================' -ForegroundColor Cyan

if (!(Test-Path $BinDir)) {
        throw 'Application bin folder was not found.'
    }

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

    Write-Host "`nInstalled versions:" -ForegroundColor Cyan

    foreach ($name in @('yt-dlp','node','ffmpeg','ffprobe'))