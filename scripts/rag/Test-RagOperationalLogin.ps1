[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('Ingest','Reviewer')][string]$Identity,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
  [Parameter(Mandatory=$true)][string]$SessionPoolerHost,
  [int]$Port=5432,
  [switch]$AllowNetwork
)
$ErrorActionPreference='Stop'
$identities=@{
  Ingest=@{ Login='nebula_rag_ingest_login'; Verifier='verify_rag_ingest_login.sql' }
  Reviewer=@{ Login='nebula_rag_reviewer_login'; Verifier='verify_rag_reviewer_login.sql' }
}
$selected=$identities[$Identity]
$loginName=$selected.Login
if(-not $AllowNetwork) { throw 'Use -AllowNetwork only after the login has been provisioned.' }
if($ProjectRef -cne 'icsekpkuheckfkgkqosg') { throw 'Unexpected project ref.' }
if($SessionPoolerHost -notmatch '\.pooler\.supabase\.com$' -or $Port -ne 5432) {
  throw 'Use the reviewed Session Pooler host and port 5432.'
}
if(-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw 'psql is required.' }
$confirmation="VERIFICAR $loginName EN $ProjectRef"
if((Read-Host "Type $confirmation to connect") -cne $confirmation) { throw 'Cancelled without connection.' }
$secure=Read-Host "$loginName database password" -AsSecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$names='PGHOST','PGPORT','PGDATABASE','PGUSER','PGPASSWORD','PGSSLMODE','PGAPPNAME','PSQL_HISTORY'
$old=@{}; foreach($name in $names){$old[$name]=[Environment]::GetEnvironmentVariable($name)}
try {
  $env:PGHOST=$SessionPoolerHost; $env:PGPORT=[string]$Port; $env:PGDATABASE='postgres'
  $env:PGUSER="$loginName.$ProjectRef"; $env:PGPASSWORD=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  $env:PGSSLMODE='require'; $env:PGAPPNAME="nebula-rag-verify-$Identity-login"; $env:PSQL_HISTORY='nul'
  & psql -X --no-password -v ON_ERROR_STOP=1 -f (Join-Path $PSScriptRoot $selected.Verifier)
  if($LASTEXITCODE -ne 0) { throw 'Operational login verification failed.' }
} finally {
  if($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  foreach($name in $names) {
    if($null -eq $old[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$name" $old[$name] }
  }
  $secure=$null
}
