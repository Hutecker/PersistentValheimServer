# Troubleshooting Guide

Common issues and solutions for the Valheim Azure server.

## Server Won't Start

### Issue: Container group not found
**Solution**: The container group needs to be created first. The Discord bot should handle this, but if it fails:
1. Check Azure Portal → Container Instances
2. Manually create the container group using the Bicep template
3. Verify storage account and file share exist

### Issue: Permission errors
**Solution**: 
1. Verify Function App has managed identity enabled
2. Check Key Vault access policies include the Function App
3. Verify Container Instance Contributor role is assigned

### Issue: Storage mount failures
**Solution**:
1. Verify file share exists and is accessible
2. Check storage account key is correct
3. Ensure file share has sufficient quota

## Discord Bot Not Responding

### Issue: Commands not working
**Solution**:
1. Verify Discord bot token is correct in Key Vault
2. Check interaction endpoint URL is set correctly in Discord Developer Portal
3. Verify Function App is running and accessible
4. Check Application Insights for errors

### Issue: 401 Unauthorized
**Solution**:
1. Verify Discord bot token hasn't expired
2. Check bot has proper permissions in Discord server
3. Verify interaction endpoint URL matches Function App URL

## Auto-Shutdown Not Working

### Issue: Server doesn't shut down automatically
**Solution**:
1. Check AutoShutdown function is enabled
2. Verify timer trigger schedule is correct
3. Check Application Insights for function execution logs
4. Verify `AUTO_SHUTDOWN_MINUTES` environment variable is set

### Issue: Server shuts down too early
**Solution**:
1. Adjust `AUTO_SHUTDOWN_MINUTES` in Function App settings
2. Verify timezone settings (functions use UTC)

## World Save Issues

### Issue: World not loading
**Solution**:
1. Verify world files are in correct directory structure
2. Check file names match exactly (case-sensitive)
3. Ensure both `.db` and `.fwl` files are present
4. Check container logs for errors

### Issue: World saves not persisting
**Solution**:
1. Verify Azure File Share is mounted correctly
2. Check file share has write permissions
3. Verify storage account is accessible
4. Check container logs for mount errors

## Cost Issues

### Issue: Unexpected charges
**Solution**:
1. Check Container Instances are actually stopped when not in use
2. Verify auto-shutdown is working
3. Review Azure Cost Management for breakdown
4. Consider using Azure Budget alerts

### Issue: Server running 24/7
**Solution**:
1. Verify auto-shutdown function is enabled
2. Check if someone keeps restarting the server
3. Review Discord bot logs for start commands
4. Consider reducing auto-shutdown timeout

## Performance Issues

### Issue: Server lag or disconnections
**Solution**:
1. Increase container CPU/memory in Bicep template
2. Check network latency to Azure region
3. Verify sufficient resources allocated
4. Monitor Application Insights for resource usage

### Issue: Slow startup
**Solution**:
1. This is normal - ACI takes 1-3 minutes to start
2. Consider using a VM instead for faster startup (higher cost)
3. Pre-warm container during peak hours

## Network Issues

### Issue: Can't connect to server
**Solution**:
1. Verify container group has public IP
2. Check firewall rules (ports 2456-2458 UDP)
3. Verify DNS name is resolving
4. Check Valheim server is actually running in container

### Issue: Port conflicts
**Solution**:
1. Verify ports 2456-2458 UDP are available
2. Check no other services using these ports
3. Consider changing ports in container configuration

## Getting Help

1. **Check Logs**: Application Insights → Logs
2. **Container Logs**: Azure Portal → Container Instances → Logs
3. **Function Logs**: Azure Portal → Function App → Functions → Monitor
4. **Azure Status**: https://status.azure.com/

## Common Commands

```bash
# Check container status
az container show --resource-group <rg> --name valheim-server

# View container logs
az container logs --resource-group <rg> --name valheim-server

# Restart Function App
az functionapp restart --resource-group <rg> --name <function-app-name>

# Check Function App logs
az functionapp log tail --resource-group <rg> --name <function-app-name>
```
