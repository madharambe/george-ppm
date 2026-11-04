Set-Location "George PPM"
$runId = "41797491054"
for ($i = 0; $i -lt 90; $i++) {
    $json = & gh run view $runId --json status,conclusion 2>&1 | Out-String
    try {
        $o = $json | ConvertFrom-Json
        $st = $o.status
        $cc = $o.conclusion
    } catch { $st = "unknown"; $cc = "" }
    Write-Output ("[{0:HH:mm:ss}] status={1} conclusion={2}" -f (Get-Date), $st, $cc)
    if ($st -eq "completed") { break }
    Start-Sleep -Seconds 20
}
Write-Output ""
Write-Output "=== job summary ==="
& gh run view $runId 2>&1 | ForEach-Object { "  " + $_ }
