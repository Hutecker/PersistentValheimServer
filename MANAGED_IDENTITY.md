# Managed Identity Configuration

This document describes how managed identities are used throughout the Valheim server infrastructure.

## Overview

All Azure resources use managed identities where possible to eliminate the need for storing and managing credentials. This improves security and simplifies credential management.

## Resources Using Managed Identity

### 1. Function App (System-Assigned Managed Identity)

The Azure Function App uses a **system-assigned managed identity** that is automatically created and managed by Azure.

**Uses:**
- ✅ Accessing Key Vault secrets (via RBAC)
- ✅ Accessing Storage Account (for retrieving keys and file operations)
- ✅ Managing Container Instances (create/delete operations)
- ✅ Function App storage (using `__accountName` pattern)

**RBAC Role Assignments:**
- `Key Vault Secrets User` - Read secrets from Key Vault
- `Storage Account Contributor` - Manage storage account and retrieve keys
- `Storage Blob Data Contributor` - Access Function App storage
- `Storage File Data SMB Share Elevated Contributor` - Access Azure Files (for future use)
- `Container Instance Contributor` - Create and manage container instances

### 2. Key Vault (RBAC Authorization)

Key Vault uses **RBAC (Role-Based Access Control)** instead of access policies for modern, identity-based access.

**Configuration:**
- `enableRbacAuthorization: true` - Enables RBAC mode
- Function App's managed identity is granted `Key Vault Secrets User` role

**Benefits:**
- Centralized access control through Azure RBAC
- Better audit trail
- Easier to manage permissions

### 3. Storage Accounts

#### Function App Storage
The Function App uses managed identity to access its storage account via the `__accountName` pattern:

```bicep
AzureWebJobsStorage__accountName: functionStorageAccount.name
WEBSITE_CONTENTAZUREFILECONNECTIONSTRING__accountName: functionStorageAccount.name
```

This tells Azure Functions to use the Function App's managed identity instead of connection strings with keys.

#### World Save Storage
The storage account for world saves has Azure AD authentication enabled:

```bicep
azureFilesIdentityBasedAuthentication: {
  directoryServiceOptions: 'AADKERB'
}
```

**Note:** Container Instances currently don't support managed identity for Azure Files mounts, so storage keys are still required. However:
- Keys are retrieved using managed identity (not hardcoded)
- Keys are only used temporarily during container group creation
- The Function App has proper RBAC permissions to retrieve keys securely

### 4. Container Instances

**Current Limitation:**
Azure Container Instances do not support managed identity for Azure Files volume mounts. Storage account keys are still required.

**Workaround:**
- Storage keys are retrieved using the Function App's managed identity
- Keys are only used during container group creation
- Keys are stored securely in the container group resource (not exposed in code)

**Future:**
When Azure Container Instances adds support for managed identity with Azure Files, we can migrate to identity-based authentication.

## Security Benefits

### ✅ No Hardcoded Credentials
- No connection strings with keys in code
- No secrets in environment variables
- All authentication via managed identity

### ✅ Automatic Credential Rotation
- Managed identities are automatically rotated by Azure
- No manual credential management required

### ✅ Principle of Least Privilege
- Each resource has only the minimum permissions needed
- RBAC roles are scoped to specific resources

### ✅ Audit Trail
- All access is logged with the managed identity
- Easy to track who accessed what and when

## Code Implementation

### C# Functions

All Azure SDK clients use `DefaultAzureCredential`:

```csharp
private static readonly DefaultAzureCredential Credential = new();
```

This automatically:
1. Uses the Function App's managed identity when running in Azure
2. Falls back to Azure CLI credentials for local development
3. Supports other credential sources (VS Code, Visual Studio, etc.)

### Key Vault Access

```csharp
var kvUri = new Uri($"https://{keyVaultName}.vault.azure.net");
_secretClient = new SecretClient(kvUri, Credential);
```

Uses managed identity automatically - no keys or tokens needed.

### Storage Account Access

```csharp
var storageAccount = resourceGroup.GetStorageAccount(storageAccountName);
var keys = storageAccount.Value.GetKeys(); // Uses managed identity
```

The `GetKeys()` call uses the Function App's managed identity to retrieve storage keys.

## Local Development

When developing locally, `DefaultAzureCredential` will:
1. Try managed identity (not available locally)
2. Fall back to Azure CLI credentials
3. Fall back to Visual Studio credentials
4. Fall back to other credential sources

**Setup:**
```bash
az login
```

This allows local development without managing separate credentials.

## Troubleshooting

### "Access Denied" Errors

1. **Check RBAC assignments:**
   ```bash
   az role assignment list --assignee <function-app-principal-id>
   ```

2. **Verify managed identity is enabled:**
   ```bash
   az functionapp identity show --name <function-app-name> --resource-group <rg>
   ```

3. **Check Key Vault RBAC:**
   ```bash
   az keyvault show --name <key-vault-name> --query properties.enableRbacAuthorization
   ```

### Storage Key Retrieval Issues

If you get errors retrieving storage keys:
1. Verify the Function App has `Storage Account Contributor` role
2. Check the storage account exists and is accessible
3. Ensure the managed identity has propagated (may take a few minutes)

## Best Practices

1. ✅ **Always use managed identity** when available
2. ✅ **Use RBAC** instead of access policies for Key Vault
3. ✅ **Scope permissions** to the minimum required
4. ✅ **Use `DefaultAzureCredential`** in code for automatic credential resolution
5. ✅ **Document limitations** (like ACI not supporting managed identity for Azure Files)

## Future Improvements

- [ ] Migrate to managed identity for Azure Files when ACI supports it
- [ ] Consider user-assigned managed identity for cross-resource scenarios
- [ ] Implement managed identity for Application Insights (if needed)

## References

- [Azure Managed Identities](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [Key Vault RBAC](https://docs.microsoft.com/azure/key-vault/general/rbac-guide)
- [DefaultAzureCredential](https://docs.microsoft.com/dotnet/api/azure.identity.defaultazurecredential)
- [Azure Functions Managed Identity](https://docs.microsoft.com/azure/app-service/overview-managed-identity)
