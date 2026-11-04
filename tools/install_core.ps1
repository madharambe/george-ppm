# install_core.ps1 - the packages actually needed to BUILD the app.
# The emulator + system image (~1.5 GB) is excluded on purpose: sdkmanager
# thrashed on it (3.2 GB heap vs limited RAM, zero disk progress for 10 min),
# and an emulator has no Bluetooth radio so it can never test this project.
param([string]$Root = "D:\Android")

$ErrorActionPreference = "Continue"
$Sdk = Join-Path $Root "Sdk"
$Log = Join-Path $Root "core_install.log"

function Log($m) {
    $line = "{0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $m
    Write-Output $line
    Add-Content -Path $Log -Value $line
}

$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot"
# Cap the heap: the default let the JVM grow to 4.8 GB on a machine with far
# less free RAM, which produced CPU-burning stalls with no disk progress.
$env:JAVA_OPTS = "-Xmx1024m"

$sdkmanager = Join-Path $Root "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkmanager)) { Log "FATAL: sdkmanager missing"; exit 1 }

Log "=== installing core packages (no emulator, no system image) ==="
Log ("heap cap: " + $env:JAVA_OPTS)
Log ("D: free before: {0:N1} GB" -f ((Get-PSDrive D).Free/1GB))

$pkgs = @("platform-tools", "platforms;android-35", "build-tools;35.0.0")
foreach ($p in $pkgs) {
    Log ("--- installing " + $p)
    $before = (Get-ChildItem $Sdk -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    & $sdkmanager --sdk_root=$Sdk $p 2>&1 | Select-Object -Last 4 | ForEach-Object { Log ("    " + $_) }
    $after = (Get-ChildItem $Sdk -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Log ("    exit " + $LASTEXITCODE + "   delta {0:N1} MB" -f (($after-$before)/1MB))
}

Log "=== installed ==="
& $sdkmanager --sdk_root=$Sdk --list_installed 2>&1 | ForEach-Object { Log $_ }

Log "=== verify binaries ==="
foreach ($b in @("platform-tools\adb.exe", "build-tools\35.0.0\aapt2.exe", "platforms\android-35\android.jar")) {
    $f = Join-Path $Sdk $b
    if (Test-Path $f) { Log ("  OK   " + $b) } else { Log ("  MISS " + $b) }
}

$size = (Get-ChildItem $Root -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
Log ("total D:\Android: {0:N0} MB   D: free {1:N1} GB" -f ($size/1MB), ((Get-PSDrive D).Free/1GB))
Log "=== DONE ==="
