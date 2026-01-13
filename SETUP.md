# Setup Guide

Complete step-by-step guide to deploy your Valheim server on Azure.

## Prerequisites

1. **Azure Account** with an active subscription
2. **Azure CLI** installed ([Download](https://aka.ms/installazurecliwindows))
3. **.NET 8.0 SDK** installed ([Download](https://dotnet.microsoft.com/download))
4. **Azure Functions Core Tools** ([Download](https://docs.microsoft.com/azure/azure-functions/functions-run-local))
5. **Discord Account** and access to create a bot
6. **PowerShell Execution Policy** configured (see below)

### Configure PowerShell Execution Policy

Before running the deployment script, you need to allow PowerShell to run local scripts:

```powershell
# Recommended: Allow local scripts for your user account only
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Alternative:** If you prefer not to change the policy, you can bypass it for a single execution:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 -ResourceGroupName "valheim-server-rg" ...
```

For more details, see [DEPLOYMENT_TROUBLESHOOTING.md](DEPLOYMENT_TROUBLESHOOTING.md).

## Step 1: Create Discord Bot

1. Go to https://discord.com/developers/applications
2. Click **"New Application"**
3. Name it (e.g., "Valheim Server Bot")
4. Go to **"Bot"** section
5. Click **"Add Bot"**
6. Copy the **Bot Token** (you'll need this for deployment)
7. Under **"Privileged Gateway Intents"**, enable:
   - ✅ Server Members Intent (if needed)
8. Go to **"General Information"** section
9. Copy the **Public Key** (you'll need this for deployment - it's a 64-character hex string)
10. Go to **"OAuth2" → "URL Generator"**
11. Select scopes:
    - ✅ `bot`
    - ✅ `applications.commands`
12. Select permissions:
    - ✅ Send Messages
    - ✅ Use Slash Commands
13. Copy the generated URL and open it in a browser
14. Select your Discord server and authorize

## Step 2: Login to Azure

```powershell
az login
az account list  # View available subscriptions
az account set --subscription "<subscription-id>"  # Set active subscription
```

## Step 3: Deploy Infrastructure

### Option A: Using PowerShell Script (Recommended)

```powershell
.\scripts\deploy.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -Location "eastus" `
  -DiscordBotToken "YOUR_DISCORD_BOT_TOKEN" `
  -DiscordPublicKey "YOUR_DISCORD_PUBLIC_KEY" `
  -ServerPassword "YOUR_SERVER_PASSWORD" `
  -ServerName "My Valheim Server" `
  -AutoShutdownMinutes 120
```

**Note:** The Discord Public Key is required and is automatically stored in Key Vault during deployment. Get it from Discord Developer Portal → Your Application → General Information → Public Key.

### Option B: Manual Deployment

```powershell
# Set variables
$RESOURCE_GROUP = "valheim-server-rg"
$LOCATION = "eastus"
$DISCORD_TOKEN = "YOUR_DISCORD_BOT_TOKEN"
$DISCORD_PUBLIC_KEY = "YOUR_DISCORD_PUBLIC_KEY"
$SERVER_PASSWORD = "YOUR_SERVER_PASSWORD"
$SERVER_NAME = "My Valheim Server"

# Deploy infrastructure
cd infrastructure
az deployment sub create `
  --location $LOCATION `
  --template-file main.bicep `
  --parameters resourceGroupName=$RESOURCE_GROUP `
               location=$LOCATION `
               discordBotToken=$DISCORD_TOKEN `
               discordPublicKey=$DISCORD_PUBLIC_KEY `
               serverPassword=$SERVER_PASSWORD `
               serverName=$SERVER_NAME `
               autoShutdownMinutes=120

# Get outputs
$outputs = az deployment sub show --name "valheim-deployment-*" --query "properties.outputs" | ConvertFrom-Json
$FUNCTION_APP_NAME = $outputs.functionAppName.value
$FUNCTION_APP_URL = $outputs.functionAppUrl.value
```

## Step 4: Deploy Function App Code

```powershell
cd functions

# Restore NuGet packages
dotnet restore

# Build the project
dotnet build --configuration Release

# Deploy to Azure
func azure functionapp publish $FUNCTION_APP_NAME --dotnet-isolated
```

## Step 5: Register Discord Commands

```powershell
# Get your Application ID from Discord Developer Portal
$APPLICATION_ID = "YOUR_APPLICATION_ID"
$BOT_TOKEN = "YOUR_DISCORD_BOT_TOKEN"

.\scripts\register-discord-commands.ps1 `
  -ApplicationId $APPLICATION_ID `
  -BotToken $BOT_TOKEN
```

## Step 6: Configure Discord Interaction Endpoint

1. Go to https://discord.com/developers/applications
2. Select your application
3. Go to **"General Information"**
4. Scroll to **"Interactions Endpoint URL"**
5. Enter: `https://<your-function-app-name>.azurewebsites.net/api/DiscordBot`
6. Click **"Save Changes"**

## Step 7: Test the Setup

1. Open Discord
2. In your server, type `/valheim status`
3. You should see: "🔴 Server is **STOPPED**"
4. Type `/valheim start`
5. Wait 2-3 minutes for the server to start
6. Check status again: `/valheim status`

## Step 8: Connect to Server

1. After server starts, get the server IP:
   ```powershell
   az container show `
     --resource-group valheim-server-rg `
     --name valheim-server `
     --query "ipAddress.ip" -o tsv
   ```

2. In Valheim game:
   - Go to **"Join Game"**
   - Click **"Join IP"**
   - Enter the IP address
   - Enter your server password

## Step 9: Migrate Existing World (Optional)

If you have an existing Valheim world save:

```powershell
.\scripts\migrate-save.ps1 `
  -StorageAccountName "<storage-account-name>" `
  -ResourceGroupName "valheim-server-rg" `
  -WorldSavePath "C:\Users\YourName\AppData\LocalLow\IronGate\Valheim\worlds" `
  -WorldName "Dedicated"
```

## Verification Checklist

- [ ] Infrastructure deployed successfully
- [ ] Function App code deployed
- [ ] Discord commands registered
- [ ] Interaction endpoint configured
- [ ] Bot responds to `/valheim status`
- [ ] Server starts with `/valheim start`
- [ ] Server stops with `/valheim stop`
- [ ] Auto-shutdown works (wait for timeout)
- [ ] Can connect from Valheim game client
- [ ] World saves persist after restart

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues.

## Cost Monitoring

Set up Azure Budget alerts:

```powershell
az consumption budget create `
  --budget-name "valheim-monthly" `
  --amount 10 `
  --time-grain Monthly `
  --start-date $(Get-Date -Format "yyyy-MM-dd") `
  --end-date $(Get-Date -AddYears 1 -Format "yyyy-MM-dd") `
  --resource-group valheim-server-rg
```

## Next Steps

- Configure backup retention (default: 7 days)
- Set up monitoring alerts
- Customize auto-shutdown timeout
- Add more Discord commands (e.g., `/valheim players`)
