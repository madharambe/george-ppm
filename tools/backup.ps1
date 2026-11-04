# backup.ps1 - mirror the workspace to the external drive.
#
# Golden rule: heavy, repeated writes go to the external HDD, never to the
# OneDrive-synced workspace and never to the small C: partition.
#
# DEFAULT IS ADDITIVE (/E): it copies and updates, but NEVER deletes anything in
# the destination. A mirror (/MIR) deletes destination-only files, which on
# 2026-11-04 would have silently removed 113 files / 57.7 MB of a previous
# backup that used an older folder layout. Pass -Mirror to opt into that.
#
# Run:  powershell -ExecutionPolicy Bypass -File "George PPM\tools\backup.ps1"
param(
    [string]$Source = "C:\Users\nicho\OneDrive\Desktop\Projects_deepseek\Tugas Kuliah",
    [string]$Dest   = "D:\Backup Projects\Projects_deepseek\Tugas Kuliah",
    [switch]$DryRun,
    [switch]$Mirror
)

$ErrorActionPreference = "Continue"

function Log($m) { Write-Output ("{0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $m) }

if (-not (Test-Path $Source)) { Log "SOURCE MISSING: $Source"; exit 1 }
if (-not (Test-Path $Dest)) {
    Log "DEST MISSING: $Dest"
    Log "refusing to create-and-mirror into an unknown location"
    exit 1
}

# --- storage status first, always ---
$c = Get-PSDrive C; $d = Get-PSDrive D
Log ("storage  C: free {0:N1} GB   D: free {1:N1} GB" -f ($c.Free/1GB), ($d.Free/1GB))
if ($d.Free -lt 2GB) { Log "D: below 2 GB free - aborting"; exit 1 }

# --- skip the things that must not be mirrored ---
$excludeDirs = @(".git", "__pycache__", ".gradle", "build", "node_modules", ".idea")
$excludeFiles = @("*.pyc", "*.tmp")

$mode = if ($Mirror) { "/MIR" } else { "/E" }
Log ("mode: " + $mode + $(if ($Mirror) { "  (destructive: deletes destination-only files)" } else { "  (additive: never deletes)" }))

$args = @(
    $Source, $Dest,
    $mode,
    "/FFT", "/R:2", "/W:2",
    "/NFL", "/NDL", "/NP",
    "/XD"
) + $excludeDirs + @("/XF") + $excludeFiles
if ($DryRun) { $args += "/L" }

Log ("robocopy " + ($args -join " "))
& robocopy @args | Select-Object -Last 12
$code = $LASTEXITCODE
# robocopy: 0-7 are success, >=8 is a real failure
if ($code -ge 8) { Log "ROBOCOPY FAILED (code $code)"; exit $code }

Log ("backup OK (robocopy code $code)")
$size = (Get-ChildItem $Dest -Recurse -Force -File -ErrorAction SilentlyContinue |
         Measure-Object Length -Sum).Sum
Log ("destination size: {0:N1} MB" -f ($size/1MB))
Log ("D: free after: {0:N1} GB" -f ((Get-PSDrive D).Free/1GB))
