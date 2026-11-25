[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('T09-A', 'T09-B', 'T09-C')]
    [string]$Scenario,

    [ValidateSet('Real', 'Simulation')]
    [string]$Transport = 'Real',

    [ValidateSet('Valid', 'HttpError', 'InvalidJson', 'EmptyResponse', 'WrongProject', 'SuccessFalse', 'LiteralEscape', 'UnexpectedStructure', 'AuthRejected')]
    [string]$SimulationScenario = 'Valid',

    [switch]$AllowNetwork,
    [string]$ReportDirectory = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$supabaseUrl = 'https://icsekpkuheckfkgkqosg.supabase.co'
$webhookUrl = 'https://sofinebula.app.n8n.cloud/webhook-test/nebula-v2/chat'
$conversationId = 'T09_' + [Guid]::NewGuid().ToString('N').Substring(0, 20)
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $ReportDirectory = Join-Path $PSScriptRoot 'reports'
}

$scenarioPath = Join-Path $PSScriptRoot 't09-scenarios.json'
$scenarioDefinitions = [IO.File]::ReadAllText($scenarioPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$selected = $scenarioDefinitions.PSObject.Properties[$Scenario].Value

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
    param([string]$SimulationName)
    $validText = switch ($Scenario) {
        'T09-A' { 'Una clase es el molde y un objeto es una instancia concreta creada con ese molde. La evaluacion academica de esta explicacion sigue pendiente.' }
        'T09-B' { 'Una clave primaria identifica cada fila y una clave foranea relaciona una fila con otra tabla. La evaluacion academica sigue pendiente.' }
        default { 'Todavia no tengo acceso verificado a tu historial, creditos ni reglas curriculares, asi que no debo inventar esa informacion.' }
    }
    $payload = [ordered]@{ success = $true; project = 'Nebula 2.0'; response = $validText }
    switch ($SimulationName) {
        'AuthRejected' { return [pscustomobject]@{ AuthStatus = 400; Token = $null; WebhookStatus = $null; WebhookBody = $null } }
        'HttpError' { return [pscustomobject]@{ AuthStatus = 200; Token = 'memory-only-fixture'; WebhookStatus = 500; WebhookBody = ($payload | ConvertTo-Json -Compress) } }
        'InvalidJson' { return [pscustomobject]@{ AuthStatus = 200; Token = 'memory-only-fixture'; WebhookStatus = 200; WebhookBody = 'not-json' } }
        'EmptyResponse' { $payload.response = '   ' }
        'WrongProject' { $payload.project = 'Another project' }
        'SuccessFalse' { $payload.success = $false }
        'LiteralEscape' { $payload.response = 'Explicacion util con una secuencia literal\nque debe revisarse manualmente.' }
        'UnexpectedStructure' { $payload.response = @('texto dentro de una lista') }
    }
    return [pscustomobject]@{ AuthStatus = 200; Token = 'memory-only-fixture'; WebhookStatus = 200; WebhookBody = ($payload | ConvertTo-Json -Compress -Depth 5) }
}

function Test-AgentResponse {
    param([int]$StatusCode, [string]$Body)
    $errors = New-Object Collections.Generic.List[string]
    $warnings = New-Object Collections.Generic.List[string]
    $text = $null
    $jsonValid = $false
    if ($StatusCode -ne 200) { $errors.Add('unexpected_http_status') }
    try { $json = $Body | ConvertFrom-Json; $jsonValid = $true }
    catch { $errors.Add('invalid_json'); return [pscustomobject]@{ JsonValid = $false; Errors = @($errors); Warnings = @($warnings); Text = $null } }
    if (-not ($json.success -is [bool]) -or $json.success -ne $true) { $errors.Add('success_must_be_boolean_true') }
    if (-not ($json.project -is [string]) -or $json.project -cne 'Nebula 2.0') { $errors.Add('unexpected_project') }
    if (-not ($json.response -is [string])) { $errors.Add('response_must_be_text') }
    else {
        $text = [string]$json.response
        if ($text.Trim().Length -lt 20) { $errors.Add('response_empty_or_not_significant') }
        if ($text -match '\\[nrt"]') { $warnings.Add('literal_escape_sequence_detected') }
    }
    return [pscustomobject]@{ JsonValid = $jsonValid; Errors = @($errors); Warnings = @($warnings); Text = $text }
}

function Save-SafeReport {
    param($Report)
    if (-not (Test-Path -LiteralPath $ReportDirectory)) { New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null }
    $path = Join-Path $ReportDirectory ('{0}-{1}.json' -f $Scenario, [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
    [IO.File]::WriteAllText($path, ($Report | ConvertTo-Json -Depth 8), $utf8NoBom)
    return $path
}

$report = [ordered]@{
    caseId = $Scenario
    transport = $Transport
    automaticStatus = 'SKIP'
    authHttpStatus = $null
    webhookHttpStatus = $null
    jsonValid = $false
    structuralValidation = 'NOT_RUN'
    conversationIdValid = ($conversationId -cmatch '^[A-Za-z0-9_-]{8,64}$')
    formatWarnings = @()
    manualEvaluation = 'PENDING'
    manualCriteria = @($selected.manualCriteria)
    diagnostic = 'not_started'
    timestampUtc = [DateTime]::UtcNow.ToString('o')
}
$exitCode = 0
$accessToken = $null
$responseText = $null
$passwordPlain = $null
$publicKeyPlain = $null

try {
    if ($Transport -eq 'Simulation') {
        $exchange = Get-SimulatedExchange $SimulationScenario
        $report.authHttpStatus = $exchange.AuthStatus
        $accessToken = $exchange.Token
        if ($exchange.AuthStatus -ne 200 -or [string]::IsNullOrWhiteSpace($accessToken)) {
            $report.automaticStatus = 'FAIL'; $report.structuralValidation = 'FAIL'; $report.diagnostic = 'auth_rejected_or_missing_token'; $exitCode = 1
        }
        else {
            $report.webhookHttpStatus = $exchange.WebhookStatus
            $validation = Test-AgentResponse $exchange.WebhookStatus $exchange.WebhookBody
            $report.jsonValid = $validation.JsonValid
            $report.formatWarnings = @($validation.Warnings)
            $responseText = $validation.Text
            if ($validation.Errors.Count -eq 0) {
                $report.automaticStatus = 'PASS'; $report.structuralValidation = 'PASS'; $report.diagnostic = 'structure_valid_manual_academic_review_pending'
            }
            else {
                $report.automaticStatus = 'FAIL'; $report.structuralValidation = 'FAIL'; $report.diagnostic = $validation.Errors[0]; $exitCode = 1
            }
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
        if ([string]::IsNullOrWhiteSpace($passwordPlain) -or [string]::IsNullOrWhiteSpace($publicKeyPlain)) { throw 'missing_private_input' }
        $authResponse = Invoke-JsonRequest `
            -Url ($supabaseUrl + '/auth/v1/token?grant_type=password') `
            -Body @{ email = $email; password = $passwordPlain } `
            -Headers @{ apikey = $publicKeyPlain }
        $report.authHttpStatus = $authResponse.StatusCode
        if ($authResponse.StatusCode -ne 200) {
            $report.automaticStatus = 'FAIL'; $report.structuralValidation = 'FAIL'; $report.diagnostic = 'auth_rejected'; $exitCode = 1
        }
        else {
            try { $authJson = $authResponse.Body | ConvertFrom-Json } catch { $authJson = $null }
            if ($null -eq $authJson -or [string]::IsNullOrWhiteSpace($authJson.access_token)) {
                $report.automaticStatus = 'FAIL'; $report.structuralValidation = 'FAIL'; $report.diagnostic = 'auth_response_missing_access_token'; $exitCode = 1
            }
            else {
                $accessToken = [string]$authJson.access_token
                $authJson = $null; $authResponse = $null; $passwordPlain = $null; [GC]::Collect()
                $confirmation = Read-Host 'Active Execute workflow en n8n. Escriba EJECUTAR cuando webhook-test este escuchando'
                if ($confirmation -ne 'EJECUTAR') {
                    $report.diagnostic = 'workflow_activation_not_confirmed'
                }
                else {
                    $webhookResponse = Invoke-JsonRequest `
                        -Url $webhookUrl `
                        -Body @{ message = $selected.message; conversationId = $conversationId } `
                        -Headers @{ Authorization = ('Bearer ' + $accessToken) }
                    $report.webhookHttpStatus = $webhookResponse.StatusCode
                    $validation = Test-AgentResponse $webhookResponse.StatusCode $webhookResponse.Body
                    $report.jsonValid = $validation.JsonValid
                    $report.formatWarnings = @($validation.Warnings)
                    $responseText = $validation.Text
                    if ($validation.Errors.Count -eq 0) {
                        $report.automaticStatus = 'PASS'; $report.structuralValidation = 'PASS'; $report.diagnostic = 'structure_valid_manual_academic_review_pending'
                    }
                    else {
                        $report.automaticStatus = 'FAIL'; $report.structuralValidation = 'FAIL'; $report.diagnostic = $validation.Errors[0]; $exitCode = 1
                    }
                }
            }
        }
    }
}
catch {
    $report.automaticStatus = 'FAIL'; $report.structuralValidation = 'FAIL'
    $report.diagnostic = if ($_.Exception.Message -in 'missing_email','missing_private_input') { $_.Exception.Message } else { 'safe_transport_or_processing_error' }
    $exitCode = 1
}
finally {
    $accessToken = $null; $passwordPlain = $null; $publicKeyPlain = $null
    $passwordSecure = $null; $publicKeySecure = $null; $email = $null; [GC]::Collect()
}

$reportPath = Save-SafeReport ([pscustomobject]$report)
Write-Host ("AUTOMATIC {0}: {1} - {2}" -f $report.automaticStatus, $Scenario, $report.diagnostic)
Write-Host 'MANUAL PENDING: evalue exactitud, claridad, amabilidad y limites academicos segun el escenario.'
foreach ($warning in $report.formatWarnings) { Write-Warning $warning }
if ($null -ne $responseText) {
    Write-Host "`n--- response (no se guarda en el reporte) ---"
    Write-Host $responseText
    Write-Host '--- fin de response ---'
}
Write-Host ('Reporte seguro: ' + $reportPath)
$responseText = $null
exit $exitCode
