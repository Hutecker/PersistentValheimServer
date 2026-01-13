# Fixing Azure Quota Error

## Error: SubscriptionIsOverQuotaForSku

If you see this error:
```
SubscriptionIsOverQuotaForSku
Current Limit (Dynamic VMs): 0
Amount required for this deployment (Dynamic VMs): 1
```

This means your Azure subscription doesn't have quota for Function Apps on Consumption plan.

## Solution Options

### Option 1: Request Quota Increase (Recommended - Free)

1. Go to Azure Portal: https://portal.azure.com
2. Navigate to **Subscriptions** → Your Subscription → **Usage + quotas**
3. Search for "App Service - Dynamic" or "Function Apps"
4. Click **Request increase**
5. Fill out the form:
   - **Quota type**: App Service - Dynamic
   - **Region**: eastus (or your region)
   - **New limit**: 10 (or more)
6. Submit the request (usually approved within 24-48 hours)

**Alternative via Azure CLI:**
```powershell
az support tickets create \
  --title "Request Function App Consumption Plan Quota" \
  --description "Need quota for Function Apps on Consumption plan (Dynamic VMs) in eastus region" \
  --problem-classification "/providers/Microsoft.Support/services/quota_service_guid/problem_types/quota_problem_type_guid" \
  --severity "minimal"
```

### Option 2: Use Basic App Service Plan (Immediate - Costs More)

If you need to deploy immediately, you can switch to a Basic plan:

1. Edit `infrastructure/main.bicep`
2. Change the App Service Plan SKU from:
   ```bicep
   sku: {
     name: 'Y1' // Consumption plan
     tier: 'Dynamic'
   }
   ```
   To:
   ```bicep
   sku: {
     name: 'B1' // Basic plan
     tier: 'Basic'
   }
   ```

**Cost Impact:**
- Consumption Plan: ~$0.20/month (pay per execution)
- Basic Plan: ~$13/month (always running)

### Option 3: Use Azure Container Apps (Alternative)

Container Apps is serverless and doesn't require the same quota. However, this would require significant code changes.

## Recommended Approach

1. **Request quota increase** (Option 1) - it's free and the right long-term solution
2. **Wait for approval** (usually 24-48 hours)
3. **Re-run deployment** once quota is approved

## Check Quota Status

```powershell
az vm list-usage --location eastus --query "[?contains(name.value, 'Function') || contains(name.value, 'Dynamic')]" -o table
```

## Temporary Workaround

If you need to test immediately, you can:
1. Use Option 2 (Basic plan) temporarily
2. Request quota increase
3. Switch back to Consumption plan once quota is approved
4. Delete the Basic plan to save costs
