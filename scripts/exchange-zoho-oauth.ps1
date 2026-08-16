# Exchanges a Zoho Self Client grant code for access + refresh tokens.
# Run from the repo root:
#   pwsh -File scripts/exchange-zoho-oauth.ps1
#
# You will be prompted for client_id, client_secret, and the Generate Code
# value. The grant code expires in a few minutes — run this immediately
# after creating it in https://api-console.zoho.com/

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host 'Zoho Self Client — exchange grant code for refresh token'
Write-Host 'Do not paste these values into chat.'
Write-Host ''

$clientId = (Read-Host 'Client ID').Trim()
$clientSecret = (Read-Host 'Client Secret').Trim()
$grantCode = (Read-Host 'Grant code (Generate Code)').Trim()

if (-not $clientId -or -not $clientSecret -or -not $grantCode) {
    Write-Host 'All three values are required.' -ForegroundColor Red
    exit 1
}

$accountsHost = 'accounts.zoho.com'
$tokenUrl = "https://$accountsHost/oauth/v2/token"

Write-Host ''
Write-Host "POST $tokenUrl ..."

try {
    $response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body @{
        grant_type    = 'authorization_code'
        client_id     = $clientId
        client_secret = $clientSecret
        code          = $grantCode
    }
}
catch {
    Write-Host 'Request failed.' -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host $_.ErrorDetails.Message
    }
    else {
        Write-Host $_.Exception.Message
    }
    Write-Host ''
    Write-Host 'If the error is invalid_code, generate a new code and run this again immediately.'
    exit 1
}

if ($response.error) {
    Write-Host "Zoho error: $($response.error)" -ForegroundColor Red
    if ($response.error_description) {
        Write-Host $response.error_description
    }
    exit 1
}

if (-not $response.refresh_token) {
    Write-Host 'No refresh_token in the response. Zoho returned:' -ForegroundColor Red
    $response | ConvertTo-Json -Depth 5
    exit 1
}

Write-Host ''
Write-Host 'Success. Save the refresh token — it is shown only here.' -ForegroundColor Green
Write-Host ''
Write-Host "scope:         $($response.scope)"
Write-Host "api_domain:    $($response.api_domain)"
Write-Host "token_type:    $($response.token_type)"
Write-Host "expires_in:    $($response.expires_in)"
Write-Host ''
Write-Host 'access_token (short-lived):'
Write-Host $response.access_token
Write-Host ''
Write-Host 'refresh_token (put this in Firestore server_config/zoho field "code"):'
Write-Host $response.refresh_token
Write-Host ''
Write-Host 'Firestore document server_config/zoho:'
Write-Host "  client_id        = (the Client ID you typed)"
Write-Host "  client_secret    = (the Client Secret you typed)"
Write-Host "  code             = (the refresh_token above)"
Write-Host "  organization_id  = 783019958"
Write-Host ''
