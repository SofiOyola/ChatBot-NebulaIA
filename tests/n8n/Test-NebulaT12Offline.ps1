[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-NebulaT12.ps1'
$migration = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'supabase\migrations\20261124040000_secure_academic_read_functions.sql'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nebula-t12-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $failed = 0
    $sql = [IO.File]::ReadAllText($migration, [Text.Encoding]::UTF8)
    $fields = @('position_id text','course_name text','curriculum_semester integer','credits integer','attempt_number integer','final_grade numeric','outcome text','source_type text','total_curriculum_credits bigint','verified_approved_credits bigint','reported_only_approved_credits bigint','pending_or_unverified_credits bigint')
    $contractValid = @($fields | Where-Object { $sql -notmatch [regex]::Escape($_) }).Count -eq 0 -and $sql -match 'get_academic_history\(\)' -and $sql -match 'get_credit_progress\(\)'
    Write-Host ("{0}: contratos locales de ambas RPC" -f $(if ($contractValid) {'PASS'} else {'FAIL'})); if (-not $contractValid) { $failed++ }
    $expectations = @(
        @{ Name='ValidData'; Status='PASS'; Categories=@('DATA','DATA'); Exit=0 },
        @{ Name='ValidNoData'; Status='PASS'; Categories=@('NO_DATA','NO_DATA'); Exit=0 },
        @{ Name='HistoryHttpError'; Status='FAIL'; Categories=@('HTTP_ERROR','DATA'); Exit=1 },
        @{ Name='ProgressHttpError'; Status='FAIL'; Categories=@('DATA','HTTP_ERROR'); Exit=1 },
        @{ Name='InvalidJson'; Status='FAIL'; Categories=@('INVALID_JSON','INVALID_JSON'); Exit=1 },
        @{ Name='InvalidHistoryStructure'; Status='FAIL'; Categories=@('INVALID_STRUCTURE','DATA'); Exit=1 },
        @{ Name='InvalidProgressStructure'; Status='FAIL'; Categories=@('DATA','INVALID_STRUCTURE'); Exit=1 },
        @{ Name='TransportTimeout'; Status='FAIL'; Categories=@('TRANSPORT_ERROR','DATA'); Exit=1 }
    )
    foreach ($expectation in $expectations) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Transport Simulation -SimulationScenario $expectation.Name -ReportDirectory $scratch | Out-Null
        $code=$LASTEXITCODE; $file=Get-ChildItem $scratch -Filter 'T12-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1; $report=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)|ConvertFrom-Json; $items=@($report.rpcResults)
        $serialized=$report|ConvertTo-Json -Depth 8; $forbidden=$serialized -match '"(password|accessToken|access_token|refresh_token|authorization|email|body|position_id|course_name|final_grade|conversationId)"'
        $ok=$code -eq $expectation.Exit -and $report.automaticStatus -eq $expectation.Status -and $items.Count -eq 2 -and $items[0].category -eq $expectation.Categories[0] -and $items[1].category -eq $expectation.Categories[1] -and -not $forbidden
        Write-Host ("{0}: T12 {1}" -f $(if($ok){'PASS'}else{'FAIL'}),$expectation.Name); if(-not $ok){$failed++}
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Transport Simulation -SimulationScenario AuthRejected -ReportDirectory $scratch | Out-Null
    $file=Get-ChildItem $scratch -Filter 'T12-*.json'|Sort-Object LastWriteTime|Select-Object -Last 1;$report=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json;$ok=$LASTEXITCODE -eq 1 -and $report.diagnostic -eq 'auth_rejected';Write-Host("{0}: T12 AuthRejected" -f $(if($ok){'PASS'}else{'FAIL'}));if(-not $ok){$failed++}
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Transport Real -ReportDirectory $scratch | Out-Null
    $file=Get-ChildItem $scratch -Filter 'T12-*.json'|Sort-Object LastWriteTime|Select-Object -Last 1;$report=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json;$ok=$LASTEXITCODE -eq 0 -and $report.automaticStatus -eq 'SKIP' -and $report.diagnostic -eq 'network_not_authorized';Write-Host("{0}: red bloqueada sin AllowNetwork" -f $(if($ok){'PASS'}else{'FAIL'}));if(-not $ok){$failed++}
    if($failed -gt 0){exit 1};exit 0
} finally { if(Test-Path $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force} }
