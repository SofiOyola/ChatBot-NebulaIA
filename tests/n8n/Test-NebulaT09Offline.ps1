[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-NebulaT09.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nebula-t09-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

try {
    $failed = 0
    foreach ($scenario in 'T09-A','T09-B','T09-C') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Scenario $scenario `
            -Transport Simulation -SimulationScenario Valid -ReportDirectory $scratch | Out-Null
        $processExit = $LASTEXITCODE
        $file = Get-ChildItem $scratch -Filter "$scenario-*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
        $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $serialized = $report | ConvertTo-Json -Depth 8
        $sensitiveNames = @('password','accessToken','access_token','refresh_token','authorization','email','responseBody','responseText')
        $sensitive = @($sensitiveNames | Where-Object { $serialized -match ('"' + [regex]::Escape($_) + '"') }).Count -gt 0
        $passed = $processExit -eq 0 -and $report.automaticStatus -eq 'PASS' -and
                  $report.structuralValidation -eq 'PASS' -and $report.conversationIdValid -eq $true -and
                  $report.manualEvaluation -eq 'PENDING' -and -not $sensitive
        Write-Host ("{0}: {1} estructura valida, revision manual pendiente" -f $(if ($passed) {'PASS'} else {'FAIL'}), $scenario)
        if (-not $passed) { $failed++ }
    }

    $negativeScenarios = 'AuthRejected','HttpError','InvalidJson','EmptyResponse','WrongProject','SuccessFalse','UnexpectedStructure'
    foreach ($simulation in $negativeScenarios) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Scenario T09-A `
            -Transport Simulation -SimulationScenario $simulation -ReportDirectory $scratch | Out-Null
        $processExit = $LASTEXITCODE
        $file = Get-ChildItem $scratch -Filter 'T09-A-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
        $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $passed = $processExit -eq 1 -and $report.automaticStatus -eq 'FAIL' -and $report.manualEvaluation -eq 'PENDING'
        Write-Host ("{0}: detecta {1}" -f $(if ($passed) {'PASS'} else {'FAIL'}), $simulation)
        if (-not $passed) { $failed++ }
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Scenario T09-A `
        -Transport Simulation -SimulationScenario LiteralEscape -ReportDirectory $scratch | Out-Null
    $processExit = $LASTEXITCODE
    $file = Get-ChildItem $scratch -Filter 'T09-A-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
    $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $warningPassed = $processExit -eq 0 -and $report.automaticStatus -eq 'PASS' -and
                     $report.formatWarnings -contains 'literal_escape_sequence_detected'
    Write-Host ("{0}: senala escape literal sin alterar el texto" -f $(if ($warningPassed) {'PASS'} else {'FAIL'}))
    if (-not $warningPassed) { $failed++ }

    if ($failed -gt 0) { exit 1 }
    exit 0
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
