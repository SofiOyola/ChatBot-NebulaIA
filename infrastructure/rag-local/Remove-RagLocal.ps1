[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if((Read-Host 'Type ELIMINAR RAG LOCAL to remove only this stack and its volume') -cne 'ELIMINAR RAG LOCAL') {
  throw 'Cancelled without changes.'
}
& docker compose --env-file (Join-Path $PSScriptRoot '.env.rag-local') -f (Join-Path $PSScriptRoot 'compose.yaml') down --volumes --remove-orphans
if($LASTEXITCODE -ne 0) { throw 'Failed to remove the isolated RAG stack.' }
Write-Host 'Only nebula-rag-local-it containers, network and volume were removed.'
