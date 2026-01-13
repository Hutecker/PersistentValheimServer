# Script to add Discord Public Key to Key Vault
# This is required for Discord interactions endpoint verification

param(
    [Parameter(Mandatory=$true)]
    [string]$PublicKey,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "valheim-server-rg"
)

Write-Host ""
Write-Host "Adding Discord Public Key to Key Vault" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Get Key Vault name
$keyVaultName = az keyvault list --resource-group $ResourceGroupName --query "[0].name" -o tsv

if (-not $keyVaultName) {
    Write-Host "Error: Key Vault not found in resource group: $ResourceGroupName" -ForegroundColor Red
    exit 1
}

Write-Host "Key Vault: $keyVaultName" -ForegroundColor Gray
Write-Host ""

# Validate public key format (should be 64 hex characters)
$PublicKey = $PublicKey.Trim()
if ($PublicKey.Length -ne 64) {
    Write-Host "Warning: Discord public key should be 64 hex characters" -ForegroundColor Yellow
    Write-Host "  Current length: $($PublicKey.Length)" -ForegroundColor Gray
    $confirm = Read-Host "Continue anyway? (y/n)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Add secret to Key Vault
Write-Host "Adding DiscordPublicKey secret..." -ForegroundColor Yellow
az keyvault secret set `
    --vault-name $keyVaultName `
    --name "DiscordPublicKey" `
    --value $PublicKey `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Host "Discord Public Key added successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "The Function App will now be able to verify Discord signatures." -ForegroundColor Gray
    Write-Host "Try setting the interactions endpoint URL again in Discord Developer Portal." -ForegroundColor Gray
} else {
    Write-Host "Error: Failed to add Discord Public Key" -ForegroundColor Red
    exit 1
}
