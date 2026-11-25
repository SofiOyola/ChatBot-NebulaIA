[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-NebulaN8nRegression.ps1'
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('nebula-n8n-runner-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

try {
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($id in 'T01','T02','T03','T04','T05','T06','T07','T08') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -CaseId $id -Transport Simulation -NonInteractive -ReportDirectory $scratch | Out-Null
        $exit = $LASTEXITCODE
        $report = Get-ChildItem $scratch -Filter "$id-*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
        $json = [System.IO.File]::ReadAllText($report.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $expected = if ($id -in 'T07','T08') { 'SKIP' } else { 'PASS' }
        $checks.Add([pscustomobject]@{ Name = "$id simulacion esperada"; Passed = ($exit -eq 0 -and $json.status -eq $expected) })
    }

    foreach ($scenario in 'WrongStatus','WrongJson') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -CaseId T01 -Transport Simulation -SimulationScenario $scenario -NonInteractive -ReportDirectory $scratch | Out-Null
        $exit = $LASTEXITCODE
        $report = Get-ChildItem $scratch -Filter 'T01-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
        $json = [System.IO.File]::ReadAllText($report.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $checks.Add([pscustomobject]@{ Name = "T01 detecta $scenario"; Passed = ($exit -eq 1 -and $json.status -eq 'FAIL') })
    }

    $failed = @($checks | Where-Object { -not $_.Passed })
    $checks | ForEach-Object { Write-Host ("{0}: {1}" -f $(if ($_.Passed) {'PASS'} else {'FAIL'}), $_.Name) }
    if ($failed.Count -gt 0) { exit 1 }
    exit 0
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
