[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$verify=Join-Path $PSScriptRoot 'verify-postgres.sql'
Get-Content -Raw -LiteralPath $verify | & docker exec -i nebula-rag-local-postgres psql -X -v ON_ERROR_STOP=1 -U postgres -d rag_local
if($LASTEXITCODE -ne 0) { throw 'PostgreSQL verification failed.' }
$previous=$env:NEBULA_RAG_POSTGREST_TEST
try {
  $env:NEBULA_RAG_POSTGREST_TEST='1'
  python -m pytest -v (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'tests\test_rag_postgrest_local.py')
  if($LASTEXITCODE -ne 0) { throw 'PostgREST verification failed.' }
} finally {
  if($null -eq $previous) { Remove-Item Env:NEBULA_RAG_POSTGREST_TEST -ErrorAction SilentlyContinue }
  else { $env:NEBULA_RAG_POSTGREST_TEST=$previous }
}
