# Usage:
#   .\scripts\migrate-save.ps1 -ResourceGroupName "valheim-server-rg" -StorageAccountName "valheimsa" -FileShareName "valheim-worlds" -WorldName "Dedicated" -WorldDbPath "C:\path\to\world.db" -WorldFwlPath "C:\path\to\world.fwl"

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$FileShareName,
    
    [Parameter(Mandatory=$true)]
    [string]$WorldName,
    
    [Parameter(Mandatory=$true)]
    [string]$WorldDbPath,
    
    [Parameter(Mandatory=$true)]
    [string]$WorldFwlPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host "Valheim World Save Migration" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $WorldDbPath)) {
    Write-Host "Error: World DB file not found: $WorldDbPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $WorldFwlPath)) {
    Write-Host "Error: World FWL file not found: $WorldFwlPath" -ForegroundColor Red
    exit 1
}

$dbFileName = Split-Path -Leaf $WorldDbPath
$fwlFileName = Split-Path -Leaf $WorldFwlPath

if ($dbFileName -ne "$WorldName.db") {
    Write-Host "Warning: DB file name '$dbFileName' doesn't match expected '$WorldName.db'" -ForegroundColor Yellow
    Write-Host "The file will be renamed during migration." -ForegroundColor Yellow
}

if ($fwlFileName -ne "$WorldName.fwl") {
    Write-Host "Warning: FWL file name '$fwlFileName' doesn't match expected '$WorldName.fwl'" -ForegroundColor Yellow
    Write-Host "The file will be renamed during migration." -ForegroundColor Yellow
}

Write-Host "Storage Account: $StorageAccountName" -ForegroundColor Green
Write-Host "File Share: $FileShareName" -ForegroundColor Green
Write-Host "World Name: $WorldName" -ForegroundColor Green
Write-Host ""

Write-Host "Retrieving storage account key..." -ForegroundColor Yellow
$storageKey = az storage account keys list `
    --resource-group $ResourceGroupName `
    --account-name $StorageAccountName `
    --query "[0].value" `
    --output tsv

if (-not $storageKey) {
    Write-Host "Error: Failed to retrieve storage account key" -ForegroundColor Red
    exit 1
}

Write-Host "Checking for existing world..." -ForegroundColor Yellow
$worldPath = "worlds_local"
$existingDb = az storage file exists `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --share-name $FileShareName `
    --path "$worldPath/$WorldName.db" `
    --output tsv 2>$null

$existingFwl = az storage file exists `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --share-name $FileShareName `
    --path "$worldPath/$WorldName.fwl" `
    --output tsv 2>$null

$worldExists = ($existingDb -eq "True") -or ($existingFwl -eq "True")

if ($worldExists) {
    Write-Host "Warning: World '$WorldName' already exists in Azure File Share" -ForegroundColor Yellow
    
    if (-not $Force) {
        $confirm = Read-Host "This will overwrite the existing world. Create backup and continue? (yes/no)"
        if ($confirm -ne "yes") {
            Write-Host "Migration cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "backups/migration-backup-$timestamp/$WorldName"
    
    Write-Host "Creating backup of existing world..." -ForegroundColor Yellow
    
    az storage directory create `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --name "backups" `
        --output none 2>$null
    
    az storage directory create `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --name "backups/migration-backup-$timestamp" `
        --output none 2>$null
    
    az storage directory create `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --name "backups/migration-backup-$timestamp/$WorldName" `
        --output none 2>$null
    
    if ($existingDb -eq "True") {
        az storage file copy start `
            --account-name $StorageAccountName `
            --account-key $storageKey `
            --source-share $FileShareName `
            --source-path "$worldPath/$WorldName.db" `
            --destination-share $FileShareName `
            --destination-path "$backupPath/$WorldName.db" `
            --output none 2>$null
        Write-Host "  Backed up: $WorldName.db" -ForegroundColor Gray
    }
    
    if ($existingFwl -eq "True") {
        az storage file copy start `
            --account-name $StorageAccountName `
            --account-key $storageKey `
            --source-share $FileShareName `
            --source-path "$worldPath/$WorldName.fwl" `
            --destination-share $FileShareName `
            --destination-path "$backupPath/$WorldName.fwl" `
            --output none 2>$null
        Write-Host "  Backed up: $WorldName.fwl" -ForegroundColor Gray
    }
    
    Write-Host "Backup created at: $backupPath" -ForegroundColor Green
    Write-Host ""
}

Write-Host "Creating world directory structure..." -ForegroundColor Yellow
az storage directory create `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --share-name $FileShareName `
    --name "worlds_local" `
    --output none 2>$null

Write-Host "Uploading world files..." -ForegroundColor Yellow

Write-Host "  Uploading $WorldName.db..." -ForegroundColor Gray
az storage file upload `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --share-name $FileShareName `
    --source $WorldDbPath `
    --path "$worldPath/$WorldName.db" `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to upload $WorldName.db" -ForegroundColor Red
    exit 1
}

Write-Host "  Uploading $WorldName.fwl..." -ForegroundColor Gray
az storage file upload `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --share-name $FileShareName `
    --source $WorldFwlPath `
    --path "$worldPath/$WorldName.fwl" `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to upload $WorldName.fwl" -ForegroundColor Red
    exit 1
}

Write-Host "Verifying upload..." -ForegroundColor Yellow
$verifyDb = az storage file exists `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --share-name $FileShareName `
    --path "$worldPath/$WorldName.db" `
    --output tsv

$verifyFwl = az storage file exists `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --share-name $FileShareName `
    --path "$worldPath/$WorldName.fwl" `
    --output tsv

if ($verifyDb -eq "True" -and $verifyFwl -eq "True") {
    Write-Host "Migration completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  World Name: $WorldName" -ForegroundColor Gray
    Write-Host "  Location: $worldPath/" -ForegroundColor Gray
    if ($worldExists) {
        Write-Host "  Backup: backups/migration-backup-$timestamp/" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "The world will be available when you start the Valheim server." -ForegroundColor Green
} else {
    Write-Host "Error: Verification failed. Files may not have uploaded correctly." -ForegroundColor Red
    exit 1
}
