# setup_android_sdk.ps1 - install a CLI-only Android SDK on the external drive.
#
# Deliberately NOT Android Studio (saves ~1.1 GB and an IDE we do not need for
# command-line builds). Everything heavy lives on D:, never in OneDrive and
# never on the small C: partition.
#
# Run: powershell -ExecutionPolicy Bypass -File "George PPM\tools\setup_android_sdk.ps1"
param(
    [string]$Root = "D:\Android",
    [string]$Api  = "35",
    [switch]$WithEmulator
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$Sdk      = Join-Path $Root "Sdk"
$CmdTools = Join-Path $Root "cmdline-tools"
$Log      = Join-Path $Root "setup.log"

New-Item -ItemType Directory -Force -Path $Root, $CmdTools, $Sdk | Out-Null
function Log($m) {
    $line = "{0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $m
    Write-Output $line
    Add-Content -Path $Log -Value $line
}

Log "=== Android SDK setup ==="
Log "root: $Root   api: $Api   emulator: $([bool]$WithEmulator)"

# ---- Java (sdkmanager needs a JDK) ----
$jdk = "C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot"
if (Test-Path $jdk) {
    $env:JAVA_HOME = $jdk
    Log "JAVA_HOME = $jdk"
} else {
    Log "WARNING: expected JDK not found at $jdk"
}

# ---- 1. command-line tools ----
$zip = Join-Path $Root "cmdline-tools.zip"
$sdkmanager = Join-Path $CmdTools "latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkmanager)) {
    Log "downloading command-line tools..."
    $dl = Join-Path $PSScriptRoot "download.py"
    & python $dl "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" $zip
    if (-not (Test-Path $zip)) { Log "DOWNLOAD FAILED"; exit 1 }

    # A truncated download must not be extracted - verify the archive first.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $entries = 0
    try {
        $za = [System.IO.Compression.ZipFile]::OpenRead($zip)
        $entries = $za.Entries.Count
        $za.Dispose()
    } catch {
        Log ("zip unreadable: " + $_.Exception.Message)
    }
    Log ("zip entries: $entries  size: {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))
    if ($entries -lt 10) {
        Log "ZIP IS TRUNCATED OR CORRUPT - deleting and stopping so the next run re-downloads"
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        exit 1
    }

    Log "extracting..."
    $tmp = Join-Path $Root "_extract"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    # the zip contains cmdline-tools\<files>; sdkmanager expects cmdline-tools\latest\<files>
    $inner = Join-Path $tmp "cmdline-tools"
    Remove-Item (Join-Path $CmdTools "latest") -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item $inner (Join-Path $CmdTools "latest") -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Log "command-line tools installed"
} else {
    Log "command-line tools already present"
}

if (-not (Test-Path $sdkmanager)) {
    Log "FATAL: sdkmanager.bat still missing at $sdkmanager - aborting"
    exit 1
}
Log "sdkmanager present"

# ---- 2. accept licences (build a stream of "y" lines without backtick escapes) ----
Log "accepting SDK licences..."
$nl = [char]10
$yes = ("y" + $nl) * 60
$yes | & $sdkmanager --sdk_root=$Sdk --licenses 2>&1 | Select-Object -Last 3 | ForEach-Object { Log $_ }

# ---- 3. core packages ----
$pkgs = @(
    "platform-tools",
    "platforms;android-$Api",
    "build-tools;35.0.0"
)
if ($WithEmulator) {
    $pkgs += @("emulator", "system-images;android-$Api;google_apis;x86_64")
}
Log ("installing: " + ($pkgs -join ", "))
& $sdkmanager --sdk_root=$Sdk $pkgs 2>&1 | Select-Object -Last 8 | ForEach-Object { Log $_ }

# ---- 4. environment variables ----
Log "setting ANDROID_HOME / ANDROID_SDK_ROOT (user scope)"
& setx ANDROID_HOME $Sdk | Out-Null
& setx ANDROID_SDK_ROOT $Sdk | Out-Null
& setx PATH "$env:PATH;$Sdk\platform-tools;$Sdk\emulator" | Out-Null
Log "env set (new shells only)"

# ---- 5. report ----
Log "=== installed components ==="
& $sdkmanager --sdk_root=$Sdk --list_installed 2>&1 | ForEach-Object { Log $_ }

$size = (Get-ChildItem $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
         Measure-Object Length -Sum).Sum
Log ("total size on disk: {0:N0} MB" -f ($size / 1MB))
Log ("D: free after install: {0:N1} GB" -f ((Get-PSDrive D).Free / 1GB))
Log "=== DONE ==="
