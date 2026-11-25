[CmdletBinding()]
param(
    [ValidateSet('Real', 'Simulation')]
    [string]$Transport = 'Real',
    [ValidateSet('ValidData', 'ValidNoData', 'AuthRejected', 'HistoryHttpError', 'ProgressHttpError', 'InvalidJson', 'InvalidHistoryStructure', 'InvalidProgressStructure', 'TransportTimeout')]
    [string]$SimulationScenario = 'ValidNoData',
    [switch]$AllowNetwork,
    [string]$ReportDirectory = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$supabaseUrl = 'https://icsekpkuheckfkgkqosg.supabase.co'
$timeoutMs = 60000
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) { $ReportDirectory = Join-Path $PSScriptRoot 'reports' }

function ConvertFrom-PrivateSecureString {
    param([Security.SecureString]$Value)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Invoke-JsonRequest {
    param([string]$Url, $Body, [hashtable]$Headers)
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.Method = 'POST'; $request.ContentType = 'application/json; charset=utf-8'; $request.Accept = 'application/json'; $request.Timeout = $timeoutMs
    foreach ($name in $Headers.Keys) { $request.Headers[$name] = $Headers[$name] }
    $bytes = $utf8NoBom.GetBytes(($Body | ConvertTo-Json -Compress -Depth 5)); $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream(); try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    try { $response = [Net.HttpWebResponse]$request.GetResponse() }
    catch [Net.WebException] { if ($null -eq $_.Exception.Response) { throw }; $response = [Net.HttpWebResponse]$_.Exception.Response }
    try {
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $text }
    } finally { $response.Dispose() }
}

function Test-IntegerValue {
    param($Value)
    return $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
           $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]
}

function Test-RequiredProperties {
    param($Value, [string[]]$Names)
    foreach ($name in $Names) { if ($null -eq $Value.PSObject.Properties[$name]) { return $false } }
    return $true
}

function Test-HistoryBody {
    param([string]$Body)
    $result = [ordered]@{ JsonValid = $false; StructureValid = $false; Category = 'INVALID_JSON'; RecordCount = 0 }
    $trimmed = $Body.Trim()
    if (-not ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) { $result.Category = 'INVALID_STRUCTURE'; return [pscustomobject]$result }
    try { $json = $Body | ConvertFrom-Json; $result.JsonValid = $true } catch { return [pscustomobject]$result }
    if ($trimmed -eq '[]') { $result.StructureValid = $true; $result.Category = 'NO_DATA'; return [pscustomobject]$result }
    $rows = @($json)
    $required = @('position_id','course_name','curriculum_semester','credits','attempt_number','final_grade','outcome','source_type')
    $allowedOutcomes = @('passed','failed','withdrawn','in_progress','unknown')
    $allowedSources = @('student_reported','institution_verified','admin_recorded')
    foreach ($row in $rows) {
        if (-not (Test-RequiredProperties $row $required)) { $result.Category = 'INVALID_STRUCTURE'; return [pscustomobject]$result }
        $gradeValid = $null -eq $row.final_grade -or $row.final_grade -is [ValueType]
        if (-not ($row.position_id -is [string]) -or -not ($row.course_name -is [string]) -or
            -not (Test-IntegerValue $row.curriculum_semester) -or -not (Test-IntegerValue $row.credits) -or
            -not (Test-IntegerValue $row.attempt_number) -or -not $gradeValid -or
            $row.outcome -notin $allowedOutcomes -or $row.source_type -notin $allowedSources) {
            $result.Category = 'INVALID_STRUCTURE'; return [pscustomobject]$result
        }
    }
    $result.StructureValid = $true; $result.Category = 'DATA'; $result.RecordCount = $rows.Count
    return [pscustomobject]$result
}

function Test-ProgressBody {
    param([string]$Body)
    $result = [ordered]@{ JsonValid = $false; StructureValid = $false; Category = 'INVALID_JSON'; RecordCount = 0 }
    $trimmed = $Body.Trim()
    if (-not ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']'))) { $result.Category = 'INVALID_STRUCTURE'; return [pscustomobject]$result }
    try { $json = $Body | ConvertFrom-Json; $result.JsonValid = $true } catch { return [pscustomobject]$result }
    if ($trimmed -eq '[]') { $result.StructureValid = $true; $result.Category = 'NO_DATA'; return [pscustomobject]$result }
    $rows = @($json)
    if ($rows.Count -ne 1) { $result.Category = 'INVALID_STRUCTURE'; return [pscustomobject]$result }
    $row = $rows[0]
    $names = @('total_curriculum_credits','verified_approved_credits','reported_only_approved_credits','pending_or_unverified_credits')
    if (-not (Test-RequiredProperties $row $names)) { $result.Category = 'INVALID_STRUCTURE'; return [pscustomobject]$result }
    foreach ($name in $names) { if (-not (Test-IntegerValue $row.$name) -or $row.$name -lt 0) { $result.Category = 'INVALID_STRUCTURE'; return [pscustomobject]$result } }
    $parts = $row.verified_approved_credits + $row.reported_only_approved_credits + $row.pending_or_unverified_credits
    if ($parts -ne $row.total_curriculum_credits) { $result.Category = 'INVALID_STRUCTURE'; return [pscustomobject]$result }
    $result.StructureValid = $true; $result.Category = 'DATA'; $result.RecordCount = 1
    return [pscustomobject]$result
}

function New-RpcResult {
    param([string]$Name)
    return [ordered]@{ rpc = $Name; httpStatus = $null; durationMs = $null; jsonValid = $false; structureValid = $false; category = 'NOT_RUN'; recordCount = 0; failureCategory = $null; transportStatus = $null }
}

function Get-SimulatedResponse {
    param([string]$Name)
    if ($SimulationScenario -eq 'TransportTimeout' -and $Name -eq 'historial_academico') { throw (New-Object Net.WebException('simulated', [Net.WebExceptionStatus]::Timeout)) }
    if ($SimulationScenario -eq 'InvalidJson') { return [pscustomobject]@{ StatusCode = 200; Body = '[not-json]' } }
    if ($SimulationScenario -eq 'HistoryHttpError' -and $Name -eq 'historial_academico') { return [pscustomobject]@{ StatusCode = 403; Body = '{}' } }
    if ($SimulationScenario -eq 'ProgressHttpError' -and $Name -eq 'progreso_creditos') { return [pscustomobject]@{ StatusCode = 500; Body = '{}' } }
    if ($SimulationScenario -eq 'InvalidHistoryStructure' -and $Name -eq 'historial_academico') { return [pscustomobject]@{ StatusCode = 200; Body = '[{"position_id":"fixture"}]' } }
    if ($SimulationScenario -eq 'InvalidProgressStructure' -and $Name -eq 'progreso_creditos') { return [pscustomobject]@{ StatusCode = 200; Body = '[{"total_curriculum_credits":151}]' } }
    if ($SimulationScenario -eq 'ValidNoData') { return [pscustomobject]@{ StatusCode = 200; Body = '[]' } }
    if ($Name -eq 'historial_academico') {
        return [pscustomobject]@{ StatusCode = 200; Body = '[{"position_id":"fixture","course_name":"Fixture","curriculum_semester":1,"credits":3,"attempt_number":1,"final_grade":null,"outcome":"unknown","source_type":"student_reported"}]' }
    }
    return [pscustomobject]@{ StatusCode = 200; Body = '[{"total_curriculum_credits":151,"verified_approved_credits":0,"reported_only_approved_credits":0,"pending_or_unverified_credits":151}]' }
}

function Save-SafeReport {
    param($Value)
    if (-not (Test-Path $ReportDirectory)) { New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null }
    $path = Join-Path $ReportDirectory ('T12-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '.json')
    [IO.File]::WriteAllText($path, ($Value | ConvertTo-Json -Depth 8), $utf8NoBom); return $path
}

$report = [ordered]@{ caseId = 'T12'; transport = $Transport; automaticStatus = 'SKIP'; authHttpStatus = $null; authDurationMs = $null; timeoutConfiguredMs = $timeoutMs; rpcResults = @(); diagnostic = 'not_started'; timestampUtc = [DateTime]::UtcNow.ToString('o') }
$exitCode = 0; $token = $null; $publicKey = $null

try {
    if ($Transport -eq 'Simulation' -and $SimulationScenario -eq 'AuthRejected') {
        $report.authHttpStatus = 400; $report.automaticStatus = 'FAIL'; $report.diagnostic = 'auth_rejected'; $exitCode = 1
    } elseif ($Transport -eq 'Real' -and -not $AllowNetwork) {
        $report.diagnostic = 'network_not_authorized'
    } else {
        if ($Transport -eq 'Real') {
            $email = Read-Host 'Correo de la cuenta estudiantil de pruebas'
            $passwordSecure = Read-Host 'Contrasena de la cuenta de pruebas' -AsSecureString
            $keySecure = Read-Host 'Clave publica publishable de Supabase' -AsSecureString
            $password = ConvertFrom-PrivateSecureString $passwordSecure; $publicKey = ConvertFrom-PrivateSecureString $keySecure
            $authClock = [Diagnostics.Stopwatch]::StartNew()
            try { $auth = Invoke-JsonRequest ($supabaseUrl + '/auth/v1/token?grant_type=password') @{ email = $email; password = $password } @{ apikey = $publicKey } } finally { $authClock.Stop(); $report.authDurationMs = [int64]$authClock.ElapsedMilliseconds }
            $report.authHttpStatus = $auth.StatusCode
            if ($auth.StatusCode -ne 200) { throw 'auth_rejected' }
            try { $authJson = $auth.Body | ConvertFrom-Json } catch { $authJson = $null }
            if ($null -eq $authJson -or [string]::IsNullOrWhiteSpace($authJson.access_token)) { throw 'auth_response_missing_access_token' }
            $token = [string]$authJson.access_token; $auth = $null; $authJson = $null; $password = $null; [GC]::Collect()
        } else { $report.authHttpStatus = 200; $token = 'memory-only-fixture'; $publicKey = 'public-fixture' }

        foreach ($definition in @(
            @{ Name = 'historial_academico'; Function = 'get_academic_history' },
            @{ Name = 'progreso_creditos'; Function = 'get_credit_progress' }
        )) {
            $item = New-RpcResult $definition.Name
            if ($Transport -eq 'Real') {
                $confirm = Read-Host ("Escriba EJECUTAR para consultar " + $definition.Name)
                if ($confirm -ne 'EJECUTAR') { $item.category = 'SKIP'; $report.rpcResults += [pscustomobject]$item; continue }
            }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            try {
                $response = if ($Transport -eq 'Simulation') { Get-SimulatedResponse $definition.Name } else { Invoke-JsonRequest ($supabaseUrl + '/rest/v1/rpc/' + $definition.Function) @{} @{ apikey = $publicKey; Authorization = ('Bearer ' + $token) } }
                $item.httpStatus = $response.StatusCode
                if ($response.StatusCode -ne 200) { $item.category = 'HTTP_ERROR'; $item.failureCategory = 'unexpected_http_status' }
                else {
                    $validation = if ($definition.Name -eq 'historial_academico') { Test-HistoryBody $response.Body } else { Test-ProgressBody $response.Body }
                    $item.jsonValid = $validation.JsonValid; $item.structureValid = $validation.StructureValid; $item.category = $validation.Category; $item.recordCount = $validation.RecordCount
                }
            } catch {
                $item.category = 'TRANSPORT_ERROR'
                if ($_.Exception -is [Net.WebException]) { $item.transportStatus = [string]$_.Exception.Status; $item.failureCategory = if ($_.Exception.Status -eq [Net.WebExceptionStatus]::Timeout) { 'transport_timeout' } else { 'transport_web_exception' } }
                elseif ($_.Exception -is [IO.IOException]) { $item.failureCategory = 'transport_io_error' } else { $item.failureCategory = 'processing_exception' }
            } finally { $clock.Stop(); $item.durationMs = [int64]$clock.ElapsedMilliseconds }
            $report.rpcResults += [pscustomobject]$item
        }
        $bad = @($report.rpcResults | Where-Object { $_.category -notin @('DATA','NO_DATA') })
        if ($bad.Count -eq 0 -and $report.rpcResults.Count -eq 2) { $report.automaticStatus = 'PASS'; $report.diagnostic = 'rpc_contracts_valid' }
        elseif (@($report.rpcResults | Where-Object { $_.category -eq 'SKIP' }).Count -gt 0) { $report.automaticStatus = 'SKIP'; $report.diagnostic = 'request_not_confirmed' }
        else { $report.automaticStatus = 'FAIL'; $report.diagnostic = 'one_or_more_rpc_checks_failed'; $exitCode = 1 }
    }
} catch {
    $report.automaticStatus = 'FAIL'; $report.diagnostic = if ($_.Exception.Message -in @('auth_rejected','auth_response_missing_access_token')) { $_.Exception.Message } else { 'safe_auth_or_processing_error' }; $exitCode = 1
} finally {
    $token = $null; $publicKey = $null; $password = $null; $passwordSecure = $null; $keySecure = $null; $email = $null; [GC]::Collect()
}

$path = Save-SafeReport ([pscustomobject]$report)
Write-Host ("AUTOMATIC {0}: T12 - {1}" -f $report.automaticStatus, $report.diagnostic)
foreach ($item in $report.rpcResults) { Write-Host ("{0}: category={1}, records={2}, http={3}, jsonValid={4}, structureValid={5}" -f $item.rpc, $item.category, $item.recordCount, $item.httpStatus, $item.jsonValid, $item.structureValid) }
Write-Host ('Reporte seguro: ' + $path)
exit $exitCode
