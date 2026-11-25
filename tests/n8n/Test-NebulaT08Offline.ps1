[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-NebulaT08.ps1'
. (Join-Path $PSScriptRoot 'JwtTestHelpers.ps1')
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nebula-t08-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

try {
    $failed = 0
    $fixture = 'headerSegment.payloadSegment.Asignature'
    $mutated = New-DeterministicallyInvalidJwt $fixture
    $before = $fixture.Split('.')
    $after = $mutated.Split('.')
    $mutationPassed = $before[0] -ceq $after[0] -and $before[1] -ceq $after[1] -and
                      $before[2] -ceq 'Asignature' -and $after[2] -ceq 'Bsignature'
    Write-Host ("{0}: mutacion determinista solo en firma" -f $(if ($mutationPassed) {'PASS'} else {'FAIL'}))
    if (-not $mutationPassed) { $failed++ }

    $expectations = @(
        @{ Scenario = 'ExpectedUnauthorized'; Status = 'PASS'; Exit = 0 },
        @{ Scenario = 'AuthRejected'; Status = 'FAIL'; Exit = 1 },
        @{ Scenario = 'WrongStatus'; Status = 'FAIL'; Exit = 1 },
        @{ Scenario = 'WrongJson'; Status = 'FAIL'; Exit = 1 },
        @{ Scenario = 'MalformedToken'; Status = 'FAIL'; Exit = 1 }
    )
    foreach ($expectation in $expectations) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner `
            -Transport Simulation -SimulationScenario $expectation.Scenario -ReportDirectory $scratch | Out-Null
        $processExit = $LASTEXITCODE
        $file = Get-ChildItem $scratch -Filter 'T08-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
        $report = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $serialized = $report | ConvertTo-Json -Depth 6
        $sensitiveNames = @('password','accessToken','access_token','refresh_token','authorization','email','responseBody','jwt')
        $containsSensitiveField = @($sensitiveNames | Where-Object { $serialized -match ('"' + [regex]::Escape($_) + '"') }).Count -gt 0
        $manualPending = $report.manualEvidence -like 'PENDING:*'
        $passed = $processExit -eq $expectation.Exit -and $report.status -eq $expectation.Status -and
                  -not $containsSensitiveField -and $manualPending
        Write-Host ("{0}: T08 {1}" -f $(if ($passed) {'PASS'} else {'FAIL'}), $expectation.Scenario)
        if (-not $passed) { $failed++ }
    }
    if ($failed -gt 0) { exit 1 }
    exit 0
}
finally {
    $fixture = $null; $mutated = $null; $before = $null; $after = $null
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
