$ErrorActionPreference = 'Continue'
$Root = "D:\Android\gradle"
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$zip = Join-Path $Root "gradle-8.9-bin.zip"

Write-Output "downloading Gradle 8.9 (services.gradle.org is the slow host, ~150 KB/s)"
& python "George PPM\tools\download.py" "https://services.gradle.org/distributions/gradle-8.9-bin.zip" $zip --chunk-mb 4

if (-not (Test-Path $zip)) { Write-Output "DOWNLOAD FAILED"; exit 1 }
Write-Output ("zip: {0:N1} MB" -f ((Get-Item $zip).Length/1MB))

Add-Type -AssemblyName System.IO.Compression.FileSystem
$za = [System.IO.Compression.ZipFile]::OpenRead($zip)
$n = $za.Entries.Count
$za.Dispose()
Write-Output "entries: $n"
if ($n -lt 100) { Write-Output "ZIP CORRUPT"; Remove-Item $zip -Force; exit 1 }

Expand-Archive -Path $zip -DestinationPath $Root -Force
Write-Output ("extracted. gradle.bat present: " + (Test-Path (Join-Path $Root "gradle-8.9\bin\gradle.bat")))
Write-Output ("D: free {0:N1} GB" -f ((Get-PSDrive D).Free/1GB))
