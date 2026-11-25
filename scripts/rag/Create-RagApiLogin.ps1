[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
  [Parameter(Mandatory=$true)][string]$SessionPoolerHost,
  [int]$Port=5432,
  [switch]$AllowDatabaseChange
)
$ErrorActionPreference='Stop'
if(-not $AllowDatabaseChange) { throw 'Use -AllowDatabaseChange only after reviewing the target and precheck.' }
if($ProjectRef -cne 'icsekpkuheckfkgkqosg') { throw 'Unexpected project ref.' }
if($SessionPoolerHost -notmatch '\.pooler\.supabase\.com$') {
  throw 'Copy the Session Pooler host from Supabase Connect; do not compose it.'
}
if($Port -ne 5432) { throw 'This procedure requires Session Pooler port 5432.' }
if(-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw 'psql is required.' }
$version=& psql --version
if($version -notmatch '(\d+)(?:\.\d+)?' -or [int]$matches[1] -lt 17) { throw 'psql 17 or later is required.' }
if((Read-Host "Type CREAR LOGIN RAG $ProjectRef to continue") -cne "CREAR LOGIN RAG $ProjectRef") {
  throw 'Cancelled without connection.'
}
$adminUser="postgres.$ProjectRef"
$secure=Read-Host 'Administrative database password' -AsSecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$names='PGHOST','PGPORT','PGDATABASE','PGUSER','PGPASSWORD','PGSSLMODE','PGAPPNAME','PSQL_HISTORY'
$old=@{}; foreach($name in $names){$old[$name]=[Environment]::GetEnvironmentVariable($name)}
try {
  $env:PGHOST=$SessionPoolerHost; $env:PGPORT=[string]$Port; $env:PGDATABASE='postgres'; $env:PGUSER=$adminUser
  $env:PGPASSWORD=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  $env:PGSSLMODE='require'; $env:PGAPPNAME='nebula-rag-create-limited-login'; $env:PSQL_HISTORY='nul'

  & psql -X --no-password -v ON_ERROR_STOP=1 -f (Join-Path $PSScriptRoot 'precheck_rag_api_login.sql')
  if($LASTEXITCODE -ne 0) { throw 'Read-only login precheck failed; no role was created.' }

  @'
BEGIN;
CREATE ROLE nebula_rag_api_login NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT nebula_rag_api TO nebula_rag_api_login;
COMMIT;
'@ | & psql -X --no-password -v ON_ERROR_STOP=1
  if($LASTEXITCODE -ne 0) { throw 'Role creation failed before password configuration.' }

  Write-Host 'Enter a new random password of at least 32 characters twice. Input is hidden by psql.'
  & psql -X --no-password -v ON_ERROR_STOP=1 -c '\password nebula_rag_api_login'
  if($LASTEXITCODE -ne 0) { throw 'Password setup failed. The partial role remains NOLOGIN and cannot authenticate.' }

  "ALTER ROLE nebula_rag_api_login LOGIN;" | & psql -X --no-password -v ON_ERROR_STOP=1
  if($LASTEXITCODE -ne 0) { throw 'LOGIN was not enabled; the role remains unable to authenticate.' }

  @'
SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls
FROM pg_catalog.pg_roles WHERE rolname='nebula_rag_api_login';
SELECT parent.rolname AS granted_role
FROM pg_catalog.pg_auth_members membership
JOIN pg_catalog.pg_roles member_role ON member_role.oid=membership.member
JOIN pg_catalog.pg_roles parent ON parent.oid=membership.roleid
WHERE member_role.rolname='nebula_rag_api_login';
'@ | & psql -X --no-password -v ON_ERROR_STOP=1
  if($LASTEXITCODE -ne 0) { throw 'Safe post-creation catalog verification failed.' }
} finally {
  if($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  foreach($name in $names) {
    if($null -eq $old[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$name" $old[$name] }
  }
  $secure=$null
}
Write-Host 'Limited RAG login created. Its password was not handled by PowerShell or written to a file.'
