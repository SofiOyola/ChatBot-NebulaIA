[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-NebulaT11.ps1'
$requestPath = Join-Path $PSScriptRoot 't11-request.json'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nebula-t11-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

try {
    $failed = 0
    $request = [IO.File]::ReadAllText($requestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $messageHash = ([BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$request.message)))).Replace('-','').ToLowerInvariant()
    } finally { $sha256.Dispose() }
    $requestValid = $request.PSObject.Properties.Name -contains 'message' -and $request.message -is [string] -and
                    $messageHash -eq '0ae24e7f2c65a50153f3079302c209f4975d23906cbf99975489462312e5fc59'
    Write-Host ("{0}: mensaje T11 exacto cargado como UTF-8" -f $(if ($requestValid) {'PASS'} else {'FAIL'}))
    if (-not $requestValid) { $failed++ }

    $expectations = @(
        @{ Name = 'Valid'; Status = 'PASS'; Exit = 0; Diagnostic = 'transport_and_structure_valid_manual_checks_pending' },
        @{ Name = 'AuthRejected'; Status = 'FAIL'; Exit = 1; Diagnostic = 'auth_rejected_or_missing_token' },
        @{ Name = 'HttpError'; Status = 'FAIL'; Exit = 1; Diagnostic = 'unexpected_http_status' },
        @{ Name = 'InvalidJson'; Status = 'FAIL'; Exit = 1; Diagnostic = 'invalid_json' },
        @{ Name = 'SuccessFalse'; Status = 'FAIL'; Exit = 1; Diagnostic = 'success_must_be_boolean_true' },
        @{ Name = 'EmptyResponse'; Status = 'FAIL'; Exit = 1; Diagnostic = 'response_empty_or_not_significant' },
        @{ Name = 'TransportTimeout'; Status = 'FAIL'; Exit = 1; Diagnostic = 'transport_timeout'; FailureStage = 'webhook_transport'; FailureCategory = 'transport_timeout'; TransportStatus = 'Timeout' },
        @{ Name = 'ProcessingError'; Status = 'FAIL'; Exit = 1; Diagnostic = 'processing_exception'; FailureStage = 'webhook_response_processing'; FailureCategory = 'processing_exception'; TransportStatus = $null }
    )
    foreach ($expectation in $expectations) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Transport Simulation -SimulationScenario $expectation.Name -ReportDirectory $scratch | Out-Null
        $code = $LASTEXITCODE
        $file = Get-ChildItem $scratch -Filter 'T11-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
        $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $serialized = $report | ConvertTo-Json -Depth 6
        $forbidden = $serialized -match '"(password|accessToken|access_token|refresh_token|authorization|email|conversationId|response|message)"'
        $pending = $report.academicEvaluation -eq 'PENDING' -and $report.mcpExecutionEvidence -eq 'PENDING'
        $technicalDiagnostic = if ($expectation.ContainsKey('FailureCategory')) {
            $report.failureStage -eq $expectation.FailureStage -and
            $report.failureCategory -eq $expectation.FailureCategory -and
            $report.transportStatus -eq $expectation.TransportStatus
        } else {
            $null -eq $report.failureCategory -and $null -eq $report.failureStage
        }
        $passed = $code -eq $expectation.Exit -and $report.automaticStatus -eq $expectation.Status -and
                  $report.diagnostic -eq $expectation.Diagnostic -and $report.conversationIdValid -eq $true -and
                  $pending -and $technicalDiagnostic -and $report.timeoutConfiguredMs -eq 60000 -and
                  $report.totalDurationMs -ge 0 -and -not $forbidden
        Write-Host ("{0}: T11 {1}" -f $(if ($passed) {'PASS'} else {'FAIL'}), $expectation.Name)
        if (-not $passed) { $failed++ }
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Transport Real -ReportDirectory $scratch | Out-Null
    $file = Get-ChildItem $scratch -Filter 'T11-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
    $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $guardPassed = $LASTEXITCODE -eq 0 -and $report.automaticStatus -eq 'SKIP' -and $report.diagnostic -eq 'network_not_authorized'
    Write-Host ("{0}: modo real bloqueado sin AllowNetwork" -f $(if ($guardPassed) {'PASS'} else {'FAIL'}))
    if (-not $guardPassed) { $failed++ }

    if ($failed -gt 0) { exit 1 }
    exit 0
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
