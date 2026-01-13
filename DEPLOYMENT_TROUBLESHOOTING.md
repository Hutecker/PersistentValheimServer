# Deployment Troubleshooting

## PowerShell Execution Policy Error

If you see an error like:
```
cannot be loaded. The file ... is not digitally signed. You cannot run this script on the current system.
```

This is due to Windows PowerShell's execution policy preventing unsigned scripts from running.

### Solution Options

#### Option 1: Bypass for Current Session (Recommended for Testing)

Run this command in PowerShell **before** running the deploy script:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

This only affects the current PowerShell session and doesn't change system-wide settings.

#### Option 2: Bypass for Current User (Recommended for Development)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

This allows you to run local scripts without signing, but still requires remote scripts to be signed.

#### Option 3: Run Script Directly with Bypass

You can bypass the execution policy for a single script execution:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 -ResourceGroupName "valheim-server-rg" -Location "eastus" -DiscordBotToken "your-token" -ServerPassword "your-password"
```

#### Option 4: Check Current Policy

To see your current execution policy:

```powershell
Get-ExecutionPolicy -List
```

### Understanding Execution Policies

- **Restricted**: No scripts can run (default on some systems)
- **RemoteSigned**: Local scripts can run, remote scripts must be signed
- **Bypass**: All scripts can run (not recommended for production)
- **Unrestricted**: All scripts can run with warnings (not recommended)

### Recommended Approach

For development, use **Option 2** (`RemoteSigned` for `CurrentUser`). This:
- ✅ Allows you to run local scripts
- ✅ Only affects your user account
- ✅ Doesn't require administrator privileges
- ✅ Still provides security for remote scripts

### Alternative: Use Azure Cloud Shell

If you prefer not to change execution policy, you can use Azure Cloud Shell which doesn't have these restrictions:

1. Go to https://shell.azure.com
2. Upload your project files
3. Run the deployment commands directly

## Other Common Issues

### Missing Azure CLI

If you get an error about `az` command not found:

1. Install Azure CLI: https://aka.ms/installazurecliwindows
2. Restart PowerShell after installation
3. Run `az login` to authenticate

### Missing .NET SDK

If you get an error about `dotnet` command not found:

1. Install .NET 8.0 SDK: https://dotnet.microsoft.com/download
2. Restart PowerShell after installation
3. Verify with `dotnet --version`

### Missing Azure Functions Core Tools

If you get an error about `func` command not found:

1. Install Azure Functions Core Tools: https://docs.microsoft.com/azure/azure-functions/functions-run-local
2. Restart PowerShell after installation
3. Verify with `func --version`
