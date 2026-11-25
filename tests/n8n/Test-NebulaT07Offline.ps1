[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-NebulaT07.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nebula-t07-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

try {
    $expectations = @(
        @{ Scenario = 'Success'; ExpectedStatus = 'PASS'; ExpectedExit = 0 },
        @{ Scenario = 'AuthRejected'; ExpectedStatus = 'FAIL'; ExpectedExit = 1 },
        @{ Scenario = 'WebhookRejected'; ExpectedStatus = 'FAIL'; ExpectedExit = 1 },
        @{ Scenario = 'InvalidJson'; ExpectedStatus = 'FAIL'; ExpectedExit = 1 }
    )
    $failed = 0
    foreach ($expectation in $expectations) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner `
            -Transport Simulation -SimulationScenario $expectation.Scenario -ReportDirectory $scratch | Out-Null
        $processExit = $LASTEXITCODE
        $file = Get-ChildItem $scratch -Filter 'T07-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
        $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $sensitiveNames = @('password','accessToken','access_token','refresh_token','authorization','email','responseBody')
        $serialized = $report | ConvertTo-Json -Depth 6
        $containsSensitiveField = @($sensitiveNames | Where-Object { $serialized -match ('"' + [regex]::Escape($_) + '"') }).Count -gt 0
        $passed = $processExit -eq $expectation.ExpectedExit -and `
                  $report.status -eq $expectation.ExpectedStatus -and `
                  $report.conversationIdValid -eq $true -and `
                  -not $containsSensitiveField
        Write-Host ("{0}: T07 {1}" -f $(if ($passed) {'PASS'} else {'FAIL'}), $expectation.Scenario)
        if (-not $passed) { $failed++ }
    }
    if ($failed -gt 0) { exit 1 }
    exit 0
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
