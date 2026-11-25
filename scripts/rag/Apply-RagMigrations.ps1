[CmdletBinding()]
param(
    [switch]$AllowRemote,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ExpectedProjectRef
)
$ErrorActionPreference = 'Stop'
$productionProjectRef = 'icsekpkuheckfkgkqosg'
if (-not $AllowRemote) { throw 'Use -AllowRemote only after selecting an isolated Supabase project.' }
if ($ExpectedProjectRef -eq $productionProjectRef) { throw 'The known primary project is blocked. Use an isolated test project.' }
$databaseUrl = [Environment]::GetEnvironmentVariable('RAG_TEST_DATABASE_URL')
if ([string]::IsNullOrWhiteSpace($databaseUrl) -or $databaseUrl -notlike "*$ExpectedProjectRef*") {
    throw 'RAG_TEST_DATABASE_URL is missing or does not match ExpectedProjectRef.'
}
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw 'psql is required.' }
$confirmation = Read-Host 'Type APLICAR RAG AISLADO to continue'
if ($confirmation -cne 'APLICAR RAG AISLADO') { throw 'Cancelled without changes.' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$migrations = @(
    'supabase\migrations\20261124060000_rag_academic_documents.sql',
    'supabase\migrations\20261124070000_rag_document_lifecycle.sql',
    'supabase\migrations\20261124080000_rag_classification_hybrid_search.sql',
    'supabase\migrations\20261124090000_rag_api_role.sql'
)
foreach ($relativePath in $migrations) {
    $path = Join-Path $root $relativePath
    & psql $databaseUrl -X -v ON_ERROR_STOP=1 -f $path
    if ($LASTEXITCODE -ne 0) { throw "Migration failed: $relativePath" }
}
& psql $databaseUrl -X -v ON_ERROR_STOP=1 -f (Join-Path $PSScriptRoot 'verify_rag_deployment.sql')
if ($LASTEXITCODE -ne 0) { throw 'Post-deployment SQL verification failed.' }
Write-Host 'RAG migrations and SQL verification completed in the isolated project.'
