[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
  [Parameter(Mandatory=$true)][string]$DatabaseHost,
  [int]$Port=5432,
  [string]$DatabaseUser='postgres',
  [switch]$AllowPrimaryDeployment
)
$ErrorActionPreference='Stop'
if(-not $AllowPrimaryDeployment) { throw 'Use -AllowPrimaryDeployment only after backup and reviewed preflight.' }
if($ProjectRef -cne 'icsekpkuheckfkgkqosg') { throw 'Unexpected project ref.' }
if($DatabaseHost -notlike "*$ProjectRef*" -and $DatabaseUser -notlike "*$ProjectRef*") {
  throw 'Host or pooler username does not identify the expected project ref.'
}
if(-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw 'psql is required.' }
$versionText=& psql --version
if($versionText -notmatch '(\d+)(?:\.\d+)?' -or [int]$matches[1] -lt 17) {
  throw 'psql 17 or later is required for the PostgreSQL 17.12 deployment.'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$migrations=@(
  'supabase\migrations\20261124060000_rag_academic_documents.sql',
  'supabase\migrations\20261124070000_rag_document_lifecycle.sql',
  'supabase\migrations\20261124080000_rag_classification_hybrid_search.sql',
  'supabase\migrations\20261124090000_rag_api_role.sql'
)
foreach($relative in $migrations) { if(-not (Test-Path -LiteralPath (Join-Path $root $relative))) { throw "Missing migration: $relative" } }
if((Read-Host "Type DESPLEGAR RAG $ProjectRef to continue") -cne "DESPLEGAR RAG $ProjectRef") { throw 'Cancelled without connection.' }
$secure=Read-Host 'Database password' -AsSecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$names='PGHOST','PGPORT','PGDATABASE','PGUSER','PGPASSWORD','PGSSLMODE','PGAPPNAME','PGOPTIONS'
$old=@{}; foreach($name in $names){$old[$name]=[Environment]::GetEnvironmentVariable($name)}
try {
  $env:PGHOST=$DatabaseHost; $env:PGPORT=[string]$Port; $env:PGDATABASE='postgres'; $env:PGUSER=$DatabaseUser
  $env:PGPASSWORD=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  $env:PGSSLMODE='require'; $env:PGAPPNAME='nebula-rag-reviewed-deployment'
  $env:PGOPTIONS='-c lock_timeout=5s -c statement_timeout=120s'
  foreach($relative in $migrations) {
    & psql -X --no-password -v ON_ERROR_STOP=1 -f (Join-Path $root $relative)
    if($LASTEXITCODE -ne 0) { throw "Migration failed; later migrations were not attempted: $relative" }
  }
  & psql -X --no-password -v ON_ERROR_STOP=1 -f (Join-Path $PSScriptRoot 'verify_rag_deployment.sql')
  if($LASTEXITCODE -ne 0) { throw 'Post-deployment verification failed.' }
  Write-Host 'RAG schema, RPCs and NOLOGIN permission role were deployed and verified. No service login was created.'
} finally {
  if($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  foreach($name in $names) {
    if($null -eq $old[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$name" $old[$name] }
  }
  $secure=$null
}
