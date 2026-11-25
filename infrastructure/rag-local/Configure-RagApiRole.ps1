[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$envFile=Join-Path $PSScriptRoot '.env.rag-local'
if(-not (Test-Path -LiteralPath $envFile)) { throw 'Start-RagLocal.ps1 must create the local environment first.' }
$values=@{}
Get-Content -LiteralPath $envFile | ForEach-Object {
  if($_ -match '^([^#=]+)=(.*)$') { $values[$matches[1]]=$matches[2] }
}
if([string]::IsNullOrWhiteSpace($values.RAG_LOCAL_API_PASSWORD)) { throw 'Local API password is missing.' }
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$migration=Join-Path $root 'supabase\migrations\20261124090000_rag_api_role.sql'
Get-Content -LiteralPath $migration -Raw | & docker exec -i nebula-rag-local-postgres psql -X -v ON_ERROR_STOP=1 -U postgres -d rag_local
if($LASTEXITCODE -ne 0) { throw 'Failed to apply the local RAG API permission role.' }
$escaped=$values.RAG_LOCAL_API_PASSWORD.Replace("'", "''")
$sql=@"
DO `$login`$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='nebula_rag_api_login') THEN
    CREATE ROLE nebula_rag_api_login LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
END;
`$login`$;
ALTER ROLE nebula_rag_api_login PASSWORD '$escaped';
GRANT nebula_rag_api TO nebula_rag_api_login;
"@
$sql | & docker exec -i nebula-rag-local-postgres psql -X -v ON_ERROR_STOP=1 -U postgres -d rag_local
if($LASTEXITCODE -ne 0) { throw 'Failed to configure the local RAG API login.' }
Write-Host 'Local RAG API role configured without displaying its credential.'
