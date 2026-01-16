# Persistent Valheim Server on Azure

A cost-effective, Discord-controlled Valheim dedicated server hosted on Azure.

## Architecture Overview

This solution uses:
- **Azure Container Instances (ACI)** - Runs the Valheim server on-demand (only pay when running)
- **Azure File Share** - Persistent storage for world saves
- **Azure Functions** - Discord bot integration and auto-shutdown logic
- **Azure Key Vault** - Secure storage for secrets (Discord token, server password)

### Cost Optimization Strategy

- Server only runs when needed (started via Discord)
- Automatic shutdown after configurable timeout (default: 2 hours)
- Uses Azure Container Instances (pay-per-second billing)
- Burstable compute tier for cost efficiency
- Estimated cost: ~$0.10-0.15/hour when running

## Features

[OK] Discord channel control (start/stop server)  
[OK] Automatic shutdown after inactivity  
[OK] Persistent world saves  
[OK] Save migration support  
[OK] Infrastructure as Code (Bicep)  
[OK] Cost-optimized for 5 players  

## Prerequisites

- Azure subscription
- Azure CLI installed and logged in
- .NET 10.0 SDK installed
- **Azure Functions Core Tools** (installed automatically by deploy script, or manually: `npm install -g azure-functions-core-tools@4`)
- Node.js (required for Azure Functions Core Tools installation)
- Discord bot token and public key (create at https://discord.com/developers/applications)
- PowerShell execution policy configured:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

## Quick Start

### 1. Create Discord Bot

1. Go to https://discord.com/developers/applications
2. Create a new application
3. Go to **Bot** section → Click **Add Bot** → Copy the **Bot Token**
4. Go to **General Information** → Copy the **Public Key** (64-character hex string)
5. Go to **OAuth2 → URL Generator**:
   - Select scopes: `bot`, `applications.commands`
   - Select permissions: Send Messages, Use Slash Commands
   - Copy the URL and open it to invite the bot to your server

### 2. Deploy Infrastructure

Run the deployment script with your values:

```powershell
.\scripts\deploy.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -Location "eastus" `
  -DiscordBotToken "YOUR_DISCORD_BOT_TOKEN_HERE" `
  -DiscordPublicKey "YOUR_64_CHARACTER_HEX_PUBLIC_KEY_HERE" `
  -ServerPassword "YOUR_SERVER_PASSWORD_HERE" `
  -ServerName "My Valheim Server" `
  -AutoShutdownMinutes 120 `
  -MonthlyBudgetLimit 30.0 `
  -BudgetAlertEmail "your-email@example.com"
```

**Example with placeholder values:**

```powershell
.\scripts\deploy.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -Location "eastus" `
  -DiscordBotToken "MTQ2MDM2NTA0NTEzMjMwMDMwOA.GE1tcd.example_token_here" `
  -DiscordPublicKey "9220348032faaf2e50d7a71af23f69a80492b966a6e363e7ccbb12a81880cf0c" `
  -ServerPassword "YourSecurePassword123" `
  -ServerName "My Valheim Server" `
  -AutoShutdownMinutes 120 `
  -MonthlyBudgetLimit 30.0 `
  -BudgetAlertEmail "your-email@example.com"
```

**Note:** Replace all placeholder values with your actual:
- Discord Bot Token (from Discord Developer Portal → Bot section)
- Discord Public Key (64-character hex string from General Information)
- Server Password (your Valheim server password)
- Email address for budget alerts (optional but recommended)

The script will:
- Deploy all Azure infrastructure (Storage, Key Vault, Function App) via Bicep
- Configure Function App settings, including Key Vault references for secrets
- Set up managed identity and role assignments
- Build, test, and deploy the Function App code

### 3. Configure Discord Interactions Endpoint

After deployment, set the interactions endpoint in Discord:

1. Go to https://discord.com/developers/applications → Your Application → **Interactions**
2. Set **Interaction Endpoint URL** to the Function App URL shown at the end of deployment (format: `https://<function-app-name>.azurewebsites.net/api/DiscordBot`)
   - The exact Function App name will be displayed in the deployment output
   - Example: `https://valheim-func-abc123.azurewebsites.net/api/DiscordBot`
3. Register slash commands using the JSON shown at the end of deployment

### 4. Migrate World Save (Optional)

If you have an existing world save, use the migration script:

```powershell
.\scripts\migrate-save.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -StorageAccountName "valheimsa" `
  -FileShareName "valheim-worlds" `
  -WorldName "Dedicated" `
  -WorldDbPath "C:\path\to\world.db" `
  -WorldFwlPath "C:\path\to\world.fwl"
```

### 5. Usage

In your Discord channel:
- `/valheim start` - Start the server
- `/valheim stop` - Stop the server
- `/valheim status` - Check server status

The server will automatically shut down after the configured timeout (default: 2 hours).

## Project Structure

```
.
├── infrastructure/          # Bicep IaC templates
│   └── main.bicep         # Main deployment template
├── functions/              # Azure Functions
│   ├── DiscordBot/        # Discord command handler
│   ├── AutoShutdown/     # Timer-triggered shutdown
│   └── ValheimServerFunctions.Tests/  # Unit tests
└── scripts/               # Deployment scripts
    ├── deploy.ps1         # Main deployment script
    └── migrate-save.ps1   # World save migration utility
```

## Architecture

- **Azure Container Instances (ACI)**: Runs Valheim server on-demand
- **Azure File Share**: Persistent storage for world saves
- **Azure Functions (Flex Consumption)**: Discord bot and auto-shutdown logic (.NET 10.0 isolated)
- **Azure Key Vault**: Secure storage for secrets (accessed via Key Vault references in app settings)
- **Managed Identity**: System-assigned identity for secure resource access
- **Application Insights**: Monitoring and logging

## Cost Estimates

- **Running**: ~$0.10-0.15/hour (ACI + Storage)
- **Stopped**: ~$0.01/day (Storage only)
- **Monthly (10 hours/week)**: ~$4-6/month
- **Budget & Alerts**: **FREE** (no additional cost)

### Budget Alerts

The deployment includes budget monitoring with alerts at:
- **50%** of budget ($15) - Early warning
- **75%** of budget ($22.50) - Approaching limit
- **90%** of budget ($27) - Critical warning
- **100%** of budget ($30) - Budget exceeded
- **80% forecasted** - Predictive alert based on spending trends

Alerts are sent via email (if `-BudgetAlertEmail` is provided during deployment).

## References

- [Valheim Dedicated Server Guide](https://valheim.fandom.com/wiki/Dedicated_servers)
- [Docker Image: lloesche/valheim-server](https://hub.docker.com/r/lloesche/valheim-server)
- [Azure Functions Flex Consumption](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-how-to)
