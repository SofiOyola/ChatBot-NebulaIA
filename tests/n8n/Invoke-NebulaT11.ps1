[CmdletBinding()]
param(
    [ValidateSet('Real', 'Simulation')]
    [string]$Transport = 'Real',

    [ValidateSet('Valid', 'AuthRejected', 'HttpError', 'InvalidJson', 'SuccessFalse', 'EmptyResponse', 'TransportTimeout', 'ProcessingError')]
    [string]$SimulationScenario = 'Valid',

    [switch]$AllowNetwork,
    [string]$ReportDirectory = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$supabaseUrl = 'https://icsekpkuheckfkgkqosg.supabase.co'
$webhookUrl = 'https://sofinebula.app.n8n.cloud/webhook-test/nebula-v2/chat'
$conversationId = 'T11_' + [Guid]::NewGuid().ToString('N').Substring(0, 20)
$requestDefinition = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 't11-request.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) { $ReportDirectory = Join-Path $PSScriptRoot 'reports' }

function ConvertFrom-PrivateSecureString {
    param([Parameter(Mandatory = $true)][Security.SecureString]$Value)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Invoke-JsonRequest {
    param([string]$Url, $Body, [hashtable]$Headers)
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.Method = 'POST'
    $request.ContentType = 'application/json; charset=utf-8'
    $request.Accept = 'application/json'
    $request.Timeout = 60000
    foreach ($name in $Headers.Keys) { $request.Headers[$name] = $Headers[$name] }
    $bytes = $utf8NoBom.GetBytes(($Body | ConvertTo-Json -Compress -Depth 10))
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream()
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    try { $httpResponse = [Net.HttpWebResponse]$request.GetResponse() }
    catch [Net.WebException] {
        if ($null -eq $_.Exception.Response) { throw }
        $httpResponse = [Net.HttpWebResponse]$_.Exception.Response
    }
    try {
        $reader = New-Object IO.StreamReader($httpResponse.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $bodyText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{ StatusCode = [int]$httpResponse.StatusCode; Body = $bodyText }
    }
    finally { $httpResponse.Dispose() }
}

function Get-SimulatedExchange {
    $payload = [ordered]@{
        success = $true
        project = 'Nebula 2.0'
        response = 'El tercer semestre contiene siete posiciones curriculares y suma diecisiete creditos. La evaluacion academica y la evidencia MCP siguen pendientes.'
    }
    switch ($SimulationScenario) {
        'TransportTimeout' { throw (New-Object Net.WebException('simulated transport timeout', [Net.WebExceptionStatus]::Timeout)) }
        'ProcessingError' { throw (New-Object InvalidOperationException('simulated processing error')) }
        'AuthRejected' { return [pscustomobject]@{ AuthStatus = 400; Token = $null; WebhookStatus = $null; WebhookBody = $null } }
        'HttpError' { return [pscustomobject]@{ AuthStatus = 200; Token = 'memory-only-fixture'; WebhookStatus = 500; WebhookBody = ($payload | ConvertTo-Json -Compress) } }
        'InvalidJson' { return [pscustomobject]@{ AuthStatus = 200; Token = 'memory-only-fixture'; WebhookStatus = 200; WebhookBody = '{not-json' } }
        'SuccessFalse' { $payload.success = $false }
        'EmptyResponse' { $payload.response = '   ' }
    }
    return [pscustomobject]@{ AuthStatus = 200; Token = 'memory-only-fixture'; WebhookStatus = 200; WebhookBody = ($payload | ConvertTo-Json -Compress) }
}

function Test-ResponseContract {
    param([int]$StatusCode, [string]$Body)
    $result = [ordered]@{ JsonValid = $false; SuccessIsTrue = $false; ResponseMeaningful = $false; Text = $null; Diagnostic = 'not_checked' }
    if ($StatusCode -ne 200) { $result.Diagnostic = 'unexpected_http_status'; return [pscustomobject]$result }
    try { $json = $Body | ConvertFrom-Json; $result.JsonValid = $true }
    catch { $result.Diagnostic = 'invalid_json'; return [pscustomobject]$result }
    $result.SuccessIsTrue = ($json.success -is [bool]) -and $json.success -eq $true
    if ($json.response -is [string]) {
        $result.Text = [string]$json.response
        $result.ResponseMeaningful = $result.Text.Trim().Length -ge 20
    }
    if (-not $result.SuccessIsTrue) { $result.Diagnostic = 'success_must_be_boolean_true' }
    elseif (-not $result.ResponseMeaningful) { $result.Diagnostic = 'response_empty_or_not_significant' }
    else { $result.Diagnostic = 'transport_and_structure_valid_manual_checks_pending' }
    return [pscustomobject]$result
}

function Save-SafeReport {
    param($Value)
    if (-not (Test-Path -LiteralPath $ReportDirectory)) { New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null }
    $path = Join-Path $ReportDirectory ('T11-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '.json')
    [IO.File]::WriteAllText($path, ($Value | ConvertTo-Json -Depth 6), $utf8NoBom)
    return $path
}

$report = [ordered]@{
    caseId = 'T11'
    transport = $Transport
    automaticStatus = 'SKIP'
    authHttpStatus = $null
    webhookHttpStatus = $null
    jsonValid = $false
    successIsTrue = $false
    responseMeaningful = $false
    conversationIdValid = ($conversationId -cmatch '^[A-Za-z0-9_-]{8,64}$')
    expectedPositionCount = 7
    expectedTotalCredits = 17
    academicEvaluation = 'PENDING'
    mcpExecutionEvidence = 'PENDING'
    timeoutConfiguredMs = 60000
    authDurationMs = $null
    webhookDurationMs = $null
    totalDurationMs = $null
    failureStage = $null
    failureCategory = $null
    transportStatus = $null
    diagnostic = 'not_started'
    timestampUtc = [DateTime]::UtcNow.ToString('o')
}
$exitCode = 0
$accessToken = $null
$responseText = $null
$passwordPlain = $null
$publicKeyPlain = $null
$currentStage = 'initialization'
$totalClock = [Diagnostics.Stopwatch]::StartNew()

try {
    if ($Transport -eq 'Simulation') {
        $currentStage = if ($SimulationScenario -eq 'TransportTimeout') { 'webhook_transport' } elseif ($SimulationScenario -eq 'ProcessingError') { 'webhook_response_processing' } else { 'simulation' }
        $exchange = Get-SimulatedExchange
        $report.authHttpStatus = $exchange.AuthStatus
        $accessToken = $exchange.Token
        if ($exchange.AuthStatus -ne 200 -or [string]::IsNullOrWhiteSpace($accessToken)) {
            $report.automaticStatus = 'FAIL'; $report.diagnostic = 'auth_rejected_or_missing_token'; $exitCode = 1
        } else {
            $report.webhookHttpStatus = $exchange.WebhookStatus
            $validation = Test-ResponseContract $exchange.WebhookStatus $exchange.WebhookBody
            $report.jsonValid = $validation.JsonValid
            $report.successIsTrue = $validation.SuccessIsTrue
            $report.responseMeaningful = $validation.ResponseMeaningful
            $report.diagnostic = $validation.Diagnostic
            $responseText = $validation.Text
            if ($validation.JsonValid -and $validation.SuccessIsTrue -and $validation.ResponseMeaningful) { $report.automaticStatus = 'PASS' }
            else { $report.automaticStatus = 'FAIL'; $exitCode = 1 }
        }
    } elseif (-not $AllowNetwork) {
        $report.diagnostic = 'network_not_authorized'
    } else {
        $currentStage = 'credential_input'
        Write-Host 'Las entradas privadas y el token solo se conservaran en memoria.'
        $email = Read-Host 'Correo de la cuenta estudiantil de pruebas'
        $passwordSecure = Read-Host 'Contrasena de la cuenta de pruebas' -AsSecureString
        $publicKeySecure = Read-Host 'Clave publica publishable de Supabase' -AsSecureString
        if ([string]::IsNullOrWhiteSpace($email)) { throw 'missing_email' }
        $passwordPlain = ConvertFrom-PrivateSecureString $passwordSecure
        $publicKeyPlain = ConvertFrom-PrivateSecureString $publicKeySecure
        if ([string]::IsNullOrWhiteSpace($passwordPlain) -or [string]::IsNullOrWhiteSpace($publicKeyPlain)) { throw 'missing_private_input' }
        $currentStage = 'supabase_auth_transport'
        $authClock = [Diagnostics.Stopwatch]::StartNew()
        try {
            $authResponse = Invoke-JsonRequest ($supabaseUrl + '/auth/v1/token?grant_type=password') @{ email = $email; password = $passwordPlain } @{ apikey = $publicKeyPlain }
        } finally {
            $authClock.Stop()
            $report.authDurationMs = [int64]$authClock.ElapsedMilliseconds
        }
        $report.authHttpStatus = $authResponse.StatusCode
        if ($authResponse.StatusCode -ne 200) {
            $report.automaticStatus = 'FAIL'; $report.diagnostic = 'auth_rejected'; $exitCode = 1
        } else {
            $currentStage = 'supabase_auth_response_processing'
            try { $authJson = $authResponse.Body | ConvertFrom-Json } catch { $authJson = $null }
            if ($null -eq $authJson -or [string]::IsNullOrWhiteSpace($authJson.access_token)) {
                $report.automaticStatus = 'FAIL'; $report.diagnostic = 'auth_response_missing_access_token'; $exitCode = 1
            } else {
                $accessToken = [string]$authJson.access_token
                $authJson = $null; $authResponse = $null; $passwordPlain = $null; [GC]::Collect()
                $currentStage = 'workflow_confirmation'
                $confirmation = Read-Host 'Active Execute workflow en n8n. Escriba EJECUTAR cuando webhook-test este escuchando'
                if ($confirmation -ne 'EJECUTAR') {
                    $report.diagnostic = 'workflow_activation_not_confirmed'
                } else {
                    $currentStage = 'webhook_transport'
                    $webhookClock = [Diagnostics.Stopwatch]::StartNew()
                    try {
                        $webhookResponse = Invoke-JsonRequest $webhookUrl @{ message = $requestDefinition.message; conversationId = $conversationId } @{ Authorization = ('Bearer ' + $accessToken) }
                    } finally {
                        $webhookClock.Stop()
                        $report.webhookDurationMs = [int64]$webhookClock.ElapsedMilliseconds
                    }
                    $report.webhookHttpStatus = $webhookResponse.StatusCode
                    $currentStage = 'webhook_response_processing'
                    $validation = Test-ResponseContract $webhookResponse.StatusCode $webhookResponse.Body
                    $report.jsonValid = $validation.JsonValid
                    $report.successIsTrue = $validation.SuccessIsTrue
                    $report.responseMeaningful = $validation.ResponseMeaningful
                    $report.diagnostic = $validation.Diagnostic
                    $responseText = $validation.Text
                    if ($validation.JsonValid -and $validation.SuccessIsTrue -and $validation.ResponseMeaningful) { $report.automaticStatus = 'PASS' }
                    else { $report.automaticStatus = 'FAIL'; $exitCode = 1 }
                }
            }
        }
    }
} catch {
    $report.automaticStatus = 'FAIL'
    $report.failureStage = $currentStage
    $caughtException = $_.Exception
    if ($caughtException.Message -in 'missing_email','missing_private_input') {
        $report.failureCategory = 'input_validation_error'
        $report.diagnostic = $caughtException.Message
    } elseif ($caughtException -is [Net.WebException]) {
        $report.transportStatus = [string]$caughtException.Status
        $report.failureCategory = if ($caughtException.Status -eq [Net.WebExceptionStatus]::Timeout) { 'transport_timeout' } else { 'transport_web_exception' }
        $report.diagnostic = $report.failureCategory
    } elseif ($caughtException -is [IO.IOException]) {
        $report.failureCategory = 'transport_io_error'
        $report.diagnostic = 'transport_io_error'
    } else {
        $report.failureCategory = 'processing_exception'
        $report.diagnostic = 'processing_exception'
    }
    $exitCode = 1
} finally {
    $accessToken = $null; $passwordPlain = $null; $publicKeyPlain = $null
    $passwordSecure = $null; $publicKeySecure = $null; $email = $null; [GC]::Collect()
}

$totalClock.Stop()
$report.totalDurationMs = [int64]$totalClock.ElapsedMilliseconds

$reportPath = Save-SafeReport ([pscustomobject]$report)
Write-Host ("AUTOMATIC {0}: T11 - {1}" -f $report.automaticStatus, $report.diagnostic)
Write-Host 'ACADEMIC PENDING: compare manualmente las siete posiciones y los 17 creditos.'
Write-Host 'MCP EVIDENCE PENDING: confirme visualmente en n8n que el agente ejecuto MCP Curricular.'
if ($null -ne $responseText) {
    Write-Host "`n--- response (no se guarda en el reporte) ---"
    Write-Host $responseText
    Write-Host '--- fin de response ---'
}
Write-Host ('Reporte seguro: ' + $reportPath)
$responseText = $null
exit $exitCode
