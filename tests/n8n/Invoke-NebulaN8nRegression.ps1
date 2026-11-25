[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^T0[1-8]$')]
    [string]$CaseId,

    [ValidateSet('Real', 'Simulation')]
    [string]$Transport = 'Real',

    [ValidateSet('Expected', 'WrongStatus', 'WrongJson')]
    [string]$SimulationScenario = 'Expected',

    [switch]$AllowNetwork,
    [switch]$ConfirmedWorkflowListening,
    [switch]$NonInteractive,
    [string]$ReportDirectory = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $ReportDirectory = Join-Path $PSScriptRoot 'reports'
}

function Write-JsonUtf8NoBom {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path)
    $json = $Value | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Test-JsonSubset {
    param($Expected, $Actual, [string]$Path = '$')
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($property in $Expected.PSObject.Properties) {
        $actualProperty = $Actual.PSObject.Properties[$property.Name]
        if ($null -eq $actualProperty) {
            $errors.Add("Falta la propiedad JSON $Path.$($property.Name)")
            continue
        }
        if ($property.Value -is [System.Management.Automation.PSCustomObject]) {
            foreach ($nested in (Test-JsonSubset $property.Value $actualProperty.Value "$Path.$($property.Name)")) {
                $errors.Add($nested)
            }
        }
        elseif ($property.Value -ne $actualProperty.Value) {
            $errors.Add("Valor JSON distinto en $Path.$($property.Name)")
        }
    }
    return $errors
}

function Get-SimulatedResponse {
    param($Case, [string]$Scenario)
    $status = [int]$Case.expectedStatus
    $body = $Case.expectedJson | ConvertTo-Json -Compress -Depth 10
    if ($Scenario -eq 'WrongStatus') { $status = 200 }
    if ($Scenario -eq 'WrongJson') { $body = '{"error":"unexpected_value"}' }
    return [pscustomobject]@{ StatusCode = $status; Body = $body }
}

function Invoke-RealRequest {
    param($Case, [string]$Url)
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = 'POST'
    $request.ContentType = 'application/json; charset=utf-8'
    $request.Accept = 'application/json'
    $request.Timeout = 30000

    # Estos dos valores son fixtures publicos y deliberadamente no validos.
    if ($Case.authorizationMode -eq 'malformed') {
        $request.Headers['Authorization'] = 'Token formato_invalido'
    }
    elseif ($Case.authorizationMode -eq 'invalid-fictitious') {
        $request.Headers['Authorization'] = 'Bearer token_ficticio_no_valido_12345'
    }

    $json = $Case.body | ConvertTo-Json -Compress -Depth 10
    $bytes = $utf8NoBom.GetBytes($json)
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream()
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }

    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
    }
    catch [System.Net.WebException] {
        if ($null -eq $_.Exception.Response) { throw }
        $response = [System.Net.HttpWebResponse]$_.Exception.Response
    }
    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $body }
    }
    finally { $response.Dispose() }
}

$definitionPath = Join-Path $PSScriptRoot 'cases.json'
$definition = [System.IO.File]::ReadAllText($definitionPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$case = $definition.cases | Where-Object { $_.id -eq $CaseId } | Select-Object -First 1
if ($null -eq $case) { throw "Caso desconocido: $CaseId" }

$result = [ordered]@{
    caseId = $case.id
    description = $case.description
    transport = $Transport
    status = 'SKIP'
    expectedHttpStatus = $case.expectedStatus
    observedHttpStatus = $null
    errors = @()
    manualEvidence = $case.manualEvidence
    timestampUtc = [DateTime]::UtcNow.ToString('o')
}
$exitCode = 0

if ($case.skipReason) {
    $result.errors = @($case.skipReason)
}
elseif ($Transport -eq 'Real' -and -not $AllowNetwork) {
    $result.errors = @('solicitud real bloqueada: vuelva a ejecutar con -AllowNetwork')
}
elseif ($Transport -eq 'Real' -and -not $ConfirmedWorkflowListening) {
    if ($NonInteractive) {
        $result.errors = @('falta -ConfirmedWorkflowListening despues de activar Execute workflow en n8n')
    }
    else {
        $confirmation = Read-Host 'Active Execute workflow en n8n. Escriba EJECUTAR cuando el webhook-test este escuchando'
        if ($confirmation -ne 'EJECUTAR') {
            $result.errors = @('el usuario no confirmo que el webhook-test estuviera escuchando')
        }
        else { $ConfirmedWorkflowListening = $true }
    }
}

if (-not $case.skipReason -and ($Transport -eq 'Simulation' -or ($AllowNetwork -and $ConfirmedWorkflowListening))) {
    try {
        if ($Transport -eq 'Simulation') {
            $response = Get-SimulatedResponse $case $SimulationScenario
        }
        else {
            $response = Invoke-RealRequest $case $definition.webhookUrl
        }
        $result.observedHttpStatus = $response.StatusCode
        $assertionErrors = New-Object System.Collections.Generic.List[string]
        if ($response.StatusCode -ne [int]$case.expectedStatus) {
            $assertionErrors.Add("HTTP esperado $($case.expectedStatus), recibido $($response.StatusCode)")
        }
        try { $actualJson = $response.Body | ConvertFrom-Json }
        catch { $assertionErrors.Add('la respuesta no es JSON valido'); $actualJson = $null }
        if ($null -ne $actualJson) {
            foreach ($jsonError in (Test-JsonSubset $case.expectedJson $actualJson)) { $assertionErrors.Add($jsonError) }
        }
        if ($assertionErrors.Count -eq 0) { $result.status = 'PASS' }
        else { $result.status = 'FAIL'; $result.errors = @($assertionErrors); $exitCode = 1 }
    }
    catch {
        $result.status = 'FAIL'
        $result.errors = @('fallo de transporte: ' + $_.Exception.Message)
        $exitCode = 1
    }
}

if (-not (Test-Path -LiteralPath $ReportDirectory)) {
    New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
}
$reportPath = Join-Path $ReportDirectory ("{0}-{1}.json" -f $CaseId, [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
Write-JsonUtf8NoBom ([pscustomobject]$result) $reportPath
Write-Host ("{0}: {1} - {2}" -f $result.status, $case.id, $case.description)
if ($result.errors.Count -gt 0) { $result.errors | ForEach-Object { Write-Host ("  " + $_) } }
if ($case.manualEvidence) { Write-Host ("  " + $case.manualEvidence) }
Write-Host ("Reporte: " + $reportPath)
exit $exitCode
