[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$previous=$env:NEBULA_RAG_HTTP_TEST
try {
  $env:NEBULA_RAG_HTTP_TEST='1'
  $root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  python -m pytest -v (Join-Path $root 'tests\test_rag_http_local.py')
  if($LASTEXITCODE -ne 0) { throw 'RAG HTTP integration verification failed.' }
} finally {
  if($null -eq $previous) { Remove-Item Env:NEBULA_RAG_HTTP_TEST -ErrorAction SilentlyContinue }
  else { $env:NEBULA_RAG_HTTP_TEST=$previous }
}
