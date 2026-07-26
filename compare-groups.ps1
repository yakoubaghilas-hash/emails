# Script to compare users between Azure DevOps group and Entra ID group

param(
    [string]$Organization = "https://amayestech.visualstudio.com/",
    [string]$Project = "selfservicedemo",
    [string]$ADOGroupName = "sdfsdfdf",
    [string]$EntraGroupName,
    [string]$PAT
)

Write-Host "`n=== Group Comparison Tool ===" -ForegroundColor Cyan
Write-Host "Azure DevOps vs Entra ID`n" -ForegroundColor Cyan

# Prompt for missing parameters
if (-not $EntraGroupName) {
    $EntraGroupName = Read-Host "Enter the Entra ID group name"
}

if (-not $EntraGroupName) {
    Write-Host "[ERROR] Entra ID group name is required" -ForegroundColor Red
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
Write-Host "Entra ID Group: $EntraGroupName" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Step 1: Get Azure DevOps Group Members
# ============================================================================

Write-Host "Step 1: Retrieving Azure DevOps group members..." -ForegroundColor Yellow
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
    exit 1
}

Write-Host "[OK] Found Azure DevOps group: $($adoTargetGroup.displayName)" -ForegroundColor Green

# Get Azure DevOps group members
$adoMembersJson = az devops security group membership list `
    --id $adoTargetGroup.descriptor `
    --org $Organization `
    --relationship members 2>&1

$adoMembers = $adoMembersJson | ConvertFrom-Json -ErrorAction SilentlyContinue

$adoMemberList = @()
$adoMembers.PSObject.Properties | ForEach-Object {
    if ($_.Value.subjectKind -eq "user") {
        $adoMemberList += @{
            Name = $_.Value.displayName
            Email = $_.Value.mailAddress
            Principal = $_.Value.principalName
            Source = "Azure DevOps"
        }
    }
}

Write-Host "[OK] Found $($adoMemberList.Count) member(s) in Azure DevOps group`n" -ForegroundColor Green

# ============================================================================
# Step 2: Get Entra ID Group Members
# ============================================================================

Write-Host "Step 2: Retrieving Entra ID group members..." -ForegroundColor Yellow

# Import required modules
Import-Module Microsoft.Graph.Groups -Force -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Users -Force -ErrorAction SilentlyContinue

try {
    # Connect to Microsoft Graph
    Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All" -ErrorAction Stop -NoWelcome 2>&1 | Out-Null
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
}
catch {
    Write-Host "[ERROR] Error searching for Entra ID group: $($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

# Get Entra ID group members
try {
    $entraMembers = Get-MgGroupMember -GroupId $entraGroup.Id -All -ErrorAction Stop
    
    $entraMemberList = @()
    $entraMembers | ForEach-Object {
        $member = $_
        
        if ($member.AdditionalProperties.userPrincipalName) {
            $entraMemberList += @{
                Name = $member.AdditionalProperties.displayName
                Email = $member.AdditionalProperties.mail
                Principal = $member.AdditionalProperties.userPrincipalName
                Source = "Entra ID"
            }
        }
    }
    
    Write-Host "[OK] Found $($entraMemberList.Count) member(s) in Entra ID group`n" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Error retrieving Entra ID members: $($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

# ============================================================================
# Step 3: Compare the two groups
# ============================================================================

Write-Host "Step 3: Comparing groups..." -ForegroundColor Yellow
Write-Host ""

# Normalize email addresses for comparison
$adoEmails = @{}
$adoMemberList | ForEach-Object {
    $key = ($_.Email -or $_.Principal).ToLower()
    $adoEmails[$key] = $_
}

$entraEmails = @{}
$entraMemberList | ForEach-Object {
    $key = ($_.Email -or $_.Principal).ToLower()
    $entraEmails[$key] = $_
}

# Find users in both groups
$inBoth = @()
$onlyInADO = @()
$onlyInEntra = @()

$adoEmails.Keys | ForEach-Object {
    if ($entraEmails.ContainsKey($_)) {
        $inBoth += $adoEmails[$_]
    }
    else {
        $onlyInADO += $adoEmails[$_]
    }
}

$entraEmails.Keys | ForEach-Object {
    if (-not $adoEmails.ContainsKey($_)) {
        $onlyInEntra += $entraEmails[$_]
    }
}

# Display results
Write-Host "=== RESULTS ===" -ForegroundColor Cyan
Write-Host ""

# Users in both groups
Write-Host "Users present in BOTH groups: $($inBoth.Count)" -ForegroundColor Green
if ($inBoth.Count -gt 0) {
    $inBoth | ForEach-Object {
        Write-Host "  [OK] $($_.Name) ($($_.Principal))"
    }
}
Write-Host ""

# Users only in Azure DevOps
Write-Host "Users ONLY in Azure DevOps: $($onlyInADO.Count)" -ForegroundColor Yellow
if ($onlyInADO.Count -gt 0) {
    $onlyInADO | ForEach-Object {
        Write-Host "  [ADO] $($_.Name) ($($_.Principal))"
    }
}
else {
    Write-Host "  None" -ForegroundColor Gray
}
Write-Host ""

# Users only in Entra ID
Write-Host "Users ONLY in Entra ID: $($onlyInEntra.Count)" -ForegroundColor Yellow
if ($onlyInEntra.Count -gt 0) {
    $onlyInEntra | ForEach-Object {
        Write-Host "  [AAD] $($_.Name) ($($_.Principal))"
    }
}
else {
    Write-Host "  None" -ForegroundColor Gray
}
Write-Host ""

# Summary
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Azure DevOps total members: $($adoMemberList.Count)" -ForegroundColor Cyan
Write-Host "Entra ID total members: $($entraMemberList.Count)" -ForegroundColor Cyan
Write-Host "Synchronized users: $($inBoth.Count)" -ForegroundColor Green
Write-Host "Discrepancies: $($onlyInADO.Count + $onlyInEntra.Count)" -ForegroundColor $(if ($onlyInADO.Count + $onlyInEntra.Count -gt 0) { "Red" } else { "Green" })
Write-Host ""

Write-Host "=== Complete ===" -ForegroundColor Green
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
