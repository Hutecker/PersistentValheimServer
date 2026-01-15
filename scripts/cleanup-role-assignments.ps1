# One-time script to clean up old role assignments before deploying updated Bicep template
# Run this ONCE if you get "RoleAssignmentUpdateNotPermitted" errors after updating the Bicep template
#
# This is needed because:
# - The Bicep template now uses new guid() formulas for role assignment names
# - Old role assignments with different GUIDs must be deleted first
# - After this cleanup, future deployments will be idempotent (no cleanup needed)

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$FunctionAppName = "valheim-func"
)

Write-Host "One-time role assignment cleanup for: $ResourceGroupName" -ForegroundColor Cyan
Write-Host "This script deletes old role assignments so the updated Bicep template can create new ones." -ForegroundColor Gray
Write-Host ""

# Get Function App managed identity principal ID
Write-Host "Getting Function App managed identity..." -ForegroundColor Yellow
$functionAppPrincipalId = az functionapp show --name $FunctionAppName --resource-group $ResourceGroupName --query "identity.principalId" --output tsv 2>$null

if (-not $functionAppPrincipalId) {
    Write-Host "Function App not found or has no managed identity." -ForegroundColor Yellow
    Write-Host "This is fine if this is a fresh deployment." -ForegroundColor Gray
    exit 0
}

Write-Host "Found Function App managed identity: $functionAppPrincipalId" -ForegroundColor Green
Write-Host ""

# List ALL role assignments for this principal (at all scopes)
Write-Host "Finding all role assignments..." -ForegroundColor Yellow
$allRoleAssignments = az role assignment list --assignee $functionAppPrincipalId --all --output json 2>$null | ConvertFrom-Json

# Filter to only those in our resource group
$roleAssignments = $allRoleAssignments | Where-Object { $_.scope -like "*resourceGroups/$ResourceGroupName*" }

if (-not $roleAssignments -or $roleAssignments.Count -eq 0) {
    Write-Host "No role assignments found for this Function App in the resource group." -ForegroundColor Green
    Write-Host "You can proceed with deployment." -ForegroundColor Gray
    exit 0
}

Write-Host "Found $($roleAssignments.Count) role assignment(s) to delete:" -ForegroundColor Yellow
foreach ($assignment in $roleAssignments) {
    Write-Host "  - $($assignment.roleDefinitionName)" -ForegroundColor Gray
    Write-Host "    Scope: $($assignment.scope)" -ForegroundColor DarkGray
}

Write-Host ""
# Auto-confirm in non-interactive mode (for script automation)
$autoConfirm = $env:CI -eq "true" -or $env:TF_BUILD -eq "true" -or $args -contains "-Force"
if (-not $autoConfirm) {
    $confirm = Read-Host "Delete these role assignments? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "Auto-confirming deletion (non-interactive mode)..." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Deleting role assignments..." -ForegroundColor Yellow
$deleted = 0
foreach ($assignment in $roleAssignments) {
    Write-Host "  Deleting $($assignment.roleDefinitionName)..." -ForegroundColor Gray
    az role assignment delete --ids $assignment.id --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        $deleted++
    }
}

Write-Host ""
Write-Host "✅ Deleted $deleted role assignment(s)" -ForegroundColor Green
Write-Host ""
Write-Host "You can now run the deployment script." -ForegroundColor Cyan
Write-Host "The Bicep template will create new role assignments with stable GUIDs." -ForegroundColor Gray
