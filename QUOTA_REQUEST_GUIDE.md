# Azure Quota Request Guide

## Problem

Your Azure subscription doesn't have quota for Function Apps. You need to request quota for:
- **Dynamic VMs** (for Consumption plan - recommended, free tier)
- OR **Basic VMs** (for Basic plan - works but costs ~$13/month)

## Solution: Request Quota Increase

### Step 1: Request Quota via Azure Portal

1. **Go to Azure Portal**: https://portal.azure.com
2. **Navigate to**: Subscriptions → Your Subscription → **Usage + quotas**
3. **Search for**: "App Service" or "Function Apps"
4. **Find**: "App Service - Dynamic" or "App Service - Basic"
5. **Click**: "Request increase"
6. **Fill out form**:
   - **Compute Tier**: Select **Y** (this is Consumption plan / Dynamic)
   - **Region**: eastus
   - **New limit**: 10 (or more)
   - **Reason**: "Need quota for Function Apps to host Discord bot for Valheim server"
7. **Submit** (usually approved in 24-48 hours)

**Important**: When the form asks for "Compute Tier", select **Y**. This corresponds to:
- Consumption plan (Y1)
- Dynamic VMs
- Pay-per-execution pricing

### Step 2: Alternative - Request via Support Ticket

```powershell
# Open Azure Portal to create support ticket
Start-Process "https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade/newsupportrequest"
```

**Ticket Details:**
- **Issue type**: Service and subscription limits (quotas)
- **Subscription**: Your subscription
- **Quota type**: Compute-VM (cores-v3) - App Service Plans
- **Region**: eastus
- **Description**: "Request quota increase for Function Apps. Need at least 10 Dynamic VMs for Consumption plan Function Apps."

### Step 3: Wait for Approval

- Usually approved within 24-48 hours
- You'll receive an email when approved
- No cost for quota increases

### Step 4: Re-run Deployment

Once quota is approved, run the deployment again:

```powershell
.\scripts\deploy.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -Location "eastus" `
  -DiscordBotToken "YOUR_TOKEN" `
  -ServerPassword "YOUR_PASSWORD" `
  -ServerName "My Valheim Server" `
  -AutoShutdownMinutes 120
```

## Quick Links

- **Portal - Usage + Quotas**: https://portal.azure.com/#blade/Microsoft_Azure_Billing/SubscriptionsBlade
- **Support Ticket**: https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade/newsupportrequest

## Check Current Quota

```powershell
az vm list-usage --location eastus --query "[?contains(name.value, 'App Service') || contains(name.value, 'Function')]" -o table
```

## Notes

- **Consumption Plan (Y1/Dynamic)**: Recommended - pay per execution (~$0.20/month)
- **Basic Plan (B1/Basic)**: Works immediately but costs ~$13/month
- Quota increases are **free** and usually approved quickly
- You can request both Dynamic and Basic quota to have options
