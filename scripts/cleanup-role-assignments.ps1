# Cleanup old role assignments that conflict with new deployments
# This removes role assignments created by previous Bicep deployments

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$OldFunctionAppName = "valheim-func-vmaygfpvthejm",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host ""
Write-Host "Cleaning up old role assignments" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check if old Function App exists
$oldApp = az functionapp show --name $OldFunctionAppName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json

if (-not $oldApp) {
    Write-Host "Old Function App not found: $OldFunctionAppName" -ForegroundColor Yellow
    Write-Host "Checking for any role assignments in resource group..." -ForegroundColor Yellow
} else {
    Write-Host "Found old Function App: $OldFunctionAppName" -ForegroundColor Yellow
    $oldPrincipalId = az functionapp identity show --name $OldFunctionAppName --resource-group $ResourceGroupName --query "principalId" -o tsv 2>$null
    if ($oldPrincipalId) {
        Write-Host "  Principal ID: $oldPrincipalId" -ForegroundColor Gray
    }
}

# List all role assignments in the resource group
Write-Host ""
Write-Host "Finding role assignments in resource group..." -ForegroundColor Yellow
$roleAssignments = az role assignment list --resource-group $ResourceGroupName --output json | ConvertFrom-Json

if (-not $roleAssignments -or $roleAssignments.Count -eq 0) {
    Write-Host "No role assignments found in resource group." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($roleAssignments.Count) role assignment(s)" -ForegroundColor Yellow
Write-Host ""

# Filter for role assignments that might be from old deployments
# These are typically for Function Apps or have specific role definitions
$functionAppRoles = @(
    "4633458b-17de-408a-b874-0445c86b69e6",  # Key Vault Secrets User
    "5d977122-f97e-4b4d-a52f-6b43003ddb4d",  # Container Instance Contributor
    "ba92f5b4-2d11-453d-a403-e96b0029c9fe",  # Storage Blob Data Contributor
    "17d1049b-9a84-46fb-8f53-869881c3d3ab",  # Storage Account Contributor
    "a7264617-510b-434b-a828-9731dc254ea7"   # Storage File Data SMB Share Elevated Contributor
)

$assignmentsToDelete = @()
foreach ($assignment in $roleAssignments) {
    $roleId = $assignment.roleDefinitionId.Split('/')[-1]
    if ($functionAppRoles -contains $roleId) {
        $assignmentsToDelete += $assignment
    }
}

if ($assignmentsToDelete.Count -eq 0) {
    Write-Host "No conflicting role assignments found." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($assignmentsToDelete.Count) role assignment(s) that may conflict:" -ForegroundColor Yellow
foreach ($assignment in $assignmentsToDelete) {
    Write-Host "  - $($assignment.name)" -ForegroundColor Gray
    Write-Host "    Role: $($assignment.roleDefinitionName)" -ForegroundColor DarkGray
    Write-Host "    Principal: $($assignment.principalName)" -ForegroundColor DarkGray
    Write-Host ""
}

if (-not $Force) {
    Write-Host "WARNING: This will delete the role assignments listed above." -ForegroundColor Red
    Write-Host "These will be recreated by deploy.ps1 for the new Function App." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Are you sure you want to delete these role assignments? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Delete role assignments
Write-Host ""
Write-Host "Deleting role assignments..." -ForegroundColor Yellow
$deletedCount = 0
foreach ($assignment in $assignmentsToDelete) {
    Write-Host "  Deleting: $($assignment.name)..." -ForegroundColor Gray
    az role assignment delete --ids $assignment.id --output none 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $deletedCount++
        Write-Host "    ✅ Deleted" -ForegroundColor Green
    } else {
        Write-Host "    ⚠️  Failed to delete (may not exist)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "✅ Cleanup complete! Deleted $deletedCount role assignment(s)" -ForegroundColor Green
Write-Host ""
Write-Host "You can now run deploy.ps1 without role assignment conflicts." -ForegroundColor Cyan
