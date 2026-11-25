[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('T10-A','T10-B','T10-C','T10-D','T10-E')]
    [string]$Scenario,
    [ValidateSet('Real','Simulation')]
    [string]$Transport = 'Real',
    [ValidateSet('Expected','HttpError','InvalidJson','MissingMemory','LeakedMemory','WrongError','MissingError','MissingSecondAccount')]
    [string]$SimulationScenario = 'Expected',
    [switch]$AllowNetwork,
    [string]$ReportDirectory = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$supabaseUrl = 'https://icsekpkuheckfkgkqosg.supabase.co'
$webhookUrl = 'https://sofinebula.app.n8n.cloud/webhook-test/nebula-v2/chat'
$marker = 'ORBITA-AZUL-731'
$conversationOne = 'T10_' + [Guid]::NewGuid().ToString('N').Substring(0, 20)
$conversationTwo = 'T10_' + [Guid]::NewGuid().ToString('N').Substring(0, 20)
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
    $request.Method = 'POST'; $request.ContentType = 'application/json; charset=utf-8'; $request.Accept = 'application/json'; $request.Timeout = 60000
    foreach ($name in $Headers.Keys) { $request.Headers[$name] = $Headers[$name] }
    $bytes = $utf8NoBom.GetBytes(($Body | ConvertTo-Json -Compress -Depth 10)); $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream(); try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    try { $response = [Net.HttpWebResponse]$request.GetResponse() }
    catch [Net.WebException] { if ($null -eq $_.Exception.Response) { throw }; $response = [Net.HttpWebResponse]$_.Exception.Response }
    try {
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $text }
    } finally { $response.Dispose() }
}

function Read-TestLogin {
    param([string]$Label, [string]$PublicKey)
    $email = Read-Host ("Correo de " + $Label)
    $secure = Read-Host ("Contrasena de " + $Label) -AsSecureString
    $plain = ConvertFrom-PrivateSecureString $secure
    try {
        $response = Invoke-JsonRequest ($supabaseUrl + '/auth/v1/token?grant_type=password') @{ email = $email; password = $plain } @{ apikey = $PublicKey }
        if ($response.StatusCode -ne 200) { return [pscustomobject]@{ Status = $response.StatusCode; Token = $null } }
        try { $json = $response.Body | ConvertFrom-Json } catch { $json = $null }
        return [pscustomobject]@{ Status = $response.StatusCode; Token = if ($null -ne $json) { [string]$json.access_token } else { $null } }
    } finally { $email = $null; $plain = $null; $secure = $null; $response = $null; $json = $null; [GC]::Collect() }
}

function Confirm-Webhook {
    param([int]$Number)
    $answer = Read-Host ("Active Execute workflow para la solicitud $Number y escriba EJECUTAR")
    return $answer -eq 'EJECUTAR'
}

function Test-AgentEnvelope {
    param($Response)
    if ($Response.StatusCode -ne 200) { return [pscustomobject]@{ Valid = $false; Text = $null; Diagnostic = 'unexpected_http_status' } }
    try { $json = $Response.Body | ConvertFrom-Json } catch { return [pscustomobject]@{ Valid = $false; Text = $null; Diagnostic = 'invalid_json' } }
    $valid = ($json.success -is [bool]) -and $json.success -eq $true -and $json.project -ceq 'Nebula 2.0' -and ($json.response -is [string]) -and $json.response.Trim().Length -ge 1
    return [pscustomobject]@{ Valid = $valid; Text = if ($json.response -is [string]) { [string]$json.response } else { $null }; Diagnostic = if ($valid) { 'valid_agent_envelope' } else { 'invalid_agent_envelope' } }
}

function Get-ErrorEnvelopeDiagnostic {
    param($Response, [int]$ExpectedStatus, [string]$ExpectedError, [int]$RequestNumber)
    $result = [ordered]@{
        scenarioName = $Scenario
        requestNumber = $RequestNumber
        expectedHttpStatus = $ExpectedStatus
        observedHttpStatus = [int]$Response.StatusCode
        jsonValid = $false
        errorFieldExists = $false
        errorValueMatches = $false
        diagnosticCode = 'not_evaluated'
    }
    try {
        $json = $Response.Body | ConvertFrom-Json
        $result.jsonValid = $true
        $errorProperty = $json.PSObject.Properties['error']
        if ($null -ne $errorProperty) {
            $result.errorFieldExists = $true
            $result.errorValueMatches = $errorProperty.Value -is [string] -and $errorProperty.Value -ceq $ExpectedError
        }
    } catch {
        $json = $null
    }
    if ($result.observedHttpStatus -ne $ExpectedStatus) { $result.diagnosticCode = 'http_status_mismatch' }
    elseif (-not $result.jsonValid) { $result.diagnosticCode = 'invalid_json' }
    elseif (-not $result.errorFieldExists) { $result.diagnosticCode = 'missing_error_field' }
    elseif (-not $result.errorValueMatches) { $result.diagnosticCode = 'error_value_mismatch' }
    else { $result.diagnosticCode = 'contract_match' }
    return [pscustomobject]$result
}

function Invoke-ConfirmedWebhook {
    param([int]$Number, $Body, [string]$Token, [switch]$NoAuthorization)
    if (-not (Confirm-Webhook $Number)) { return $null }
    $headers = @{}
    if (-not $NoAuthorization) { $headers.Authorization = 'Bearer ' + $Token }
    return Invoke-JsonRequest $webhookUrl $Body $headers
}

function Get-Simulation {
    $agentOk = { param($text) [pscustomobject]@{ StatusCode = 200; Body = ([ordered]@{ success = $true; project = 'Nebula 2.0'; response = $text } | ConvertTo-Json -Compress) } }
    if ($SimulationScenario -eq 'HttpError') { return @([pscustomobject]@{ StatusCode = 500; Body = '{}' }, [pscustomobject]@{ StatusCode = 500; Body = '{}' }) }
    if ($SimulationScenario -eq 'InvalidJson') {
        $invalidJsonStatus = if ($Scenario -eq 'T10-D') { 401 } elseif ($Scenario -eq 'T10-E') { 400 } else { 200 }
        return @([pscustomobject]@{ StatusCode = $invalidJsonStatus; Body = '{not-json' }, [pscustomobject]@{ StatusCode = $invalidJsonStatus; Body = '{not-json' })
    }
    if ($Scenario -in 'T10-D','T10-E') {
        $error = if ($SimulationScenario -eq 'WrongError') { 'unexpected' } elseif ($Scenario -eq 'T10-D') { 'unauthorized' } else { 'invalid_conversation_id' }
        $status = if ($Scenario -eq 'T10-D') { 401 } else { 400 }
        $body = if ($SimulationScenario -eq 'MissingError') { '{"message":"rejected"}' } else { '{"error":"' + $error + '"}' }
        return @(
            [pscustomobject]@{ StatusCode = $status; Body = $body },
            [pscustomobject]@{ StatusCode = $status; Body = $body }
        )
    }
    $secondText = if ($Scenario -eq 'T10-A') { "Recuerdo la preferencia $marker." } else { 'No tengo una preferencia registrada en esta conversacion.' }
    if ($SimulationScenario -eq 'MissingMemory') { $secondText = 'No recuerdo ninguna preferencia.' }
    if ($SimulationScenario -eq 'LeakedMemory') { $secondText = "La preferencia es $marker." }
    return @((& $agentOk 'Preferencia recibida.'), (& $agentOk $secondText))
}

function Save-Report {
    param($Value)
    if (-not (Test-Path $ReportDirectory)) { New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null }
    $path = Join-Path $ReportDirectory ("$Scenario-" + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '.json')
    [IO.File]::WriteAllText($path, ($Value | ConvertTo-Json -Depth 8), $utf8NoBom); return $path
}

$report = [ordered]@{
    caseId = $Scenario; transport = $Transport; automaticStatus = 'SKIP'; requestsExpected = 2; requestsCompleted = 0
    transportValidation = 'NOT_RUN'; memorySignal = 'NOT_RUN'; manualEvaluation = 'PENDING'; postgresStorageVerification = 'PENDING'
    requestDiagnostics = @(); diagnostic = 'not_started'; timestampUtc = [DateTime]::UtcNow.ToString('o')
}
$exitCode = 0; $tokenOne = $null; $tokenTwo = $null; $publicKey = $null
try {
    if ($Transport -eq 'Simulation') {
        if ($Scenario -eq 'T10-C' -and $SimulationScenario -eq 'MissingSecondAccount') {
            $report.diagnostic = 'second_test_account_unavailable'
        } else {
            $responses = @(Get-Simulation)
            if ($responses.Count -lt 2) { $report.automaticStatus = 'FAIL'; $report.transportValidation = 'FAIL'; $report.diagnostic = 'incomplete_simulated_exchange'; $exitCode = 1 }
            elseif ($Scenario -in 'T10-D','T10-E') {
                $expectedStatus = if ($Scenario -eq 'T10-D') { 401 } else { 400 }; $expectedError = if ($Scenario -eq 'T10-D') { 'unauthorized' } else { 'invalid_conversation_id' }
                $diagnosticOne = Get-ErrorEnvelopeDiagnostic $responses[0] $expectedStatus $expectedError 1
                $diagnosticTwo = Get-ErrorEnvelopeDiagnostic $responses[1] $expectedStatus $expectedError 2
                $report.requestDiagnostics = @($diagnosticOne, $diagnosticTwo)
                $okOne = $diagnosticOne.diagnosticCode -eq 'contract_match'
                $okTwo = $diagnosticTwo.diagnosticCode -eq 'contract_match'
                $ok = $okOne -and $okTwo
                $report.requestsCompleted = 2; $report.transportValidation = if ($ok) { 'PASS' } else { 'FAIL' }; $report.memorySignal = 'REQUEST_REJECTED_BEFORE_MEMORY_EXPECTED'
                $report.automaticStatus = if ($ok) { 'PASS' } else { 'FAIL' }; $report.diagnostic = if ($ok) { 'rejection_contract_valid_storage_check_pending' } else { 'wrong_rejection_contract' }; if (-not $ok) { $exitCode = 1 }
            } else {
                $one = Test-AgentEnvelope $responses[0]; $two = Test-AgentEnvelope $responses[1]
                $report.requestsCompleted = 2; $report.transportValidation = if ($one.Valid -and $two.Valid) { 'PASS' } else { 'FAIL' }
                $hasMarker = $two.Text -like ('*' + $marker + '*')
                $memoryOk = if ($Scenario -eq 'T10-A') { $hasMarker } else { -not $hasMarker }
                $report.memorySignal = if ($memoryOk) { 'PASS' } else { 'FAIL' }
                $ok = $one.Valid -and $two.Valid -and $memoryOk; $report.automaticStatus = if ($ok) { 'PASS' } else { 'FAIL' }
                $report.diagnostic = if ($ok) { 'automatic_signal_valid_manual_and_storage_checks_pending' } else { 'memory_or_transport_signal_failed' }; if (-not $ok) { $exitCode = 1 }
            }
        }
    } elseif (-not $AllowNetwork) { $report.diagnostic = 'network_not_authorized' }
    else {
        if ($Scenario -eq 'T10-C') {
            $available = Read-Host 'Escriba DISPONIBLE si cuenta con una segunda cuenta estudiantil de pruebas'
            if ($available -ne 'DISPONIBLE') { $report.diagnostic = 'second_test_account_unavailable' }
        }
        if ($report.diagnostic -ne 'second_test_account_unavailable') {
            if ($Scenario -notin 'T10-D') {
                $keySecure = Read-Host 'Clave publica publishable de Supabase' -AsSecureString; $publicKey = ConvertFrom-PrivateSecureString $keySecure
                $loginOne = Read-TestLogin 'la cuenta estudiantil de pruebas' $publicKey; $tokenOne = $loginOne.Token
                if ($loginOne.Status -ne 200 -or [string]::IsNullOrWhiteSpace($tokenOne)) { throw 'auth_failed' }
                if ($Scenario -eq 'T10-C') { $loginTwo = Read-TestLogin 'la segunda cuenta estudiantil de pruebas' $publicKey; $tokenTwo = $loginTwo.Token; if ($loginTwo.Status -ne 200 -or [string]::IsNullOrWhiteSpace($tokenTwo)) { throw 'second_auth_failed' } }
            }
            if ($Scenario -eq 'T10-A') {
                $r1 = Invoke-ConfirmedWebhook 1 @{ message = "Mi preferencia sintetica es $marker. Recuerdala."; conversationId = $conversationOne } $tokenOne
                $r2 = if ($null -ne $r1) { Invoke-ConfirmedWebhook 2 @{ message = 'Cual es la preferencia sintetica que te comunique?'; conversationId = $conversationOne } $tokenOne } else { $null }
            } elseif ($Scenario -eq 'T10-B') {
                $r1 = Invoke-ConfirmedWebhook 1 @{ message = "Mi preferencia sintetica es $marker. Recuerdala."; conversationId = $conversationOne } $tokenOne
                $r2 = if ($null -ne $r1) { Invoke-ConfirmedWebhook 2 @{ message = 'Tengo alguna preferencia sintetica registrada?'; conversationId = $conversationTwo } $tokenOne } else { $null }
            } elseif ($Scenario -eq 'T10-C') {
                $r1 = Invoke-ConfirmedWebhook 1 @{ message = "Mi preferencia sintetica es $marker. Recuerdala."; conversationId = $conversationOne } $tokenOne
                $r2 = if ($null -ne $r1) { Invoke-ConfirmedWebhook 2 @{ message = 'Tengo alguna preferencia sintetica registrada?'; conversationId = $conversationOne } $tokenTwo } else { $null }
            } elseif ($Scenario -eq 'T10-D') {
                $r1 = Invoke-ConfirmedWebhook 1 @{ message = 'Mensaje de rechazo sin autenticacion'; conversationId = $conversationOne } '' -NoAuthorization
                $r2 = if ($null -ne $r1) { Invoke-ConfirmedWebhook 2 @{ message = 'Mensaje de rechazo con token invalido'; conversationId = $conversationOne } 'token_ficticio_no_valido_12345' } else { $null }
            } else {
                $r1 = Invoke-ConfirmedWebhook 1 @{ message = 'Mensaje sin identificador de conversacion' } $tokenOne
                $r2 = if ($null -ne $r1) { Invoke-ConfirmedWebhook 2 @{ message = 'Mensaje con identificador invalido'; conversationId = 'bad' } $tokenOne } else { $null }
            }
            if ($null -eq $r1 -or $null -eq $r2) { $report.diagnostic = 'workflow_activation_not_confirmed' }
            elseif ($Scenario -in 'T10-D','T10-E') {
                $expectedStatus = if ($Scenario -eq 'T10-D') { 401 } else { 400 }; $expectedError = if ($Scenario -eq 'T10-D') { 'unauthorized' } else { 'invalid_conversation_id' }
                $diagnosticOne = Get-ErrorEnvelopeDiagnostic $r1 $expectedStatus $expectedError 1
                $diagnosticTwo = Get-ErrorEnvelopeDiagnostic $r2 $expectedStatus $expectedError 2
                $report.requestDiagnostics = @($diagnosticOne, $diagnosticTwo)
                $okOne = $diagnosticOne.diagnosticCode -eq 'contract_match'
                $okTwo = $diagnosticTwo.diagnosticCode -eq 'contract_match'
                $ok = $okOne -and $okTwo
                $report.requestsCompleted = 2; $report.transportValidation = if ($ok) { 'PASS' } else { 'FAIL' }; $report.memorySignal = 'REQUEST_REJECTED_BEFORE_MEMORY_EXPECTED'; $report.automaticStatus = if ($ok) { 'PASS' } else { 'FAIL' }; $report.diagnostic = if ($ok) { 'rejection_contract_valid_storage_check_pending' } else { 'wrong_rejection_contract' }; if (-not $ok) { $exitCode = 1 }
            } else {
                $one = Test-AgentEnvelope $r1; $two = Test-AgentEnvelope $r2; $hasMarker = $two.Text -like ('*' + $marker + '*'); $memoryOk = if ($Scenario -eq 'T10-A') { $hasMarker } else { -not $hasMarker }; $ok = $one.Valid -and $two.Valid -and $memoryOk
                $report.requestsCompleted = 2; $report.transportValidation = if ($one.Valid -and $two.Valid) { 'PASS' } else { 'FAIL' }; $report.memorySignal = if ($memoryOk) { 'PASS' } else { 'FAIL' }; $report.automaticStatus = if ($ok) { 'PASS' } else { 'FAIL' }; $report.diagnostic = if ($ok) { 'automatic_signal_valid_manual_and_storage_checks_pending' } else { 'memory_or_transport_signal_failed' }; if (-not $ok) { $exitCode = 1 }
            }
        }
    }
} catch { $report.automaticStatus = 'FAIL'; $report.transportValidation = 'FAIL'; $report.diagnostic = if ($_.Exception.Message -in 'auth_failed','second_auth_failed') { $_.Exception.Message } else { 'safe_transport_or_processing_error' }; $exitCode = 1 }
finally { $tokenOne = $null; $tokenTwo = $null; $publicKey = $null; $keySecure = $null; $loginOne = $null; $loginTwo = $null; $r1 = $null; $r2 = $null; [GC]::Collect() }

$path = Save-Report ([pscustomobject]$report)
Write-Host ("AUTOMATIC {0}: {1} - {2}" -f $report.automaticStatus, $Scenario, $report.diagnostic)
foreach ($item in $report.requestDiagnostics) {
    Write-Host ("REQUEST {0}: expected HTTP {1}, observed HTTP {2}, jsonValid={3}, errorFieldExists={4}, errorValueMatches={5}, diagnostic={6}" -f `
        $item.requestNumber, $item.expectedHttpStatus, $item.observedHttpStatus, $item.jsonValid, $item.errorFieldExists, $item.errorValueMatches, $item.diagnosticCode)
}
Write-Host 'MANUAL PENDING: revise las respuestas y confirme el aislamiento esperado.'
Write-Host 'POSTGRES PENDING: verifique almacenamiento/no escritura por un canal administrativo autorizado.'
Write-Host ('Reporte seguro: ' + $path)
exit $exitCode
