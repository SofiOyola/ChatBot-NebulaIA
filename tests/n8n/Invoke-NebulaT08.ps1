[CmdletBinding()]
param(
    [ValidateSet('Real', 'Simulation')]
    [string]$Transport = 'Real',

    [ValidateSet('ExpectedUnauthorized', 'AuthRejected', 'WrongStatus', 'WrongJson', 'MalformedToken')]
    [string]$SimulationScenario = 'ExpectedUnauthorized',

    [switch]$AllowNetwork,
    [string]$ReportDirectory = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$supabaseUrl = 'https://icsekpkuheckfkgkqosg.supabase.co'
$webhookUrl = 'https://sofinebula.app.n8n.cloud/webhook-test/nebula-v2/chat'
. (Join-Path $PSScriptRoot 'JwtTestHelpers.ps1')
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $ReportDirectory = Join-Path $PSScriptRoot 'reports'
}

function ConvertFrom-PrivateSecureString {
    param([Parameter(Mandatory = $true)][Security.SecureString]$Value)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Invoke-JsonRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)]$Body,
        [Parameter(Mandatory = $true)][hashtable]$Headers
    )
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.Method = 'POST'
    $request.ContentType = 'application/json; charset=utf-8'
    $request.Accept = 'application/json'
    $request.Timeout = 30000
    foreach ($name in $Headers.Keys) { $request.Headers[$name] = $Headers[$name] }
    $bytes = $utf8NoBom.GetBytes(($Body | ConvertTo-Json -Compress -Depth 10))
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream()
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    try { $response = [Net.HttpWebResponse]$request.GetResponse() }
    catch [Net.WebException] {
        if ($null -eq $_.Exception.Response) { throw }
        $response = [Net.HttpWebResponse]$_.Exception.Response
    }
    try {
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $responseBody = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $responseBody }
    }
    finally { $response.Dispose() }
}

function Get-SimulatedExchange {
    param([string]$Scenario)
    $validFixture = 'fixtureHeader.fixturePayload.fixtureSignature'
    switch ($Scenario) {
        'AuthRejected' { return [pscustomobject]@{ AuthStatus = 400; Token = $null; WebhookStatus = $null; WebhookBody = $null } }
        'WrongStatus' { return [pscustomobject]@{ AuthStatus = 200; Token = $validFixture; WebhookStatus = 200; WebhookBody = '{"error":"unauthorized"}' } }
        'WrongJson' { return [pscustomobject]@{ AuthStatus = 200; Token = $validFixture; WebhookStatus = 401; WebhookBody = '{"error":"different_error"}' } }
        'MalformedToken' { return [pscustomobject]@{ AuthStatus = 200; Token = 'not-a-jwt'; WebhookStatus = $null; WebhookBody = $null } }
        default { return [pscustomobject]@{ AuthStatus = 200; Token = $validFixture; WebhookStatus = 401; WebhookBody = '{"error":"unauthorized"}' } }
    }
}

function Save-SafeReport {
    param($Report)
    if (-not (Test-Path -LiteralPath $ReportDirectory)) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    }
    $path = Join-Path $ReportDirectory ('T08-{0}.json' -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
    [IO.File]::WriteAllText($path, ($Report | ConvertTo-Json -Depth 6), $utf8NoBom)
    return $path
}

function Test-UnauthorizedResponse {
    param([int]$StatusCode, [string]$Body)
    $outcome = [ordered]@{ JsonValid = $false; ErrorIsUnauthorized = $false; Diagnostic = 'not_checked' }
    try { $json = $Body | ConvertFrom-Json; $outcome.JsonValid = $true }
    catch { $outcome.Diagnostic = 'invalid_webhook_json'; return [pscustomobject]$outcome }
    if ($json.error -eq 'unauthorized') { $outcome.ErrorIsUnauthorized = $true }
    if ($StatusCode -ne 401) { $outcome.Diagnostic = 'unexpected_webhook_status' }
    elseif (-not $outcome.ErrorIsUnauthorized) { $outcome.Diagnostic = 'unexpected_webhook_error' }
    else { $outcome.Diagnostic = 'automated_rejection_confirmed_manual_route_evidence_pending' }
    return [pscustomobject]$outcome
}

$report = [ordered]@{
    caseId = 'T08'
    purpose = 'rechazo de JWT con firma alterada'
    transport = $Transport
    status = 'SKIP'
    authHttpStatus = $null
    webhookHttpStatus = $null
    jsonValid = $false
    errorIsUnauthorized = $false
    signatureMutationVerified = $false
    manualEvidence = 'PENDING: HTTP 401 y error unauthorized no demuestran por si solos que Supabase valido el JWT; revisar el recorrido de la ejecucion n8n sin registrar credenciales ni headers.'
    diagnostic = 'not_started'
    timestampUtc = [DateTime]::UtcNow.ToString('o')
}
$exitCode = 0
$accessToken = $null
$invalidToken = $null
$passwordPlain = $null
$publicKeyPlain = $null

try {
    if ($Transport -eq 'Simulation') {
        $exchange = Get-SimulatedExchange $SimulationScenario
        $report.authHttpStatus = $exchange.AuthStatus
        $accessToken = $exchange.Token
        if ($exchange.AuthStatus -ne 200 -or [string]::IsNullOrWhiteSpace($accessToken)) {
            $report.status = 'FAIL'; $report.diagnostic = 'auth_rejected_or_missing_token'; $exitCode = 1
        }
        else {
            $invalidToken = New-DeterministicallyInvalidJwt $accessToken
            $originalParts = $accessToken.Split('.')
            $invalidParts = $invalidToken.Split('.')
            $report.signatureMutationVerified = $originalParts[0] -ceq $invalidParts[0] -and
                                                $originalParts[1] -ceq $invalidParts[1] -and
                                                $originalParts[2] -cne $invalidParts[2]
            $report.webhookHttpStatus = $exchange.WebhookStatus
            $check = Test-UnauthorizedResponse $exchange.WebhookStatus $exchange.WebhookBody
            $report.jsonValid = $check.JsonValid
            $report.errorIsUnauthorized = $check.ErrorIsUnauthorized
            $report.diagnostic = $check.Diagnostic
            if ($report.signatureMutationVerified -and $exchange.WebhookStatus -eq 401 -and
                $check.JsonValid -and $check.ErrorIsUnauthorized) { $report.status = 'PASS' }
            else { $report.status = 'FAIL'; $exitCode = 1 }
        }
    }
    elseif (-not $AllowNetwork) {
        $report.diagnostic = 'network_not_authorized'
    }
    else {
        Write-Host 'Las entradas privadas y los tokens solo se conservaran en memoria.'
        $email = Read-Host 'Correo de la cuenta estudiantil de pruebas'
        $passwordSecure = Read-Host 'Contrasena de la cuenta de pruebas' -AsSecureString
        $publicKeySecure = Read-Host 'Clave publica publishable de Supabase' -AsSecureString
        if ([string]::IsNullOrWhiteSpace($email)) { throw 'missing_email' }
        $passwordPlain = ConvertFrom-PrivateSecureString $passwordSecure
        $publicKeyPlain = ConvertFrom-PrivateSecureString $publicKeySecure
        if ([string]::IsNullOrWhiteSpace($passwordPlain) -or [string]::IsNullOrWhiteSpace($publicKeyPlain)) {
            throw 'missing_private_input'
        }
        $authResponse = Invoke-JsonRequest `
            -Url ($supabaseUrl + '/auth/v1/token?grant_type=password') `
            -Body @{ email = $email; password = $passwordPlain } `
            -Headers @{ apikey = $publicKeyPlain }
        $report.authHttpStatus = $authResponse.StatusCode
        if ($authResponse.StatusCode -ne 200) {
            $report.status = 'FAIL'; $report.diagnostic = 'auth_rejected'; $exitCode = 1
        }
        else {
            try { $authJson = $authResponse.Body | ConvertFrom-Json } catch { $authJson = $null }
            if ($null -eq $authJson -or [string]::IsNullOrWhiteSpace($authJson.access_token)) {
                $report.status = 'FAIL'; $report.diagnostic = 'auth_response_missing_access_token'; $exitCode = 1
            }
            else {
                $accessToken = [string]$authJson.access_token
                $invalidToken = New-DeterministicallyInvalidJwt $accessToken
                $originalParts = $accessToken.Split('.')
                $invalidParts = $invalidToken.Split('.')
                $report.signatureMutationVerified = $originalParts[0] -ceq $invalidParts[0] -and
                                                    $originalParts[1] -ceq $invalidParts[1] -and
                                                    $originalParts[2] -cne $invalidParts[2]
                if (-not $report.signatureMutationVerified) { throw 'signature_mutation_invariant_failed' }
                $authJson = $null; $authResponse = $null; $passwordPlain = $null; [GC]::Collect()

                $confirmation = Read-Host 'Active Execute workflow en n8n. Escriba EJECUTAR cuando webhook-test este escuchando'
                if ($confirmation -ne 'EJECUTAR') {
                    $report.status = 'SKIP'; $report.diagnostic = 'workflow_activation_not_confirmed'
                }
                else {
                    $webhookResponse = Invoke-JsonRequest `
                        -Url $webhookUrl `
                        -Body @{ message = 'Hola Nebula' } `
                        -Headers @{ Authorization = ('Bearer ' + $invalidToken) }
                    $report.webhookHttpStatus = $webhookResponse.StatusCode
                    $check = Test-UnauthorizedResponse $webhookResponse.StatusCode $webhookResponse.Body
                    $report.jsonValid = $check.JsonValid
                    $report.errorIsUnauthorized = $check.ErrorIsUnauthorized
                    $report.diagnostic = $check.Diagnostic
                    if ($webhookResponse.StatusCode -eq 401 -and $check.JsonValid -and $check.ErrorIsUnauthorized) {
                        $report.status = 'PASS'
                    }
                    else { $report.status = 'FAIL'; $exitCode = 1 }
                }
            }
        }
    }
}
catch {
    $report.status = 'FAIL'
    $report.diagnostic = if ($_.Exception.Message -in 'missing_email','missing_private_input','access_token_is_not_a_three_segment_jwt','signature_mutation_invariant_failed') { $_.Exception.Message } else { 'safe_transport_or_processing_error' }
    $exitCode = 1
}
finally {
    $accessToken = $null; $invalidToken = $null; $passwordPlain = $null; $publicKeyPlain = $null
    $passwordSecure = $null; $publicKeySecure = $null; $email = $null
    $originalParts = $null; $invalidParts = $null; [GC]::Collect()
}

$reportPath = Save-SafeReport ([pscustomobject]$report)
Write-Host ("{0}: T08 - {1}" -f $report.status, $report.diagnostic)
Write-Host $report.manualEvidence
Write-Host ('Reporte seguro: ' + $reportPath)
exit $exitCode
