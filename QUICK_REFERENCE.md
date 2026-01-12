# Quick Reference Guide

## Discord Commands

| Command | Description |
|---------|-------------|
| `/valheim start` | Start the Valheim server |
| `/valheim stop` | Stop the Valheim server |
| `/valheim status` | Check server status |

## Azure CLI Commands

### Check Server Status
```bash
az container show --resource-group valheim-server-rg --name valheim-server --query "instanceView.state" -o tsv
```

### Get Server IP Address
```bash
az container show --resource-group valheim-server-rg --name valheim-server --query "ipAddress.ip" -o tsv
```

### View Server Logs
```bash
az container logs --resource-group valheim-server-rg --name valheim-server --follow
```

### View Function App Logs
```bash
az functionapp log tail --resource-group valheim-server-rg --name <function-app-name>
```

### Check Costs
```bash
az consumption usage list --start-date $(date -d "1 month ago" +%Y-%m-%d) --end-date $(date +%Y-%m-%d)
```

## File Locations

### World Saves
- **Azure File Share**: `valheim-worlds/worlds/Dedicated/`
- **Local (Windows)**: `%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\worlds\`
- **Local (Linux)**: `~/.config/unity3d/IronGate/Valheim/worlds/`

### Container Configuration
- **Image**: `lloesche/valheim-server:latest`
- **Config Path**: `/config` (mounted from Azure File Share)
- **World Path**: `/config/worlds/Dedicated/`

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SERVER_NAME` | Valheim server name | "Valheim Server" |
| `WORLD_NAME` | World name | "Dedicated" |
| `SERVER_PASS` | Server password | (from Key Vault) |
| `AUTO_SHUTDOWN_MINUTES` | Auto-shutdown timeout | 120 |
| `BACKUPS_RETENTION_DAYS` | Backup retention | 7 |

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 2456 | UDP | Game server |
| 2457 | UDP | Query server |
| 2458 | UDP | Steam server |

## Common Tasks

### Update Server Password
```bash
az keyvault secret set --vault-name <key-vault-name> --name "ServerPassword" --value "new-password"
```

### Change Auto-Shutdown Timeout
```bash
az functionapp config appsettings set \
  --resource-group valheim-server-rg \
  --name <function-app-name> \
  --settings "AUTO_SHUTDOWN_MINUTES=180"
```

### Restart Function App
```bash
az functionapp restart --resource-group valheim-server-rg --name <function-app-name>
```

### Download World Save
```bash
az storage file download \
  --account-name <storage-account-name> \
  --account-key <key> \
  --share-name valheim-worlds \
  --path "worlds/Dedicated/Dedicated.db" \
  --dest "./Dedicated.db"
```

### Upload World Save
```bash
az storage file upload \
  --account-name <storage-account-name> \
  --account-key <key> \
  --share-name valheim-worlds \
  --source "./Dedicated.db" \
  --path "worlds/Dedicated/Dedicated.db"
```

## Troubleshooting Quick Fixes

### Server Won't Start
1. Check container group exists: `az container show --resource-group valheim-server-rg --name valheim-server`
2. Check Function App logs for errors
3. Verify Key Vault secrets are accessible

### Discord Bot Not Responding
1. Verify interaction endpoint URL in Discord Developer Portal
2. Check Function App is running: `az functionapp show --resource-group valheim-server-rg --name <function-app-name>`
3. Test endpoint: `curl https://<function-app-name>.azurewebsites.net/api/DiscordBot`

### Can't Connect to Server
1. Get server IP: `az container show --resource-group valheim-server-rg --name valheim-server --query "ipAddress.ip" -o tsv`
2. Verify ports 2456-2458 UDP are open
3. Check server is running: `/valheim status` in Discord

### High Costs
1. Verify server is stopped when not in use
2. Check auto-shutdown is working
3. Review Azure Cost Management dashboard
4. Set up budget alerts

## Useful Links

- [Valheim Dedicated Server Guide](https://valheim.fandom.com/wiki/Dedicated_servers)
- [Azure Container Instances Pricing](https://azure.microsoft.com/pricing/details/container-instances/)
- [Discord Developer Portal](https://discord.com/developers/applications)
- [Azure Functions Documentation](https://docs.microsoft.com/azure/azure-functions/)
