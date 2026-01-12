# Valheim World Save Migration Script
# This script helps migrate an existing Valheim world save to Azure File Share

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$WorldSavePath,
    
    [Parameter(Mandatory=$false)]
    [string]$WorldName = "Dedicated",
    
    [Parameter(Mandatory=$false)]
    [string]$FileShareName = "valheim-worlds"
)

Write-Host "Valheim World Save Migration Script" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Validate world save path
if (-not (Test-Path $WorldSavePath)) {
    Write-Host "Error: World save path not found: $WorldSavePath" -ForegroundColor Red
    exit 1
}

# Check for world files
$dbFile = Get-ChildItem -Path $WorldSavePath -Filter "*.db" | Select-Object -First 1
$fwlFile = Get-ChildItem -Path $WorldSavePath -Filter "*.fwl" | Select-Object -First 1

if (-not $dbFile -or -not $fwlFile) {
    Write-Host "Error: World save files (.db and .fwl) not found in $WorldSavePath" -ForegroundColor Red
    exit 1
}

Write-Host "Found world files:" -ForegroundColor Green
Write-Host "  - $($dbFile.Name)"
Write-Host "  - $($fwlFile.Name)"

# Get storage account key
Write-Host "`nRetrieving storage account key..." -ForegroundColor Yellow
try {
    $storageKey = (az storage account keys list `
        --resource-group $ResourceGroupName `
        --account-name $StorageAccountName `
        --query "[0].value" -o tsv)
    
    if (-not $storageKey) {
        throw "Failed to retrieve storage key"
    }
    Write-Host "Storage key retrieved successfully" -ForegroundColor Green
} catch {
    Write-Host "Error: Failed to retrieve storage account key. Make sure Azure CLI is installed and you're logged in." -ForegroundColor Red
    exit 1
}

# Create directory structure
Write-Host "`nCreating directory structure in file share..." -ForegroundColor Yellow
try {
    az storage directory create `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --name "worlds" `
        --output none
    
    az storage directory create `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --name "worlds/$WorldName" `
        --output none
    
    Write-Host "Directory structure created" -ForegroundColor Green
} catch {
    Write-Host "Warning: Directory creation failed (may already exist): $_" -ForegroundColor Yellow
}

# Upload world files
Write-Host "`nUploading world files..." -ForegroundColor Yellow
try {
    az storage file upload `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --source $dbFile.FullName `
        --path "worlds/$WorldName/$($dbFile.Name)" `
        --output none
    
    Write-Host "  ✓ Uploaded $($dbFile.Name)" -ForegroundColor Green
    
    az storage file upload `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --source $fwlFile.FullName `
        --path "worlds/$WorldName/$($fwlFile.Name)" `
        --output none
    
    Write-Host "  ✓ Uploaded $($fwlFile.Name)" -ForegroundColor Green
} catch {
    Write-Host "Error uploading files: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nMigration completed successfully!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Start the server via Discord: /valheim start"
Write-Host "2. Wait 2-3 minutes for the server to start"
Write-Host "3. Connect to the server from Valheim"
Write-Host "4. Verify your world appears in the server list"
