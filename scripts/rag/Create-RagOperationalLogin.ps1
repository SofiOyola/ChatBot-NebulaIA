[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('Ingest','Reviewer')][string]$Identity,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
  [Parameter(Mandatory=$true)][string]$SessionPoolerHost,
  [int]$Port=5432,
  [switch]$AllowDatabaseChange
)
$ErrorActionPreference='Stop'
$identities=@{
  Ingest=@{ Login='nebula_rag_ingest_login'; PermissionRole='nebula_rag_ingest' }
  Reviewer=@{ Login='nebula_rag_reviewer_login'; PermissionRole='nebula_rag_reviewer' }
}
$selected=$identities[$Identity]
$loginName=$selected.Login
$permissionRole=$selected.PermissionRole
if(-not $AllowDatabaseChange) { throw 'Use -AllowDatabaseChange only after reviewing the target and precheck.' }
if($ProjectRef -cne 'icsekpkuheckfkgkqosg') { throw 'Unexpected project ref.' }
if($SessionPoolerHost -notmatch '\.pooler\.supabase\.com$') {
  throw 'Copy the Session Pooler host from Supabase Connect; do not compose it.'
}
if($Port -ne 5432) { throw 'This procedure requires Session Pooler port 5432.' }
if(-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw 'psql is required.' }
$version=& psql --version
if($version -notmatch '(\d+)(?:\.\d+)?' -or [int]$matches[1] -lt 17) { throw 'psql 17 or later is required.' }
$confirmation="CREAR $loginName EN $ProjectRef"
if((Read-Host "Type $confirmation to continue") -cne $confirmation) { throw 'Cancelled without connection.' }
$passwordConfirmation="CONFIRMO CLAVE EXCLUSIVA ALEATORIA 32+ PARA $loginName"
if((Read-Host "Type $passwordConfirmation") -cne $passwordConfirmation) {
  throw 'Password quality confirmation was not provided.'
}
$adminUser="postgres.$ProjectRef"
$secure=Read-Host 'Administrative database password' -AsSecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$names='PGHOST','PGPORT','PGDATABASE','PGUSER','PGPASSWORD','PGSSLMODE','PGAPPNAME','PSQL_HISTORY'
$old=@{}; foreach($name in $names){$old[$name]=[Environment]::GetEnvironmentVariable($name)}
try {
  $env:PGHOST=$SessionPoolerHost; $env:PGPORT=[string]$Port; $env:PGDATABASE='postgres'; $env:PGUSER=$adminUser
  $env:PGPASSWORD=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  $env:PGSSLMODE='require'; $env:PGAPPNAME="nebula-rag-create-$Identity-login"; $env:PSQL_HISTORY='nul'

  & psql -X --no-password -v ON_ERROR_STOP=1 -v "login_name=$loginName" -v "permission_role=$permissionRole" `
    -f (Join-Path $PSScriptRoot 'precheck_rag_operational_login.sql')
  if($LASTEXITCODE -ne 0) { throw 'Read-only operational login precheck failed; no role was created.' }
  $applyConfirmation="APLICAR CREACION DE $loginName"
  if((Read-Host "Review the precheck result, then type $applyConfirmation") -cne $applyConfirmation) {
    throw 'Cancelled after read-only precheck; no role was created.'
  }

  @"
BEGIN;
CREATE ROLE $loginName NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT $permissionRole TO $loginName;
COMMIT;
"@ | & psql -X --no-password -v ON_ERROR_STOP=1
  if($LASTEXITCODE -ne 0) { throw 'Role creation failed before password configuration.' }

  Write-Host 'Enter a different random password of at least 32 characters twice. Input is hidden by psql.'
  & psql -X --no-password -v ON_ERROR_STOP=1 -c "\password $loginName"
  if($LASTEXITCODE -ne 0) { throw 'Password setup failed. The partial role remains NOLOGIN.' }

  "ALTER ROLE $loginName LOGIN;" | & psql -X --no-password -v ON_ERROR_STOP=1
  if($LASTEXITCODE -ne 0) { throw 'LOGIN was not enabled; the role remains unable to authenticate.' }

  @"
DO `$verify`$
DECLARE login_oid oid; membership_count integer;
BEGIN
  SELECT oid INTO login_oid FROM pg_catalog.pg_roles WHERE rolname='$loginName'
    AND rolcanlogin AND rolinherit AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
    AND NOT rolreplication AND NOT rolbypassrls;
  IF login_oid IS NULL THEN RAISE EXCEPTION 'new operational login attributes are unsafe'; END IF;
  SELECT pg_catalog.count(*) INTO membership_count FROM pg_catalog.pg_auth_members WHERE member=login_oid;
  IF membership_count<>1 OR NOT pg_catalog.pg_has_role('$loginName','$permissionRole','MEMBER') THEN
    RAISE EXCEPTION 'new operational login membership is not exclusive';
  END IF;
END;
`$verify`$;
SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls
FROM pg_catalog.pg_roles WHERE rolname='$loginName';
SELECT parent.rolname AS granted_role
FROM pg_catalog.pg_auth_members membership
JOIN pg_catalog.pg_roles member_role ON member_role.oid=membership.member
JOIN pg_catalog.pg_roles parent ON parent.oid=membership.roleid
WHERE member_role.rolname='$loginName';
"@ | & psql -X --no-password -v ON_ERROR_STOP=1
  if($LASTEXITCODE -ne 0) { throw 'Safe post-creation catalog verification failed.' }
} finally {
  if($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  foreach($name in $names) {
    if($null -eq $old[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$name" $old[$name] }
  }
  $secure=$null
}
Write-Host "Operational RAG login $loginName created; its password was not handled by PowerShell or written to a file."
