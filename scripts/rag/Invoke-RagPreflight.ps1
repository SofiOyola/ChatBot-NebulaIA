[CmdletBinding()]
param([switch]$AllowRemoteReadOnly)
$ErrorActionPreference='Stop'
if(-not $AllowRemoteReadOnly) { throw 'Use -AllowRemoteReadOnly for an explicitly reviewed target.' }
$databaseUrl=[Environment]::GetEnvironmentVariable('RAG_TARGET_DATABASE_URL')
if([string]::IsNullOrWhiteSpace($databaseUrl)) { throw 'RAG_TARGET_DATABASE_URL is required.' }
if(-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw 'psql is required.' }
if((Read-Host 'Type AUDITAR SIN CAMBIOS to continue') -cne 'AUDITAR SIN CAMBIOS') { throw 'Cancelled without changes.' }
$old=$env:PGOPTIONS
try {
  $env:PGOPTIONS='-c default_transaction_read_only=on'
  & psql $databaseUrl -X -v ON_ERROR_STOP=1 -f (Join-Path $PSScriptRoot 'preflight_rag_deployment.sql')
  if($LASTEXITCODE -ne 0) { throw 'Read-only RAG preflight failed.' }
} finally {
  if($null -eq $old) { Remove-Item Env:PGOPTIONS -ErrorAction SilentlyContinue } else { $env:PGOPTIONS=$old }
}
