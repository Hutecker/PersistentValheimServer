# Migrating Valheim World Saves

This guide explains how to migrate an existing Valheim world save to the Azure-hosted server.

## Prerequisites

- Access to your existing Valheim server's world save files
- Azure Storage Explorer or Azure CLI installed
- Access to the Azure File Share (via Storage Account)

## World Save Location

Valheim world saves are typically located at:
- **Windows**: `%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\worlds\`
- **Linux**: `~/.config/unity3d/IronGate/Valheim/worlds/`

The save consists of two files:
- `worldname.db` - World data
- `worldname.fwl` - World metadata

## Migration Steps

### Option 1: Using Azure Storage Explorer

1. **Download Azure Storage Explorer**
   - Install from: https://azure.microsoft.com/features/storage-explorer/

2. **Connect to Storage Account**
   - Open Azure Storage Explorer
   - Sign in with your Azure account
   - Navigate to your Storage Account → File Shares → `valheim-worlds`

3. **Upload World Files**
   - Create a folder for your world (e.g., `Dedicated`)
   - Upload both `.db` and `.fwl` files to this folder
   - Ensure the folder structure matches: `worlds/Dedicated/`

### Option 2: Using Azure CLI

```bash
# Set variables
STORAGE_ACCOUNT_NAME="your-storage-account-name"
RESOURCE_GROUP="valheim-server-rg"
FILE_SHARE_NAME="valheim-worlds"
WORLD_NAME="Dedicated"  # Or your world name

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query "[0].value" -o tsv)

# Create directory structure
az storage directory create \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key $STORAGE_KEY \
  --share-name $FILE_SHARE_NAME \
  --name "worlds"

az storage directory create \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key $STORAGE_KEY \
  --share-name $FILE_SHARE_NAME \
  --name "worlds/$WORLD_NAME"

# Upload world files
az storage file upload \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key $STORAGE_KEY \
  --share-name $FILE_SHARE_NAME \
  --source "path/to/your/worldname.db" \
  --path "worlds/$WORLD_NAME/worldname.db"

az storage file upload \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key $STORAGE_KEY \
  --share-name $FILE_SHARE_NAME \
  --source "path/to/your/worldname.fwl" \
  --path "worlds/$WORLD_NAME/worldname.fwl"
```

### Option 3: Using PowerShell Script

See `migrate-save.ps1` for an automated migration script.

## Verifying Migration

1. Start the server via Discord: `/valheim start`
2. Wait for the server to fully start (2-3 minutes)
3. Check the server logs in Azure Portal → Container Instances
4. Connect to the server from Valheim game client
5. Verify your world appears in the server list

## Important Notes

- **World Name**: The container uses `WORLD_NAME=Dedicated` by default. If your world has a different name, update the container environment variable or rename your world files.
- **Backups**: The container automatically creates backups. Check the `/config/backups` directory in the file share.
- **File Permissions**: Ensure the container has read/write access to the file share (handled automatically by Azure).

## Troubleshooting

### World Not Appearing
- Verify files are in the correct directory structure
- Check file names match exactly (case-sensitive on Linux)
- Ensure both `.db` and `.fwl` files are present

### Permission Errors
- Verify the container has proper access to the file share
- Check storage account firewall rules (if enabled)

### Server Won't Start
- Check container logs in Azure Portal
- Verify world files are not corrupted
- Ensure sufficient storage quota in file share
