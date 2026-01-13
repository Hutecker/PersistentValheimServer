# Deployment Status & Next Steps

## Current Issue

Your Azure subscription doesn't have quota for Function Apps. You need to request quota before deployment can succeed.

## Immediate Action Required

### Request Quota Increase

**Option 1: Via Azure Portal (Easiest)**

1. Go to: https://portal.azure.com
2. Navigate to: **Subscriptions** → **Samosaverse Valheim Server** → **Usage + quotas**
3. Search for: "App Service" or "Function Apps"
4. Find: **"App Service - Dynamic"** quota
5. Click: **"Request increase"**
6. Fill out:
   - **Region**: eastus
   - **New limit**: 10
   - **Reason**: "Function Apps for Valheim server Discord bot"
7. Submit

**Option 2: Via Support Ticket**

```powershell
# This will open Azure Portal to create support ticket
Start-Process "https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade/newsupportrequest"
```

Select:
- **Issue type**: Service and subscription limits (quotas)
- **Quota type**: Compute-VM (cores-v3) - App Service Plans
- **Region**: eastus

## Timeline

- **Quota approval**: Usually 24-48 hours
- **No cost**: Quota increases are free
- **Email notification**: You'll receive email when approved

## After Quota is Approved

1. Re-run the deployment:
   ```powershell
   .\scripts\deploy.ps1 `
     -ResourceGroupName "valheim-server-rg" `
     -Location "eastus" `
     -DiscordBotToken "MTQ2MDM2NTA0NTEzMjMwMDMwOA.GY_7jj.6v_EhJj3yJyNBmN9z5jsC_TcN7o7QbT0UHYQmo" `
     -ServerPassword "00000" `
     -ServerName "My Valheim Server" `
     -AutoShutdownMinutes 120
   ```

2. The deployment should complete successfully

## What's Already Done

✅ Resource group created: `valheim-server-rg`  
✅ All code is ready  
✅ Bicep templates are fixed  
⏳ Waiting for quota approval

## Check Quota Status

```powershell
az vm list-usage --location eastus --query "[?contains(name.value, 'App Service')]" -o table
```

## Alternative: Use Different Region

If eastus has quota issues, you can try a different region:

```powershell
.\scripts\deploy.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -Location "westus2" `  # Try different region
  -DiscordBotToken "..." `
  -ServerPassword "..." `
  -ServerName "My Valheim Server" `
  -AutoShutdownMinutes 120
```
