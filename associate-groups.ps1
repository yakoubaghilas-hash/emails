param(
    [string]$Organization = "https://amayestech.visualstudio.com/",
    [string]$Project = "selfservicedemo",
    [string]$ADOGroupName,
    [string]$EntraGroupName,
    [string]$PAT
)

Write-Host "`n=== Associer Groupe Entra ID à Groupe Azure DevOps ===" -ForegroundColor Cyan

# Demander les paramètres manquants
if (-not $ADOGroupName) {
    $ADOGroupName = Read-Host "Entrez le nom du groupe Azure DevOps"
}

if (-not $EntraGroupName) {
    $EntraGroupName = Read-Host "Entrez le nom du groupe Entra ID à associer"
}

if (-not $PAT) {
    $PAT = Read-Host -Prompt "Entrez votre Personal Access Token (PAT)" -AsSecureString
    $PAT = [System.Net.NetworkCredential]::new("", $PAT).Password
}

if (-not $ADOGroupName -or -not $EntraGroupName -or -not $PAT) {
    Write-Host "[ERREUR] Les paramètres sont manquants" -ForegroundColor Red
    exit 1
}

$env:AZURE_DEVOPS_EXT_PAT = $PAT

# Trouver le groupe Azure DevOps
Write-Host "`nRecherche du groupe Azure DevOps: $ADOGroupName..." -ForegroundColor Yellow
$groupsJson = az devops security group list --org $Organization --project $Project 2>&1
$groups = $groupsJson | ConvertFrom-Json -ErrorAction SilentlyContinue

$groupList = if ($groups.graphGroups) { $groups.graphGroups } elseif ($groups.value) { $groups.value } else { @() }

$adoTargetGroup = $groupList | Where-Object { 
    $_.displayName -eq $ADOGroupName -or 
    $_.displayName -like "*$ADOGroupName*"
}

if (-not $adoTargetGroup) {
    Write-Host "[ERREUR] Groupe Azure DevOps '$ADOGroupName' non trouvé" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Groupe trouvé: $($adoTargetGroup.displayName)" -ForegroundColor Green

# Ajouter le groupe Entra ID à Azure DevOps et l'associer
Write-Host "`nAjout et association du groupe Entra ID..." -ForegroundColor Cyan
az devops security group membership add `
    --group-id $adoTargetGroup.descriptor `
    --member-path "aad://$EntraGroupName" `
    --org $Organization 2>&1

Write-Host "[OK] Groupe Entra ID associé avec succès!" -ForegroundColor Green
Write-Host "`nL'association est complète:" -ForegroundColor Green
Write-Host "  Groupe Azure DevOps: $($adoTargetGroup.displayName)" -ForegroundColor Green
Write-Host "  Groupe Entra ID: $EntraGroupName" -ForegroundColor Green
Write-Host ""
