# Persistent Valheim Server on Azure

A cost-effective, Discord-controlled Valheim dedicated server hosted on Azure.

## Architecture Overview

This solution uses:
- **Azure Container Instances (ACI)** - Runs the Valheim server on-demand (only pay when running)
- **Azure Container Registry (ACR)** - Hosts the Valheim Docker image (avoids Docker Hub rate limits)
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

#### Code-Only Deployment

For faster iterations during development, you can deploy only the Function App code without redeploying infrastructure:

```powershell
.\scripts\deploy.ps1 `
  -CodeOnly `
  -FunctionAppName "valheim-func" `
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

**Note:** When using `-CodeOnly`:
- The `-FunctionAppName` parameter is required
- Infrastructure deployment is skipped (faster for code changes)
- All other parameters are still required (they're validated but not used)
- To find your Function App name: `az functionapp list --resource-group "valheim-server-rg" --query '[0].name' -o tsv`

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

### 6. Connecting to the Server

Once the server is started, the Discord bot will send you the connection information:

**Connection Details:**
- **IP Address**: The public IP address (e.g., `20.123.45.67`)
- **FQDN**: The fully qualified domain name (e.g., `valheim-1a2b3c4d.eastus.azurecontainer.io`)

**To Connect in Valheim:**

1. **Using the Server Browser (Recommended):**
   - Open Valheim
   - Click "Join Game"
   - Click "Join IP"
   - Enter the connection string in format: `IP_ADDRESS:2456`
     - Example: `20.123.45.67:2456`
     - **Important:** You MUST include the port `:2456` in the IP field
   - Enter the server password (configured during deployment)
   - Click "Connect"

2. **Using Console Command:**
   - In Valheim, press `F5` to open the console
   - Type: `connect <IP_ADDRESS>:2456`
   - Example: `connect 20.123.45.67:2456`
   - Enter the password when prompted

**Important Notes:**
- **Port Format:** Always use `IP:2456` format (e.g., `20.123.45.67:2456`)
- **FQDN:** Valheim typically doesn't accept FQDN/domain names - use the IP address only
- **Wait Time:** The server may take 3-5 minutes to fully initialize after container starts
- If connection fails, wait 1-2 more minutes and try again

**Server Ports:**
- Primary port: `2456` (UDP) - **Use this for connections**
- Additional ports: `2457`, `2458` (UDP) - used automatically by game

**Troubleshooting Connection Issues:**

If you get "Failed to connect":
1. **Wait longer:** Server may need 3-5 minutes to fully initialize
2. **Check format:** Ensure you're using `IP:2456` format (not just IP)
3. **Verify server status:** Run `/valheim status` in Discord to confirm server is running
4. **Check container logs:** In Azure Portal → Container Instance → Logs to see if server started properly
5. **Try console command:** Use `F5` console with `connect IP:2456` instead of Join IP button

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
- **Azure Container Registry (ACR)**: Hosts Valheim Docker image (Basic tier, ~$5/month)
- **Azure File Share**: Persistent storage for world saves
- **Azure Functions (Flex Consumption)**: Discord bot and auto-shutdown logic (.NET 10.0 isolated)
- **Azure Key Vault**: Secure storage for secrets (accessed via Key Vault references in app settings)
- **Managed Identity**: System-assigned identity for secure resource access
- **Application Insights**: Monitoring and logging

## Cost Estimates

- **Running**: ~$0.10-0.15/hour (ACI + Storage)
- **Stopped**: ~$0.01/day (Storage only)
- **Azure Container Registry**: ~$5/month (Basic tier, avoids Docker Hub rate limits)
- **Monthly (10 hours/week)**: ~$9-11/month (including ACR)
- **Budget & Alerts**: **FREE** (no additional cost)

### Why Azure Container Registry?

Docker Hub has rate limits for anonymous image pulls (100 per 6 hours). Azure Container Instances share IP ranges, so you can hit these limits even with infrequent use, causing server start failures. ACR provides:
- No rate limits within Azure network
- Faster container startup (same datacenter)
- Reliable image pulls every time

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
