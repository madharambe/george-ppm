# build_apk.ps1 - build the debug APK with the D: toolchain.
# Everything heavy (SDK, Gradle, dependency caches) stays on D:.
param(
    [string]$Project = "George PPM\android",
    [string]$GradleHome = "D:\Android\gradle-home"
)

$ErrorActionPreference = "Continue"
$env:JAVA_HOME        = "C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot"
$env:ANDROID_HOME     = "D:\Android\Sdk"
$env:ANDROID_SDK_ROOT = "D:\Android\Sdk"
$env:GRADLE_USER_HOME = $GradleHome

$gradle = "D:\Android\gradle\gradle-8.9\bin\gradle.bat"
if (-not (Test-Path $gradle)) { Write-Output "gradle missing"; exit 1 }

New-Item -ItemType Directory -Force -Path $GradleHome | Out-Null

Write-Output ("JAVA_HOME      = " + $env:JAVA_HOME)
Write-Output ("ANDROID_HOME   = " + $env:ANDROID_HOME)
Write-Output ("GRADLE_USER_HOME = " + $env:GRADLE_USER_HOME)
Write-Output ("D: free {0:N1} GB" -f ((Get-PSDrive D).Free/1GB))
Write-Output ""

& $gradle -p $Project assembleDebug --no-daemon --console=plain --stacktrace 2>&1
$code = $LASTEXITCODE
Write-Output ""
Write-Output ("=== gradle exit: " + $code + " ===")

$apk = Join-Path $Project "app\build\outputs\apk\debug\app-debug.apk"
if (Test-Path $apk) {
    Write-Output ("APK: " + (Resolve-Path $apk))
    Write-Output ("size: {0:N2} MB" -f ((Get-Item $apk).Length/1MB))
} else {
    Write-Output "NO APK PRODUCED"
}
Write-Output ("D: free after {0:N1} GB" -f ((Get-PSDrive D).Free/1GB))
