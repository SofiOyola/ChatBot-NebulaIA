[CmdletBinding()]
param([switch]$AllowExternalApi)
$ErrorActionPreference='Stop'
if(-not $AllowExternalApi) { throw 'Use -AllowExternalApi only after approving exactly two Gemini embedding requests.' }
if((Read-Host 'Type PROBAR EMBEDDINGS GEMINI to continue') -cne 'PROBAR EMBEDDINGS GEMINI') {
  throw 'Cancelled without external requests.'
}
$secure=Read-Host 'Gemini API key' -AsSecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$previous=$env:GEMINI_API_KEY
try {
  $env:GEMINI_API_KEY=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  $root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  python (Join-Path $PSScriptRoot 'verify_gemini_embedding.py')
  if($LASTEXITCODE -ne 0) { throw 'Controlled Gemini embedding validation failed.' }
} finally {
  if($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  if($null -eq $previous) { Remove-Item Env:GEMINI_API_KEY -ErrorAction SilentlyContinue }
  else { $env:GEMINI_API_KEY=$previous }
  $secure=$null
}
