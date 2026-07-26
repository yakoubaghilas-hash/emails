# Script to list users from an Azure DevOps group using az devops CLI

param(
    [string]$Organization = "https://amayestech.visualstudio.com/",
    [string]$Project = "selfservicedemo",
    [string]$GroupName = "sdfsdfdf",
    [string]$PAT
)

# Prompt for PAT if not provided
if (-not $PAT) {
    $PAT = Read-Host -Prompt "Entrez votre Personal Access Token (PAT)" -AsSecureString
    $PAT = [System.Net.NetworkCredential]::new("", $PAT).Password
}

if (-not $PAT) {
    Write-Host "Empty PAT. Aborting." -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Configuration ===" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project"
Write-Host "Group: $GroupName"
Write-Host ""

# Configure authentication with PAT
$env:AZURE_DEVOPS_EXT_PAT = $PAT

# Configure organization and project
$org = $Organization.TrimEnd('/')
if ($org.Contains('/')) {
    # Extract organization name from URL
    $org = ($org -split '/')[-1]
}

Write-Host "Step 1: Configure organization" -ForegroundColor Cyan
az devops configure --defaults organization=$Organization project=$Project 2>&1 | Out-Null

# Step 2: List groups
Write-Host "`nStep 2: Search for groups..." -ForegroundColor Cyan
$groupsJson = az devops security group list --org $Organization --project $Project 2>&1

$groups = $groupsJson | ConvertFrom-Json -ErrorAction SilentlyContinue

# Response uses "graphGroups" not "value"
$groupList = if ($groups.graphGroups) { $groups.graphGroups } elseif ($groups.value) { $groups.value } else { @() }

if (-not $groupList -or $groupList.Count -eq 0) {
    Write-Host "[ERROR] No groups found" -ForegroundColor Red
    exit 1
}

Write-Host "Available groups:" -ForegroundColor Green
$groupList | ForEach-Object {
    Write-Host "  - $($_.displayName)"
}

# Step 3: Find specific group
Write-Host "`nStep 3: Searching for group '$GroupName'..." -ForegroundColor Cyan
$targetGroup = $groupList | Where-Object { 
    $_.displayName -like "*$GroupName*" -or 
    $_.displayName -eq $GroupName -or
    $_.principalName -like "*$GroupName*"
}

if (-not $targetGroup) {
    Write-Host "[ERROR] Group '$GroupName' not found" -ForegroundColor Red
    Write-Host "Available groups:" -ForegroundColor Yellow
    $groupList | ForEach-Object {
        Write-Host "  $($_.displayName) ($($_.principalName))"
    }
    exit 1
}

Write-Host "[OK] Group found: $($targetGroup.displayName)" -ForegroundColor Green
$groupDescriptor = $targetGroup.descriptor

# Step 4: List group members
Write-Host "`nStep 4: Retrieving members..." -ForegroundColor Cyan

# Retrieve members using membership list command
$membersJson = az devops security group membership list `
    --id $groupDescriptor `
    --org $Organization `
    --relationship members 2>&1

$members = $membersJson | ConvertFrom-Json -ErrorAction SilentlyContinue

# Response is an object with descriptors as keys, not an array
# Extract properties and filter for users
$memberList = @()
$members.PSObject.Properties | ForEach-Object {
    if ($_.Value.subjectKind -eq "user") {
        $memberList += $_.Value
    }
}

if ($memberList.Count -eq 0) {
    Write-Host "[INFO] No user members found in the group" -ForegroundColor Yellow
}
else {
    Write-Host "[OK] $($memberList.Count) member(s) found:`n" -ForegroundColor Green
    
    $memberList | ForEach-Object {
        Write-Host "---"
        Write-Host "Name           : $($_.displayName)"
        Write-Host "Email          : $($_.mailAddress)"
        Write-Host "Principal Name : $($_.principalName)"
        Write-Host "ID             : $($_.descriptor)"
    }
}

Write-Host "`n=== Complete ===" -ForegroundColor Green
