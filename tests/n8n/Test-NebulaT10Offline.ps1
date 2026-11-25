[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-NebulaT10.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nebula-t10-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $failed = 0
    foreach ($scenario in 'T10-A','T10-B','T10-C','T10-D','T10-E') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Scenario $scenario -Transport Simulation -SimulationScenario Expected -ReportDirectory $scratch | Out-Null
        $code = $LASTEXITCODE; $file = Get-ChildItem $scratch -Filter "$scenario-*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
        $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $serialized = $report | ConvertTo-Json -Depth 8
        $sensitive = $serialized -match '"(password|accessToken|refresh_token|authorization|email|response|conversationId|marker)"'
        $ok = $code -eq 0 -and $report.automaticStatus -eq 'PASS' -and $report.manualEvaluation -eq 'PENDING' -and $report.postgresStorageVerification -eq 'PENDING' -and -not $sensitive
        Write-Host ("{0}: {1} esperado" -f $(if ($ok) {'PASS'} else {'FAIL'}), $scenario); if (-not $ok) { $failed++ }
    }
    foreach ($pair in @(@('T10-A','MissingMemory'),@('T10-B','LeakedMemory'),@('T10-C','LeakedMemory'),@('T10-A','HttpError'),@('T10-A','InvalidJson'),@('T10-E','WrongError'))) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Scenario $pair[0] -Transport Simulation -SimulationScenario $pair[1] -ReportDirectory $scratch | Out-Null
        $code = $LASTEXITCODE; $file = Get-ChildItem $scratch -Filter "$($pair[0])-*.json" | Sort-Object LastWriteTime | Select-Object -Last 1; $report = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
        $ok = $code -eq 1 -and $report.automaticStatus -eq 'FAIL'; Write-Host ("{0}: detecta {1}/{2}" -f $(if ($ok) {'PASS'} else {'FAIL'}), $pair[0], $pair[1]); if (-not $ok) { $failed++ }
    }
    $diagnosticExpectations = @(
        @{ Simulation = 'Expected'; Code = 'contract_match'; Exit = 0; Status = 'PASS' },
        @{ Simulation = 'HttpError'; Code = 'http_status_mismatch'; Exit = 1; Status = 'FAIL' },
        @{ Simulation = 'InvalidJson'; Code = 'invalid_json'; Exit = 1; Status = 'FAIL' },
        @{ Simulation = 'MissingError'; Code = 'missing_error_field'; Exit = 1; Status = 'FAIL' },
        @{ Simulation = 'WrongError'; Code = 'error_value_mismatch'; Exit = 1; Status = 'FAIL' }
    )
    foreach ($scenario in 'T10-D','T10-E') {
        foreach ($expectation in $diagnosticExpectations) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Scenario $scenario -Transport Simulation -SimulationScenario $expectation.Simulation -ReportDirectory $scratch | Out-Null
            $code = $LASTEXITCODE
            $file = Get-ChildItem $scratch -Filter "$scenario-*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
            $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $items = @($report.requestDiagnostics)
            $detailsSafe = @($items | Where-Object {
                $_.PSObject.Properties.Name -contains 'observedHttpStatus' -and
                $_.PSObject.Properties.Name -contains 'jsonValid' -and
                $_.PSObject.Properties.Name -contains 'errorFieldExists' -and
                $_.PSObject.Properties.Name -contains 'errorValueMatches'
            }).Count -eq 2
            $bothDiagnosed = $items.Count -eq 2 -and $items[0].diagnosticCode -eq $expectation.Code -and $items[1].diagnosticCode -eq $expectation.Code
            $ok = $code -eq $expectation.Exit -and $report.automaticStatus -eq $expectation.Status -and $detailsSafe -and $bothDiagnosed
            Write-Host ("{0}: {1} distingue {2}" -f $(if ($ok) {'PASS'} else {'FAIL'}), $scenario, $expectation.Code)
            if (-not $ok) { $failed++ }
        }
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Scenario T10-C -Transport Simulation -SimulationScenario MissingSecondAccount -ReportDirectory $scratch | Out-Null
    $file = Get-ChildItem $scratch -Filter 'T10-C-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1; $report = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
    $ok = $LASTEXITCODE -eq 0 -and $report.automaticStatus -eq 'SKIP'; Write-Host ("{0}: T10-C sin segunda cuenta queda SKIP" -f $(if ($ok) {'PASS'} else {'FAIL'})); if (-not $ok) { $failed++ }
    if ($failed -gt 0) { exit 1 }; exit 0
} finally { if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force } }
