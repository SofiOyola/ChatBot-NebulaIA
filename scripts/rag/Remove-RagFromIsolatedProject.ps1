[CmdletBinding()]
param([switch]$AllowRemote,[Parameter(Mandatory=$true)][string]$ExpectedProjectRef)
$ErrorActionPreference='Stop'
if (-not $AllowRemote) { throw 'Use -AllowRemote only for an isolated project.' }
if ($ExpectedProjectRef -eq 'icsekpkuheckfkgkqosg') { throw 'The known primary project is blocked.' }
$databaseUrl=[Environment]::GetEnvironmentVariable('RAG_TEST_DATABASE_URL')
if ([string]::IsNullOrWhiteSpace($databaseUrl) -or $databaseUrl -notlike "*$ExpectedProjectRef*") {
    throw 'RAG_TEST_DATABASE_URL does not match the isolated project.'
}
if ((Read-Host 'Type ELIMINAR RAG AISLADO to drop only RAG objects') -cne 'ELIMINAR RAG AISLADO') {
    throw 'Cancelled without changes.'
}
& psql $databaseUrl -X -v ON_ERROR_STOP=1 -f (Join-Path $PSScriptRoot 'rollback_rag_isolated.sql')
if ($LASTEXITCODE -ne 0) { throw 'RAG rollback failed.' }
Write-Host 'RAG schema and RAG RPCs removed; academic and student schemas were not targeted.'
