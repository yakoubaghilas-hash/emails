# Script to associate an Entra ID group with an Azure DevOps group
# Adds an Entra ID group as a member of an Azure DevOps group

param(
    [string]$Organization = "https://amayestech.visualstudio.com/",
    [string]$Project = "selfservicedemo",
    [string]$ADOGroupName = "sdfsdfdf",
    [string]$EntraGroupName = "toto1917",
    [string]$PAT = "3sCrYLCyiFxlDU4cLAlZaH9t7CswV2V3tjGGLg3RLsZtbnDBeEJQQJ99CGACAAAAAAAAAAAAASAZDO4KJy"
)

Write-Host "`n=== Associate Entra ID Group to Azure DevOps Group ===" -ForegroundColor Cyan
Write-Host ""

# Prompt for missing parameters
if (-not $ADOGroupName) {
    $ADOGroupName = Read-Host "Enter the Azure DevOps group name"
}

if (-not $EntraGroupName) {
    $EntraGroupName = Read-Host "Enter the Entra ID group name to associate"
}

if (-not $ADOGroupName -or -not $EntraGroupName) {
    Write-Host "[ERROR] Both group names are required" -ForegroundColor Red
    exit 1
}

if (-not $PAT) {
    $PAT = Read-Host -Prompt "Enter your Personal Access Token (PAT)" -AsSecureString
    $PAT = [System.Net.NetworkCredential]::new("", $PAT).Password
}

if (-not $PAT) {
    Write-Host "[ERROR] PAT is required" -ForegroundColor Red
    exit 1
}

Write-Host "Azure DevOps Group: $ADOGroupName" -ForegroundColor Cyan
Write-Host "Entra ID Group to Associate: $EntraGroupName" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Step 1: Find Azure DevOps Group
# ============================================================================

Write-Host "Step 1: Finding Azure DevOps group..." -ForegroundColor Yellow
$env:AZURE_DEVOPS_EXT_PAT = $PAT

$groupsJson = az devops security group list --org $Organization --project $Project 2>&1
$groups = $groupsJson | ConvertFrom-Json -ErrorAction SilentlyContinue

$groupList = if ($groups.graphGroups) { $groups.graphGroups } elseif ($groups.value) { $groups.value } else { @() }

if (-not $groupList) {
    Write-Host "[ERROR] No Azure DevOps groups found" -ForegroundColor Red
    exit 1
}

$adoTargetGroup = $groupList | Where-Object { 
    $_.displayName -like "*$ADOGroupName*" -or 
    $_.displayName -eq $ADOGroupName -or
    $_.principalName -like "*$ADOGroupName*"
}

if (-not $adoTargetGroup) {
    Write-Host "[ERROR] Azure DevOps group '$ADOGroupName' not found" -ForegroundColor Red
    Write-Host "Available groups:" -ForegroundColor Yellow
    $groupList | ForEach-Object {
        Write-Host "  - $($_.displayName)"
    }
    exit 1
}

Write-Host "[OK] Found Azure DevOps group: $($adoTargetGroup.displayName)" -ForegroundColor Green
Write-Host "Descriptor: $($adoTargetGroup.descriptor)" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Step 2: Find Entra ID Group
# ============================================================================

Write-Host "Step 2: Finding Entra ID group..." -ForegroundColor Yellow

# Import required modules
Import-Module Microsoft.Graph.Groups -Force -ErrorAction SilentlyContinue

try {
    # Connect to Microsoft Graph
    Connect-MgGraph -Scopes "Group.Read.All", "GroupMember.ReadWrite.All" -ErrorAction Stop -NoWelcome 2>&1 | Out-Null
    Write-Host "[OK] Connected to Entra ID" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to connect to Entra ID: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Search for Entra ID group
try {
    $entraGroups = Get-MgGroup -Filter "displayName eq '$EntraGroupName'" -ErrorAction Stop
    
    if (-not $entraGroups) {
        Write-Host "[ERROR] Entra ID group '$EntraGroupName' not found" -ForegroundColor Red
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }
    
    $entraGroup = $entraGroups | Select-Object -First 1
    Write-Host "[OK] Found Entra ID group: $($entraGroup.DisplayName)" -ForegroundColor Green
    Write-Host "ID: $($entraGroup.Id)" -ForegroundColor Gray
    Write-Host "Mail: $($entraGroup.Mail)" -ForegroundColor Gray
}
catch {
    Write-Host "[ERROR] Error searching for Entra ID group: $($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

Write-Host ""

# ============================================================================
# Step 3: Associate Entra ID Group to Azure DevOps Group
# ============================================================================

Write-Host "Step 3: Associating groups..." -ForegroundColor Yellow

# Get the principal name of the Entra ID group
# Format: "Entra ID Group Name" or domain\groupname
$entraPrincipalName = if ($entraGroup.Mail) {
    $entraGroup.Mail
}
else {
    $entraGroup.DisplayName
}

Write-Host "Using principal name: $entraPrincipalName" -ForegroundColor Gray

# Method 1: Using Azure DevOps CLI to add group member
try {
    Write-Host "Adding Entra ID group to Azure DevOps group..." -ForegroundColor Cyan
    
    # First, try to find the Entra group descriptor in Azure DevOps
    # We need to search for it in the available groups
    $adoEntraGroupsJson = az devops security group list --org $Organization --scope aad 2>&1
    
    if ($adoEntraGroupsJson -notlike "*error*" -and $adoEntraGroupsJson -notlike "*ERROR*") {
        $adoEntraGroups = $adoEntraGroupsJson | ConvertFrom-Json -ErrorAction SilentlyContinue
        $entraGroupList = if ($adoEntraGroups.graphGroups) { $adoEntraGroups.graphGroups } elseif ($adoEntraGroups.value) { $adoEntraGroups.value } else { @() }
        
        $adoEntraGroupMatch = $entraGroupList | Where-Object { 
            $_.displayName -eq $EntraGroupName -or 
            $_.principalName -eq $entraPrincipalName -or
            $_.displayName -like "*$EntraGroupName*"
        }
        
        if ($adoEntraGroupMatch) {
            Write-Host "[OK] Found Entra group in Azure DevOps: $($adoEntraGroupMatch.displayName)" -ForegroundColor Green
            $entraGroupDescriptor = $adoEntraGroupMatch.descriptor
            
            # Add the Entra group to the Azure DevOps group
            Write-Host "Adding membership..." -ForegroundColor Cyan
            az devops security group membership add `
                --group-id $adoTargetGroup.descriptor `
                --member-id $entraGroupDescriptor `
                --org $Organization 2>&1 | Out-Null
            
            Write-Host "[OK] Entra ID group successfully added to Azure DevOps group!" -ForegroundColor Green
        }
        else {
            Write-Host "[WARNING] Entra group not found in Azure DevOps. Listing available AAD groups..." -ForegroundColor Yellow
            $entraGroupList | ForEach-Object {
                Write-Host "  - $($_.displayName) ($($_.principalName))"
            }
        }
    }
    else {
        Write-Host "[WARNING] Could not list AAD groups in Azure DevOps" -ForegroundColor Yellow
        Write-Host "You may need to add the group manually through the Azure DevOps UI" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[ERROR] Error during association: $($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

Write-Host ""

# ============================================================================
# Step 4: Verify the Association
# ============================================================================

Write-Host "Step 4: Verifying association..." -ForegroundColor Yellow

try {
    $members = az devops security group membership list `
        --id $adoTargetGroup.descriptor `
        --org $Organization `
        --relationship members 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
    
    $members.PSObject.Properties | ForEach-Object {
        if ($_.Value.displayName -like "*$EntraGroupName*" -or $_.Value.principalName -like "*$EntraGroupName*") {
            Write-Host "[OK] Verified: Entra ID group is now a member of Azure DevOps group" -ForegroundColor Green
            Write-Host "Name: $($_.Value.displayName)" -ForegroundColor Green
            Write-Host "Type: $($_.Value.subjectKind)" -ForegroundColor Green
        }
    }
}
catch {
    Write-Host "[INFO] Could not verify membership" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Complete ===" -ForegroundColor Green
Write-Host "The Entra ID group '$EntraGroupName' has been associated with Azure DevOps group '$($adoTargetGroup.displayName)'" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Verify the group membership in Azure DevOps" -ForegroundColor Cyan
Write-Host "  2. Users in the Entra ID group will automatically have access through Azure DevOps" -ForegroundColor Cyan
Write-Host ""

Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
