[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
& docker compose --env-file (Join-Path $PSScriptRoot '.env.rag-local') -f (Join-Path $PSScriptRoot 'compose.yaml') stop
if($LASTEXITCODE -ne 0) { throw 'Failed to stop the isolated RAG stack.' }
Write-Host 'Only nebula-rag-local-it services were stopped; its volume was preserved.'
