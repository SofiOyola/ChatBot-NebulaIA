[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('T13-A', 'T13-B')]
    [string]$Scenario,
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
$timeoutMs = 60000
$conversationId = 'T13_' + [Guid]::NewGuid().ToString('N').Substring(0, 20)
$definitions = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 't13-scenarios.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$selected = $definitions.PSObject.Properties[$Scenario].Value
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
    $bytes = $utf8NoBom.GetBytes(($Body | ConvertTo-Json -Compress -Depth 8)); $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream(); try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    try { $response = [Net.HttpWebResponse]$request.GetResponse() }
    catch [Net.WebException] { if ($null -eq $_.Exception.Response) { throw }; $response = [Net.HttpWebResponse]$_.Exception.Response }
    try {
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $text }
    } finally { $response.Dispose() }
}

function Get-SimulatedExchange {
    if ($SimulationScenario -eq 'TransportTimeout') { throw (New-Object Net.WebException('simulated', [Net.WebExceptionStatus]::Timeout)) }
    if ($SimulationScenario -eq 'ProcessingError') { throw (New-Object InvalidOperationException('simulated')) }
    $payload = [ordered]@{ success = $true; project = 'Nebula 2.0'; response = 'Respuesta academica simulada suficiente para validar solamente el contrato estructural.' }
    switch ($SimulationScenario) {
        'AuthRejected' { return [pscustomobject]@{ AuthStatus=400; Token=$null; WebhookStatus=$null; WebhookBody=$null } }
        'HttpError' { return [pscustomobject]@{ AuthStatus=200; Token='memory-only-fixture'; WebhookStatus=500; WebhookBody=($payload|ConvertTo-Json -Compress) } }
        'InvalidJson' { return [pscustomobject]@{ AuthStatus=200; Token='memory-only-fixture'; WebhookStatus=200; WebhookBody='{not-json' } }
        'SuccessFalse' { $payload.success = $false }
        'EmptyResponse' { $payload.response = '   ' }
    }
    return [pscustomobject]@{ AuthStatus=200; Token='memory-only-fixture'; WebhookStatus=200; WebhookBody=($payload|ConvertTo-Json -Compress) }
}

function Test-ResponseContract {
    param([int]$StatusCode, [string]$Body)
    $result=[ordered]@{JsonValid=$false;SuccessIsTrue=$false;ResponseMeaningful=$false;Text=$null;Diagnostic='not_checked'}
    if($StatusCode-ne 200){$result.Diagnostic='unexpected_http_status';return [pscustomobject]$result}
    try{$json=$Body|ConvertFrom-Json;$result.JsonValid=$true}catch{$result.Diagnostic='invalid_json';return [pscustomobject]$result}
    $result.SuccessIsTrue=($json.success-is[bool])-and$json.success-eq$true
    if($json.response-is[string]){$result.Text=[string]$json.response;$result.ResponseMeaningful=$result.Text.Trim().Length-ge 20}
    if(-not$result.SuccessIsTrue){$result.Diagnostic='success_must_be_boolean_true'}elseif(-not$result.ResponseMeaningful){$result.Diagnostic='response_empty_or_not_significant'}else{$result.Diagnostic='structure_valid_manual_tool_review_pending'}
    return [pscustomobject]$result
}

function Save-SafeReport {
    param($Value)
    if(-not(Test-Path $ReportDirectory)){New-Item -ItemType Directory -Path $ReportDirectory -Force|Out-Null}
    $path=Join-Path $ReportDirectory ($Scenario+'-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'.json')
    [IO.File]::WriteAllText($path,($Value|ConvertTo-Json -Depth 6),$utf8NoBom);return $path
}

$report=[ordered]@{
    caseId=$Scenario;expectedTool=$selected.expectedTool;transport=$Transport;automaticStatus='SKIP';authHttpStatus=$null;webhookHttpStatus=$null
    jsonValid=$false;successIsTrue=$false;responseMeaningful=$false;conversationIdValid=($conversationId-cmatch'^[A-Za-z0-9_-]{8,64}$')
    academicEvaluation='PENDING';toolExecutionEvidence='PENDING';timeoutConfiguredMs=$timeoutMs;authDurationMs=$null;webhookDurationMs=$null;totalDurationMs=$null
    failureStage=$null;failureCategory=$null;transportStatus=$null;diagnostic='not_started';timestampUtc=[DateTime]::UtcNow.ToString('o')
}
$exitCode=0;$token=$null;$responseText=$null;$publicKey=$null;$currentStage='initialization';$totalClock=[Diagnostics.Stopwatch]::StartNew()
try{
    if($Transport-eq'Simulation'){
        $currentStage=if($SimulationScenario-eq'TransportTimeout'){'webhook_transport'}elseif($SimulationScenario-eq'ProcessingError'){'webhook_response_processing'}else{'simulation'}
        $exchange=Get-SimulatedExchange;$report.authHttpStatus=$exchange.AuthStatus;$token=$exchange.Token
        if($exchange.AuthStatus-ne 200-or[string]::IsNullOrWhiteSpace($token)){$report.automaticStatus='FAIL';$report.diagnostic='auth_rejected_or_missing_token';$exitCode=1}else{
            $report.webhookHttpStatus=$exchange.WebhookStatus;$validation=Test-ResponseContract $exchange.WebhookStatus $exchange.WebhookBody
            $report.jsonValid=$validation.JsonValid;$report.successIsTrue=$validation.SuccessIsTrue;$report.responseMeaningful=$validation.ResponseMeaningful;$report.diagnostic=$validation.Diagnostic;$responseText=$validation.Text
            if($validation.JsonValid-and$validation.SuccessIsTrue-and$validation.ResponseMeaningful){$report.automaticStatus='PASS'}else{$report.automaticStatus='FAIL';$exitCode=1}
        }
    }elseif(-not$AllowNetwork){$report.diagnostic='network_not_authorized'}else{
        $currentStage='credential_input';$email=Read-Host 'Correo de la cuenta estudiantil de pruebas';$passwordSecure=Read-Host 'Contrasena de la cuenta de pruebas' -AsSecureString;$keySecure=Read-Host 'Clave publica publishable de Supabase' -AsSecureString
        $password=ConvertFrom-PrivateSecureString $passwordSecure;$publicKey=ConvertFrom-PrivateSecureString $keySecure
        $currentStage='supabase_auth_transport';$clock=[Diagnostics.Stopwatch]::StartNew();try{$auth=Invoke-JsonRequest ($supabaseUrl+'/auth/v1/token?grant_type=password') @{email=$email;password=$password} @{apikey=$publicKey}}finally{$clock.Stop();$report.authDurationMs=[int64]$clock.ElapsedMilliseconds}
        $report.authHttpStatus=$auth.StatusCode;if($auth.StatusCode-ne 200){throw'auth_rejected'}
        $currentStage='supabase_auth_response_processing';try{$authJson=$auth.Body|ConvertFrom-Json}catch{$authJson=$null};if($null-eq$authJson-or[string]::IsNullOrWhiteSpace($authJson.access_token)){throw'auth_response_missing_access_token'}
        $token=[string]$authJson.access_token;$auth=$null;$authJson=$null;$password=$null;[GC]::Collect()
        $currentStage='workflow_confirmation';$confirm=Read-Host 'Active Execute workflow en n8n. Escriba EJECUTAR cuando webhook-test este escuchando'
        if($confirm-ne'EJECUTAR'){$report.diagnostic='workflow_activation_not_confirmed'}else{
            $currentStage='webhook_transport';$clock=[Diagnostics.Stopwatch]::StartNew();try{$response=Invoke-JsonRequest $webhookUrl @{message=$selected.message;conversationId=$conversationId} @{Authorization=('Bearer '+$token)}}finally{$clock.Stop();$report.webhookDurationMs=[int64]$clock.ElapsedMilliseconds}
            $report.webhookHttpStatus=$response.StatusCode;$currentStage='webhook_response_processing';$validation=Test-ResponseContract $response.StatusCode $response.Body
            $report.jsonValid=$validation.JsonValid;$report.successIsTrue=$validation.SuccessIsTrue;$report.responseMeaningful=$validation.ResponseMeaningful;$report.diagnostic=$validation.Diagnostic;$responseText=$validation.Text
            if($validation.JsonValid-and$validation.SuccessIsTrue-and$validation.ResponseMeaningful){$report.automaticStatus='PASS'}else{$report.automaticStatus='FAIL';$exitCode=1}
        }
    }
}catch{
    $report.automaticStatus='FAIL';$report.failureStage=$currentStage;$caught=$_.Exception
    if($caught.Message-in@('auth_rejected','auth_response_missing_access_token')){$report.failureCategory='authentication_error';$report.diagnostic=$caught.Message}
    elseif($caught-is[Net.WebException]){$report.transportStatus=[string]$caught.Status;$report.failureCategory=if($caught.Status-eq[Net.WebExceptionStatus]::Timeout){'transport_timeout'}else{'transport_web_exception'};$report.diagnostic=$report.failureCategory}
    elseif($caught-is[IO.IOException]){$report.failureCategory='transport_io_error';$report.diagnostic='transport_io_error'}else{$report.failureCategory='processing_exception';$report.diagnostic='processing_exception'};$exitCode=1
}finally{$token=$null;$publicKey=$null;$password=$null;$passwordSecure=$null;$keySecure=$null;$email=$null;[GC]::Collect()}
$totalClock.Stop();$report.totalDurationMs=[int64]$totalClock.ElapsedMilliseconds
$path = Save-SafeReport ([pscustomobject]$report)
Write-Host ("AUTOMATIC {0}: {1} - {2}" -f $report.automaticStatus, $Scenario, $report.diagnostic)
Write-Host ("ACADEMIC PENDING: revise manualmente la respuesta de {0}." -f $Scenario)
Write-Host ("TOOL EVIDENCE PENDING: confirme visualmente en n8n el uso de {0}." -f $selected.expectedTool)
if ($null -ne $responseText) {
    Write-Host "`n--- response (no se guarda en el reporte) ---"
    Write-Host $responseText
    Write-Host '--- fin de response ---'
}
Write-Host ('Reporte seguro: ' + $path)
$responseText = $null
exit $exitCode
