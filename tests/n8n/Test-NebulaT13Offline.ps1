[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-NebulaT13.ps1'
$definitionsPath = Join-Path $PSScriptRoot 't13-scenarios.json'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nebula-t13-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

try {
    $failed = 0
    $definitions = [IO.File]::ReadAllText($definitionsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $definitionsValid = $definitions.'T13-A'.expectedTool -eq 'historial_academico' -and
                        $definitions.'T13-B'.expectedTool -eq 'progreso_creditos' -and
                        $definitions.'T13-A'.message -is [string] -and
                        $definitions.'T13-B'.message -is [string]
    Write-Host ("{0}: definiciones T13" -f $(if ($definitionsValid) { 'PASS' } else { 'FAIL' }))
    if (-not $definitionsValid) { $failed++ }

    $expectations = @(
        @{ Name='Valid'; Status='PASS'; Exit=0; Diagnostic='structure_valid_manual_tool_review_pending' },
        @{ Name='AuthRejected'; Status='FAIL'; Exit=1; Diagnostic='auth_rejected_or_missing_token' },
        @{ Name='HttpError'; Status='FAIL'; Exit=1; Diagnostic='unexpected_http_status' },
        @{ Name='InvalidJson'; Status='FAIL'; Exit=1; Diagnostic='invalid_json' },
        @{ Name='SuccessFalse'; Status='FAIL'; Exit=1; Diagnostic='success_must_be_boolean_true' },
        @{ Name='EmptyResponse'; Status='FAIL'; Exit=1; Diagnostic='response_empty_or_not_significant' },
        @{ Name='TransportTimeout'; Status='FAIL'; Exit=1; Diagnostic='transport_timeout' },
        @{ Name='ProcessingError'; Status='FAIL'; Exit=1; Diagnostic='processing_exception' }
    )
    foreach ($scenario in 'T13-A','T13-B') {
        foreach ($expectation in $expectations) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner `
                -Scenario $scenario -Transport Simulation -SimulationScenario $expectation.Name -ReportDirectory $scratch | Out-Null
            $code = $LASTEXITCODE
            $file = Get-ChildItem $scratch -Filter "$scenario-*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
            $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $serialized = $report | ConvertTo-Json -Depth 7
            $forbidden = $serialized -match '"(password|accessToken|access_token|refresh_token|authorization|email|conversationId|response|message|course_name|final_grade|credits)"'
            $expectedTool = if ($scenario -eq 'T13-A') { 'historial_academico' } else { 'progreso_creditos' }
            $ok = $code -eq $expectation.Exit -and
                  $report.automaticStatus -eq $expectation.Status -and
                  $report.diagnostic -eq $expectation.Diagnostic -and
                  $report.expectedTool -eq $expectedTool -and
                  $report.academicEvaluation -eq 'PENDING' -and
                  $report.toolExecutionEvidence -eq 'PENDING' -and
                  -not $forbidden
            Write-Host ("{0}: {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $scenario, $expectation.Name)
            if (-not $ok) { $failed++ }
        }
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Scenario T13-A -Transport Real -ReportDirectory $scratch | Out-Null
    $file = Get-ChildItem $scratch -Filter 'T13-A-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
    $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $guardPassed = $LASTEXITCODE -eq 0 -and $report.automaticStatus -eq 'SKIP' -and $report.diagnostic -eq 'network_not_authorized'
    Write-Host ("{0}: red bloqueada sin AllowNetwork" -f $(if ($guardPassed) { 'PASS' } else { 'FAIL' }))
    if (-not $guardPassed) { $failed++ }

    if ($failed -gt 0) { exit 1 }
    exit 0
} finally {
    if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
