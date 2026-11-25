function New-DeterministicallyInvalidJwt {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$AccessToken)

    $segments = $AccessToken.Split('.')
    if ($segments.Count -ne 3 -or [string]::IsNullOrWhiteSpace($segments[0]) -or
        [string]::IsNullOrWhiteSpace($segments[1]) -or [string]::IsNullOrWhiteSpace($segments[2])) {
        throw 'access_token_is_not_a_three_segment_jwt'
    }
    $signature = $segments[2]
    $replacement = if ($signature[0] -eq 'A') { 'B' } else { 'A' }
    $invalidSignature = $replacement + $signature.Substring(1)
    return $segments[0] + '.' + $segments[1] + '.' + $invalidSignature
}
