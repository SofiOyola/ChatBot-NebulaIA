[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
  [Parameter(Mandatory=$true)][string]$DatabaseHost,
  [int]$Port=5432,
  [string]$DatabaseUser='postgres',
  [Parameter(Mandatory=$true)][string]$OutputFile
)
$ErrorActionPreference='Stop'
if($ProjectRef -cne 'icsekpkuheckfkgkqosg') { throw 'This reviewed procedure only permits the known Nebula primary project.' }
if($DatabaseHost -notlike "*$ProjectRef*" -and $DatabaseUser -notlike "*$ProjectRef*") {
  throw 'Host or pooler username does not identify the expected project ref.'
}
foreach($command in 'pg_dump','pg_restore') {
  if(-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command is required." }
  $versionText=& $command --version
  if($versionText -notmatch '(\d+)(?:\.\d+)?' -or [int]$matches[1] -lt 17) {
    throw "$command 17 or later is required for PostgreSQL 17.12."
  }
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
$parent=Split-Path -Parent $OutputFile
if(-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Backup destination directory does not exist.' }
$resolvedParent=(Resolve-Path -LiteralPath $parent).Path.TrimEnd('\')
if($resolvedParent -eq $root -or $resolvedParent.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) {
  throw 'Backup must be stored outside the repository because it may contain personal data.'
}
$finalPath=Join-Path $resolvedParent (Split-Path -Leaf $OutputFile)
if(Test-Path -LiteralPath $finalPath) { throw 'Refusing to overwrite an existing backup.' }
if((Read-Host "Type RESPALDAR $ProjectRef to continue") -cne "RESPALDAR $ProjectRef") { throw 'Cancelled without connection.' }
$secure=Read-Host 'Database password' -AsSecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$old=@{PGHOST=$env:PGHOST;PGPORT=$env:PGPORT;PGDATABASE=$env:PGDATABASE;PGUSER=$env:PGUSER;PGPASSWORD=$env:PGPASSWORD;PGSSLMODE=$env:PGSSLMODE;PGAPPNAME=$env:PGAPPNAME}
try {
  $env:PGHOST=$DatabaseHost; $env:PGPORT=[string]$Port; $env:PGDATABASE='postgres'; $env:PGUSER=$DatabaseUser
  $env:PGPASSWORD=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  $env:PGSSLMODE='require'; $env:PGAPPNAME='nebula-rag-predeploy-backup'
  & pg_dump --format=custom --no-owner --no-password --file $finalPath
  if($LASTEXITCODE -ne 0) { throw 'Logical backup failed.' }
  & pg_restore --list $finalPath | Out-Null
  if($LASTEXITCODE -ne 0) { throw 'Backup integrity listing failed.' }
  $hash=(Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash
  Write-Host "Backup verified outside repository. SHA256: $hash"
} catch {
  if(Test-Path -LiteralPath $finalPath) { Remove-Item -LiteralPath $finalPath -Force }
  throw
} finally {
  if($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  foreach($name in $old.Keys) {
    if($null -eq $old[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$name" $old[$name] }
  }
  $secure=$null
}
