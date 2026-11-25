[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$compose=Join-Path $PSScriptRoot 'compose.yaml'
$envFile=Join-Path $PSScriptRoot '.env.rag-local'
foreach($name in @('nebula-rag-local-postgres','nebula-rag-local-postgrest')) {
  $existing=& docker ps -a --filter "name=^/$name$" --format '{{.Names}}'
  if($existing) {
    $inspection=(& docker inspect $name | ConvertFrom-Json)[0]
    $project=$inspection.Config.Labels.'com.docker.compose.project'
    if($project -ne 'nebula-rag-local-it') { throw "Container name collision: $name" }
  }
}
if(-not (Test-Path $envFile)) {
  function New-LocalSecret([int]$bytes) {
    $buffer=New-Object byte[] $bytes
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buffer)
    return ([Convert]::ToBase64String($buffer) -replace '[^A-Za-z0-9]','')
  }
  @(
    "RAG_LOCAL_DB_PASSWORD=$(New-LocalSecret 24)",
    "RAG_LOCAL_AUTHENTICATOR_PASSWORD=$(New-LocalSecret 24)",
    "RAG_LOCAL_API_PASSWORD=$(New-LocalSecret 24)",
    "RAG_LOCAL_JWT_SECRET=$(New-LocalSecret 48)"
  ) | Set-Content -LiteralPath $envFile -Encoding ASCII
}
elseif(-not (Select-String -LiteralPath $envFile -Pattern '^RAG_LOCAL_API_PASSWORD=' -Quiet)) {
  $buffer=New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buffer)
  $secret=([Convert]::ToBase64String($buffer) -replace '[^A-Za-z0-9]','')
  Add-Content -LiteralPath $envFile -Value "RAG_LOCAL_API_PASSWORD=$secret" -Encoding ASCII
}
foreach($port in 55432,53000) {
  $owner=Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
  $ownRunning=& docker ps --filter 'label=com.docker.compose.project=nebula-rag-local-it' --format '{{.Names}}'
  if($owner -and -not $ownRunning) { throw "Local port $port is already in use." }
}
& docker compose --env-file $envFile -f $compose up -d
if($LASTEXITCODE -ne 0) { throw 'Failed to start the isolated RAG stack.' }
for($attempt=0;$attempt -lt 60;$attempt++) {
  try {
    $response=Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:53000/' -TimeoutSec 2
    if($response.StatusCode -eq 200) { Write-Host 'RAG local ready: PostgreSQL 127.0.0.1:55432; PostgREST 127.0.0.1:53000'; exit 0 }
  } catch { Start-Sleep -Seconds 1 }
}
throw 'PostgREST did not become ready within 60 seconds.'
