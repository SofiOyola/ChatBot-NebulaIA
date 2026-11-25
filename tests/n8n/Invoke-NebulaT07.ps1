[CmdletBinding()]
param(
    [ValidateSet('Real', 'Simulation')]
    [string]$Transport = 'Real',

    [ValidateSet('Success', 'AuthRejected', 'WebhookRejected', 'InvalidJson')]
    [string]$SimulationScenario = 'Success',

    [switch]$AllowNetwork,
    [string]$ReportDirectory = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$supabaseUrl = 'https://icsekpkuheckfkgkqosg.supabase.co'
$webhookUrl = 'https://sofinebula.app.n8n.cloud/webhook-test/nebula-v2/chat'
$conversationId = 'T07_' + [Guid]::NewGuid().ToString('N').Substring(0, 20)
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
    switch ($Scenario) {
        'AuthRejected' { return [pscustomobject]@{ AuthStatus = 400; Token = $null; WebhookStatus = $null; WebhookBody = $null } }
        'WebhookRejected' { return [pscustomobject]@{ AuthStatus = 200; Token = 'memory-only-fixture'; WebhookStatus = 401; WebhookBody = '{"error":"unauthorized"}' } }
        'InvalidJson' { return [pscustomobject]@{ AuthStatus = 200; Token = 'memory-only-fixture'; WebhookStatus = 200; WebhookBody = 'not-json' } }
        default { return [pscustomobject]@{ AuthStatus = 200; Token = 'memory-only-fixture'; WebhookStatus = 200; WebhookBody = '{"status":"provisional"}' } }
    }
}

function Save-SafeReport {
    param($Report)
    if (-not (Test-Path -LiteralPath $ReportDirectory)) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    }
    $path = Join-Path $ReportDirectory ('T07-{0}.json' -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
    $json = $Report | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($path, $json, $utf8NoBom)
    return $path
}

$report = [ordered]@{
    caseId = 'T07'
    purpose = 'acceso provisional con Supabase Auth; no valida el chatbot completo'
    transport = $Transport
    status = 'SKIP'
    authHttpStatus = $null
    webhookHttpStatus = $null
    jsonValid = $false
    conversationIdValid = ($conversationId -cmatch '^[A-Za-z0-9_-]{8,64}$')
    diagnostic = 'not_started'
    timestampUtc = [DateTime]::UtcNow.ToString('o')
}
$exitCode = 0
$accessToken = $null
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
            $report.webhookHttpStatus = $exchange.WebhookStatus
            try { $null = $exchange.WebhookBody | ConvertFrom-Json; $report.jsonValid = $true }
            catch { $report.jsonValid = $false }
            if ($exchange.WebhookStatus -eq 200 -and $report.jsonValid) {
                $report.status = 'PASS'; $report.diagnostic = 'provisional_access_confirmed'
            }
            else {
                $report.status = 'FAIL'
                $report.diagnostic = if ($exchange.WebhookStatus -ne 200) { 'unexpected_webhook_status' } else { 'invalid_webhook_json' }
                $exitCode = 1
            }
        }
    }
    elseif (-not $AllowNetwork) {
        $report.diagnostic = 'network_not_authorized'
    }
    else {
        Write-Host 'Las entradas privadas no se guardaran en reportes ni se mostraran en pantalla.'
        $email = Read-Host 'Correo de la cuenta estudiantil de pruebas'
        $passwordSecure = Read-Host 'Contrasena de la cuenta de pruebas' -AsSecureString
        $publicKeySecure = Read-Host 'Clave publica publishable o anon de Supabase' -AsSecureString
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
            try { $authJson = $authResponse.Body | ConvertFrom-Json }
            catch { $authJson = $null }
            if ($null -eq $authJson -or [string]::IsNullOrWhiteSpace($authJson.access_token)) {
                $report.status = 'FAIL'; $report.diagnostic = 'auth_response_missing_access_token'; $exitCode = 1
            }
            else {
                $accessToken = [string]$authJson.access_token
                $authJson = $null
                $authResponse = $null
                $passwordPlain = $null
                [GC]::Collect()

                $confirmation = Read-Host 'Active Execute workflow en n8n. Escriba EJECUTAR cuando webhook-test este escuchando'
                if ($confirmation -ne 'EJECUTAR') {
                    $report.status = 'SKIP'; $report.diagnostic = 'workflow_activation_not_confirmed'
                }
                else {
                    $webhookResponse = Invoke-JsonRequest `
                        -Url $webhookUrl `
                        -Body @{ message = 'Hola Nebula'; conversationId = $conversationId } `
                        -Headers @{ Authorization = ('Bearer ' + $accessToken) }
                    $report.webhookHttpStatus = $webhookResponse.StatusCode
                    try { $null = $webhookResponse.Body | ConvertFrom-Json; $report.jsonValid = $true }
                    catch { $report.jsonValid = $false }
                    if ($webhookResponse.StatusCode -eq 200 -and $report.jsonValid) {
                        $report.status = 'PASS'; $report.diagnostic = 'provisional_access_confirmed'
                    }
                    else {
                        $report.status = 'FAIL'
                        $report.diagnostic = if ($webhookResponse.StatusCode -ne 200) { 'unexpected_webhook_status' } else { 'invalid_webhook_json' }
                        $exitCode = 1
                    }
                }
            }
        }
    }
}
catch {
    $report.status = 'FAIL'
    $report.diagnostic = if ($_.Exception.Message -in 'missing_email','missing_private_input') { $_.Exception.Message } else { 'safe_transport_or_processing_error' }
    $exitCode = 1
}
finally {
    $accessToken = $null
    $passwordPlain = $null
    $publicKeyPlain = $null
    $passwordSecure = $null
    $publicKeySecure = $null
    $email = $null
    [GC]::Collect()
}

$reportPath = Save-SafeReport ([pscustomobject]$report)
Write-Host ("{0}: T07 - {1}" -f $report.status, $report.diagnostic)
Write-Host 'El resultado solo evalua acceso autenticado provisional, no el chatbot completo.'
Write-Host ('Reporte seguro: ' + $reportPath)
exit $exitCode
