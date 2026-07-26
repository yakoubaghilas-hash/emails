# Script to list users from an Entra ID (Azure AD) group
# Connects using the current user's account

param(
    [string]$GroupName,
    [string]$TenantId
)

# Check if Microsoft.Graph module is installed
Write-Host "Checking Microsoft.Graph module..." -ForegroundColor Cyan
$module = Get-Module -Name Microsoft.Graph.Groups -ListAvailable

if (-not $module) {
    Write-Host "[INFO] Microsoft.Graph module not found. Installing..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph.Groups -Scope CurrentUser -Force -AllowClobber 2>&1 | Out-Null
    Write-Host "[OK] Module installed" -ForegroundColor Green
}

# Import required modules
Import-Module Microsoft.Graph.Groups -Force
Import-Module Microsoft.Graph.Users -Force

Write-Host "`n=== Configuration ===" -ForegroundColor Cyan

# Prompt for group name if not provided
if (-not $GroupName) {
    $GroupName = Read-Host "Enter the Entra ID group name"
}

if (-not $GroupName) {
    Write-Host "[ERROR] Group name is required" -ForegroundColor Red
    exit 1
}

Write-Host "Group Name: $GroupName"

# Connect to Microsoft Graph
Write-Host "`nStep 1: Connecting to Entra ID..." -ForegroundColor Cyan
try {
    # Connect with default scopes
    Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All", "Directory.Read.All" -ErrorAction Stop -NoWelcome 2>&1 | Out-Null
    Write-Host "[OK] Connected successfully" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 2: Search for the group
Write-Host "`nStep 2: Searching for group '$GroupName'..." -ForegroundColor Cyan
try {
    # Search by display name
    $groups = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction Stop
    
    if (-not $groups) {
        Write-Host "[ERROR] Group '$GroupName' not found" -ForegroundColor Red
        
        # Try to list some groups as suggestions
        Write-Host "`nSearching for similar groups..." -ForegroundColor Yellow
        $similarGroups = Get-MgGroup -Filter "startsWith(displayName,'$(($GroupName).Substring(0, [Math]::Min(3, $GroupName.Length)))')" -Top 10
        
        if ($similarGroups) {
            Write-Host "Available groups:" -ForegroundColor Yellow
            $similarGroups | ForEach-Object {
                Write-Host "  - $($_.DisplayName)"
            }
        }
        exit 1
    }
    
    $group = $groups | Select-Object -First 1
    Write-Host "[OK] Group found: $($group.DisplayName)" -ForegroundColor Green
    Write-Host "Group ID: $($group.Id)" -ForegroundColor Gray
}
catch {
    Write-Host "[ERROR] Error searching for group: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 3: Get group members
Write-Host "`nStep 3: Retrieving group members..." -ForegroundColor Cyan
try {
    $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction Stop
    
    if (-not $members -or $members.Count -eq 0) {
        Write-Host "[INFO] No members found in the group" -ForegroundColor Yellow
    }
    else {
        Write-Host "[OK] $($members.Count) member(s) found:`n" -ForegroundColor Green
        
        # Process each member
        $members | ForEach-Object {
            $member = $_
            
            # Get additional user details if it's a user
            if ($member.AdditionalProperties.userPrincipalName) {
                Write-Host "---"
                Write-Host "Display Name   : $($member.AdditionalProperties.displayName)"
                Write-Host "User Principal : $($member.AdditionalProperties.userPrincipalName)"
                Write-Host "Email          : $($member.AdditionalProperties.mail)"
                Write-Host "Account Status : $($member.AdditionalProperties.accountEnabled)"
                Write-Host "ID             : $($member.Id)"
            }
            else {
                # It might be a group or service principal
                Write-Host "---"
                Write-Host "Name           : $($member.AdditionalProperties.displayName)"
                Write-Host "Type           : $($member.AdditionalProperties.'@odata.type')"
                Write-Host "ID             : $($member.Id)"
            }
        }
    }
}
catch {
    Write-Host "[ERROR] Error retrieving members: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 4: Offer to disconnect
Write-Host "`n=== Complete ===" -ForegroundColor Green
Write-Host "Disconnecting from Entra ID..." -ForegroundColor Cyan
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Write-Host "[OK] Disconnected" -ForegroundColor Green
