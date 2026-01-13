# Cleanup script for old/unused Azure resources
# This script removes resources that are no longer needed after migration to Flex Consumption

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host "Cleaning up old resources in resource group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host ""

# Resources to keep (standardized names)
$keepResources = @(
    "valheim-func-flex",           # Flex Consumption Function App
    "valheim-server-rg",           # Resource group itself
    "valheim-kv-server-rg",        # Key Vault (standardized name)
    "valheimserver-rg",            # Storage account (standardized name)
    "valheimfuncserver-rg",        # Function storage account (standardized name)
    "valheim-insights-server-rg",  # Application Insights (standardized name)
    "valheim-server"                # Container group
)

# Resources to delete
$resourcesToDelete = @()

Write-Host "Scanning resources..." -ForegroundColor Cyan

# Get all resources in the resource group
$allResources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json

foreach ($resource in $allResources) {
    $resourceName = $resource.name
    $resourceType = $resource.type
    
    # Check if this is a resource we should keep
    $shouldKeep = $false
    foreach ($keep in $keepResources) {
        if ($resourceName -like "*$keep*" -or $resourceName -eq $keep) {
            $shouldKeep = $true
            break
        }
    }
    
    # Special handling for old Function App
    if ($resourceType -eq "Microsoft.Web/sites" -and $resourceName -ne "valheim-func-flex") {
        Write-Host "  Found old Function App: $resourceName" -ForegroundColor Yellow
        $resourcesToDelete += @{
            Name = $resourceName
            Type = $resourceType
            Id = $resource.id
        }
    }
    # Old App Service Plans (not needed for Flex Consumption)
    elseif ($resourceType -eq "Microsoft.Web/serverfarms") {
        Write-Host "  Found App Service Plan: $resourceName" -ForegroundColor Yellow
        $resourcesToDelete += @{
            Name = $resourceName
            Type = $resourceType
            Id = $resource.id
        }
    }
    # Old Log Analytics Workspaces (keep only the one created by Application Insights)
    elseif ($resourceType -eq "Microsoft.OperationalInsights/workspaces") {
        if ($resourceName -notlike "*valheim-insights*" -and $resourceName -notlike "*managed-valheim*") {
            Write-Host "  Found old Log Analytics Workspace: $resourceName" -ForegroundColor Yellow
            $resourcesToDelete += @{
                Name = $resourceName
                Type = $resourceType
                Id = $resource.id
            }
        }
    }
    # Resources with random suffixes (old naming convention)
    elseif (-not $shouldKeep -and ($resourceName -match "vmaygfpvthejm" -or $resourceName -match "afbe")) {
        Write-Host "  Found resource with old naming: $resourceName ($resourceType)" -ForegroundColor Yellow
        $resourcesToDelete += @{
            Name = $resourceName
            Type = $resourceType
            Id = $resource.id
        }
    }
}

if ($resourcesToDelete.Count -eq 0) {
    Write-Host "✅ No old resources found to clean up." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "Resources to delete:" -ForegroundColor Red
foreach ($resource in $resourcesToDelete) {
    Write-Host "  - $($resource.Name) ($($resource.Type))" -ForegroundColor Red
}

if (-not $Force) {
    Write-Host ""
    $confirm = Read-Host "Do you want to delete these resources? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Deleting resources..." -ForegroundColor Yellow

foreach ($resource in $resourcesToDelete) {
    Write-Host "  Deleting $($resource.Name)..." -ForegroundColor Gray
    az resource delete --ids $resource.Id --output none 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ✅ Deleted $($resource.Name)" -ForegroundColor Green
    } else {
        Write-Host "    ⚠️  Failed to delete $($resource.Name) (may already be deleted)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "✅ Cleanup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Remaining resources:" -ForegroundColor Cyan
az resource list --resource-group $ResourceGroupName --output table
