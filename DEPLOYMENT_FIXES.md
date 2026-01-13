# Deployment Fixes Applied

## Issues Fixed

### 1. Bicep Template Errors

**Fixed:**
- Changed `float` type to `int` for `containerCpu` and `containerMemory` parameters (Bicep doesn't support float)
- Fixed file share parent reference - now properly references the file service resource
- Fixed role assignment names - changed from using `functionApp.id` to `functionApp.name` in guid() calls (Bicep requires compile-time constants for role assignment names)

### 2. NuGet Package Version

**Fixed:**
- Changed `Azure.ResourceManager.Resources` from version `3.1.1` (doesn't exist) to `1.11.2` (latest available)

### 3. Azure Functions Core Tools

**Issue:** The `func` command is not found, which means Azure Functions Core Tools is not installed or not in PATH.

**Solution:**
1. Install Azure Functions Core Tools v4:
   ```powershell
   winget install Microsoft.AzureFunctionsCoreTools
   ```
   
   Or download from: https://github.com/Azure/azure-functions-core-tools/releases

2. After installation, restart PowerShell and verify:
   ```powershell
   func --version
   ```

## Next Steps

1. **Install Azure Functions Core Tools** (see above)

2. **Re-run deployment:**
   ```powershell
   .\deploy.ps1 -ServerPassword "00000"
   ```

3. **If you still get errors**, check:
   - Azure CLI is logged in: `az account show`
   - .NET SDK is installed: `dotnet --version`
   - All prerequisites are met (see SETUP.md)

## Alternative: Deploy Function App Manually

If you can't install Azure Functions Core Tools right now, you can:

1. Deploy the infrastructure first (Bicep template)
2. Build the function app locally: `dotnet build --configuration Release`
3. Deploy via Azure Portal or VS Code Azure Functions extension
