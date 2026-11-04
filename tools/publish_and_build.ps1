# publish_and_build.ps1 - push the project to GitHub and let CI build the .ipa.
#
# NOT run automatically: the golden rules say "git push only when the user asked".
# Run this yourself when you want the iOS app actually compiled.
#
# What it does:
#   1. creates a PRIVATE GitHub repo (your code is not published)
#   2. pushes the project
#   3. triggers the "iOS build and test" workflow
#   4. waits for it, then downloads the unsigned .ipa artifact
#
# Requires: gh CLI logged in (already true on this machine).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File "George PPM\tools\publish_and_build.ps1"
#   ... -RepoName george-ppm -Visibility private
param(
    [string]$RepoName   = "george-ppm",
    [string]$Visibility = "private"
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
Push-Location $proj

try {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh CLI not found" }

    $auth = gh auth status 2>&1 | Out-String
    if ($auth -notmatch "Logged in") { throw "gh is not logged in - run: gh auth login" }

    $remotes = git remote -v
    if (-not $remotes) {
        Write-Output "creating $Visibility repo $RepoName ..."
        gh repo create $RepoName --$Visibility --source . --remote origin --push
    } else {
        Write-Output "remote already configured, pushing ..."
        git push -u origin HEAD
    }

    Write-Output ""
    Write-Output "waiting for the iOS workflow ..."
    Start-Sleep -Seconds 10
    gh run list --workflow=ios.yml --limit 1
    gh run watch

    Write-Output ""
    Write-Output "downloading artifacts ..."
    $out = Join-Path $proj "build-artifacts"
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    gh run download --dir $out

    Get-ChildItem $out -Recurse -Filter "*.ipa" | ForEach-Object {
        Write-Output ("IPA: " + $_.FullName + "  ({0:N2} MB)" -f ($_.Length/1MB))
    }
} finally {
    Pop-Location
}
