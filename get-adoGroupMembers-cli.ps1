# Script pour lister les utilisateurs d'un groupe Azure DevOps avec az devops CLI

param(
    [string]$Organization = "https://amayestech.visualstudio.com/",
    [string]$Project = "selfservicedemo",
    [string]$GroupName = "sdfsdfdf",
    [string]$PAT
)

# Demander le PAT s'il n'est pas fourni
if (-not $PAT) {
    $PAT = Read-Host -Prompt "Entrez votre Personal Access Token (PAT)" -AsSecureString
    $PAT = [System.Net.NetworkCredential]::new("", $PAT).Password
}

if (-not $PAT) {
    Write-Host "PAT vide. Abandon." -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Configuration ===" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project"
Write-Host "Group: $GroupName"
Write-Host ""

# Configurer l'authentification avec le PAT
$env:AZURE_DEVOPS_EXT_PAT = $PAT

# Configuration de l'organisation et du projet
$org = $Organization.TrimEnd('/')
if ($org.Contains('/')) {
    # Extraire le nom de l'organisation de l'URL
    $org = ($org -split '/')[-1]
}

Write-Host "Etape 1: Configuration de l'organisation" -ForegroundColor Cyan
az devops configure --defaults organization=$Organization project=$Project 2>&1 | Out-Null

# Etape 2: Lister les groupes
Write-Host "`nEtape 2: Recherche des groupes..." -ForegroundColor Cyan
$groupsJson = az devops security group list --org $Organization --project $Project 2>&1

$groups = $groupsJson | ConvertFrom-Json -ErrorAction SilentlyContinue

# La réponse utilise "graphGroups" et non "value"
$groupList = if ($groups.graphGroups) { $groups.graphGroups } elseif ($groups.value) { $groups.value } else { @() }

if (-not $groupList -or $groupList.Count -eq 0) {
    Write-Host "[ERREUR] Aucun groupe trouve" -ForegroundColor Red
    exit 1
}

Write-Host "Groupes disponibles:" -ForegroundColor Green
$groupList | ForEach-Object {
    Write-Host "  - $($_.displayName)"
}

# Etape 3: Chercher le groupe specifique
Write-Host "`nEtape 3: Recherche du groupe '$GroupName'..." -ForegroundColor Cyan
$targetGroup = $groupList | Where-Object { 
    $_.displayName -like "*$GroupName*" -or 
    $_.displayName -eq $GroupName -or
    $_.principalName -like "*$GroupName*"
}

if (-not $targetGroup) {
    Write-Host "[ERREUR] Groupe '$GroupName' non trouve" -ForegroundColor Red
    Write-Host "Groupes disponibles:" -ForegroundColor Yellow
    $groupList | ForEach-Object {
        Write-Host "  $($_.displayName) ($($_.principalName))"
    }
    exit 1
}

Write-Host "[OK] Groupe trouve: $($targetGroup.displayName)" -ForegroundColor Green
$groupDescriptor = $targetGroup.descriptor

# Etape 4: Lister les membres du groupe
Write-Host "`nEtape 4: Recuperation des membres..." -ForegroundColor Cyan

# Essayer avec la commande membership list
$membersJson = az devops security group membership list `
    --id $groupDescriptor `
    --org $Organization `
    --relationship members 2>&1

$members = $membersJson | ConvertFrom-Json -ErrorAction SilentlyContinue

# La réponse est un objet avec les descripteurs comme clés, pas un tableau
# On doit extraire les propriétés et filtrer les utilisateurs
$memberList = @()
$members.PSObject.Properties | ForEach-Object {
    if ($_.Value.subjectKind -eq "user") {
        $memberList += $_.Value
    }
}

if ($memberList.Count -eq 0) {
    Write-Host "[INFO] Aucun membre (utilisateur) trouve dans le groupe" -ForegroundColor Yellow
}
else {
    Write-Host "[OK] $($memberList.Count) membre(s) trouve(s):`n" -ForegroundColor Green
    
    $memberList | ForEach-Object {
        Write-Host "---"
        Write-Host "Nom            : $($_.displayName)"
        Write-Host "Email          : $($_.mailAddress)"
        Write-Host "Principal Name : $($_.principalName)"
        Write-Host "ID             : $($_.descriptor)"
    }
}

Write-Host "`n=== Fin ===" -ForegroundColor Green
