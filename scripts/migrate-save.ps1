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

# Check if world already exists and create backup
Write-Host "`nChecking for existing world..." -ForegroundColor Yellow
$existingDbPath = "worlds/$WorldName/$($dbFile.Name)"
$existingFwlPath = "worlds/$WorldName/$($fwlFile.Name)"

$existingDb = az storage file exists `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --share-name $FileShareName `
    --path $existingDbPath `
    --query "exists" -o tsv 2>$null

if ($existingDb -eq "true") {
    Write-Host "⚠️  WARNING: World '$WorldName' already exists in Azure File Share!" -ForegroundColor Yellow
    Write-Host "This will overwrite the existing world save." -ForegroundColor Yellow
    
    # Create backup of existing world
    $backupTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = "backups/migration-backup-$backupTimestamp"
    
    Write-Host "`nCreating backup of existing world..." -ForegroundColor Yellow
    try {
        # Create backup directory
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
            --name $backupDir `
            --output none 2>$null
        
        # Copy existing files to backup
        $backupDbPath = "$backupDir/$($dbFile.Name)"
        $backupFwlPath = "$backupDir/$($fwlFile.Name)"
        
        # Download existing files temporarily to backup them
        $tempDir = Join-Path $env:TEMP "valheim-backup-$backupTimestamp"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        az storage file download `
            --account-name $StorageAccountName `
            --account-key $storageKey `
            --share-name $FileShareName `
            --path $existingDbPath `
            --dest "$tempDir\$($dbFile.Name)" `
            --output none 2>$null
        
        az storage file download `
            --account-name $StorageAccountName `
            --account-key $storageKey `
            --share-name $FileShareName `
            --path $existingFwlPath `
            --dest "$tempDir\$($fwlFile.Name)" `
            --output none 2>$null
        
        # Upload to backup location
        az storage file upload `
            --account-name $StorageAccountName `
            --account-key $storageKey `
            --share-name $FileShareName `
            --source "$tempDir\$($dbFile.Name)" `
            --path $backupDbPath `
            --output none
        
        az storage file upload `
            --account-name $StorageAccountName `
            --account-key $storageKey `
            --share-name $FileShareName `
            --source "$tempDir\$($fwlFile.Name)" `
            --path $backupFwlPath `
            --output none
        
        # Cleanup temp directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Host "  ✓ Backup created at: $backupDir" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️  Warning: Failed to create backup: $_" -ForegroundColor Yellow
        Write-Host "  Continuing with migration anyway..." -ForegroundColor Yellow
    }
    
    # Ask for confirmation
    $confirmation = Read-Host "`nDo you want to continue and overwrite the existing world? (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "Migration cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Create directory structure
Write-Host "`nCreating directory structure in file share..." -ForegroundColor Yellow
try {
    az storage directory create `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --name "worlds" `
        --output none 2>$null
    
    az storage directory create `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --name "worlds/$WorldName" `
        --output none 2>$null
    
    Write-Host "Directory structure created" -ForegroundColor Green
} catch {
    Write-Host "Warning: Directory creation failed (may already exist): $_" -ForegroundColor Yellow
}

# Validate world name matches (if file names contain world name)
$dbFileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($dbFile.Name)
$fwlFileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fwlFile.Name)

if ($dbFileNameWithoutExt -ne $WorldName -or $fwlFileNameWithoutExt -ne $WorldName) {
    Write-Host "`n⚠️  WARNING: World file names don't match WORLD_NAME='$WorldName'" -ForegroundColor Yellow
    Write-Host "  DB file: $($dbFile.Name) (expected: $WorldName.db)" -ForegroundColor Yellow
    Write-Host "  FWL file: $($fwlFile.Name) (expected: $WorldName.fwl)" -ForegroundColor Yellow
    Write-Host "`nThe container uses WORLD_NAME='$WorldName' by default." -ForegroundColor Yellow
    Write-Host "If your world has a different name, you need to either:" -ForegroundColor Yellow
    Write-Host "  1. Rename your files to match '$WorldName.db' and '$WorldName.fwl'" -ForegroundColor White
    Write-Host "  2. Or update the WORLD_NAME environment variable in the container" -ForegroundColor White
    
    $continue = Read-Host "`nContinue anyway? (yes/no)"
    if ($continue -ne "yes") {
        Write-Host "Migration cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Upload world files
Write-Host "`nUploading world files..." -ForegroundColor Yellow
try {
    # Upload with the correct world name (matching WORLD_NAME env var)
    $targetDbPath = "worlds/$WorldName/$WorldName.db"
    $targetFwlPath = "worlds/$WorldName/$WorldName.fwl"
    
    az storage file upload `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --source $dbFile.FullName `
        --path $targetDbPath `
        --output none
    
    Write-Host "  ✓ Uploaded $($dbFile.Name) → $targetDbPath" -ForegroundColor Green
    
    az storage file upload `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --share-name $FileShareName `
        --source $fwlFile.FullName `
        --path $targetFwlPath `
        --output none
    
    Write-Host "  ✓ Uploaded $($fwlFile.Name) → $targetFwlPath" -ForegroundColor Green
} catch {
    Write-Host "Error uploading files: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ Migration completed successfully!" -ForegroundColor Green
Write-Host "`n📋 Summary:" -ForegroundColor Cyan
Write-Host "  - World Name: $WorldName"
Write-Host "  - Storage Account: $StorageAccountName"
Write-Host "  - File Share: $FileShareName"
Write-Host "  - World Location: worlds/$WorldName/"
if ($existingDb -eq "true") {
    Write-Host "  - Backup Created: Yes (in backups/ directory)" -ForegroundColor Green
}

Write-Host "`n📝 Important Notes:" -ForegroundColor Yellow
Write-Host "  - The container uses WORLD_NAME='$WorldName' by default" -ForegroundColor White
Write-Host "  - If your world has a different name, update the container's WORLD_NAME environment variable" -ForegroundColor White
Write-Host "  - World saves are persistent - they survive container restarts and deletions" -ForegroundColor White
Write-Host "  - Automatic backups are created by the container (7-day retention)" -ForegroundColor White

Write-Host "`n🚀 Next steps:" -ForegroundColor Cyan
Write-Host "1. Start the server via Discord: /valheim start"
Write-Host "2. Wait 2-3 minutes for the server to start"
Write-Host "3. Connect to the server from Valheim"
Write-Host "4. Verify your world appears in the server list"
