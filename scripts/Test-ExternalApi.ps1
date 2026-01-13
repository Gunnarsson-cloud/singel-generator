<#
.SYNOPSIS
  Test-super-script: skapar en separat Azure Functions App för TEST,
  deployar din befintliga API-kod dit, och ger dig test-URL:er.
  Rör inte SWA, rör inte main-branch, rör inte staticwebapp.config.json.

.FÖRUTSÄTTNINGAR
  - Du står i repo-roten
  - Du har Azure CLI (az) installerat
  - Du har Functions Core Tools (func)
  - Du har Node installerat
#>

Write-Host "=== TEST-SUPER-SCRIPT: External Azure Functions API Test ===" -ForegroundColor Cyan

# --- 1. PARAMETRAR ---

$subscriptionId = Read-Host "Azure Subscription ID"
$resourceGroup  = Read-Host "Resource Group för TEST (skapas om den saknas)"
$location       = Read-Host "Azure region (t.ex. westeurope)"
$functionApp    = Read-Host "Namn på TEST Functions App (t.ex. singel-generator-api-test)"
$storageAccount = Read-Host "Namn på TEST Storage Account (t.ex. singelgenapiteststore)"

if ([string]::IsNullOrWhiteSpace($subscriptionId) -or
    [string]::IsNullOrWhiteSpace($resourceGroup) -or
    [string]::IsNullOrWhiteSpace($location) -or
    [string]::IsNullOrWhiteSpace($functionApp) -or
    [string]::IsNullOrWhiteSpace($storageAccount)) {
    Write-Error "Alla fält är obligatoriska."
    exit 1
}

# --- 2. LOGGA IN OCH SÄTT SUBSCRIPTION ---

Write-Host "`nLoggar in mot Azure..." -ForegroundColor Cyan
az account show 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    az login
}
az account set --subscription $subscriptionId

# --- 3. SKAPA RESOURCE GROUP (OM SAKNAS) ---

Write-Host "`nSäkerställer Resource Group..." -ForegroundColor Cyan
$rgExists = az group show --name $resourceGroup 2>$null
if ($LASTEXITCODE -ne 0) {
    az group create --name $resourceGroup --location $location | Out-Null
    Write-Host "Resource group skapad." -ForegroundColor Green
} else {
    Write-Host "Resource group finns redan." -ForegroundColor Green
}

# --- 4. SKAPA STORAGE ACCOUNT (OM SAKNAS) ---

Write-Host "`nSäkerställer Storage Account..." -ForegroundColor Cyan
$stExists = az storage account show --name $storageAccount --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -ne 0) {
    az storage account create `
        --name $storageAccount `
        --resource-group $resourceGroup `
        --location $location `
        --sku Standard_LRS `
        --kind StorageV2 | Out-Null
    Write-Host "Storage account skapat." -ForegroundColor Green
} else {
    Write-Host "Storage account finns redan." -ForegroundColor Green
}

# --- 5. SKAPA TEST FUNCTIONS APP (NODE 20, LINUX) ---

Write-Host "`nSkapar TEST Functions App..." -ForegroundColor Cyan
$faExists = az functionapp show --name $functionApp --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -ne 0) {
    az functionapp create `
        --name $functionApp `
        --resource-group $resourceGroup `
        --storage-account $storageAccount `
        --consumption-plan-location $location `
        --runtime node `
        --runtime-version 20 `
        --functions-version 4 `
        --os-type Linux | Out-Null
    Write-Host "TEST Functions App skapad." -ForegroundColor Green
} else {
    Write-Host "TEST Functions App finns redan." -ForegroundColor Green
}

# --- 6. DEPLOYA DIN BEFINTLIGA API-KOD TILL TEST FUNCTIONS APP ---

Write-Host "`nDeployar API-kod till TEST Functions App..." -ForegroundColor Cyan

if (-not (Test-Path ".\api")) {
    Write-Error "api/-mappen hittades inte. Kör skriptet i repo-roten."
    exit 1
}

Push-Location .\api
func azure functionapp publish $functionApp
Pop-Location

Write-Host "`n=== DEPLOY KLAR ===" -ForegroundColor Green

# --- 7. VISA TEST-URL:ER ---

$baseUrl = "https://$functionApp.azurewebsites.net/api"

Write-Host "`n=== TEST-API KLART ===" -ForegroundColor Cyan
Write-Host "Du kan nu testa dina endpoints i molnet:" -ForegroundColor Yellow

Write-Host "  $baseUrl/Ping"
Write-Host "  $baseUrl/GetProfiles"
Write-Host "  $baseUrl/SubmitProfile"
Write-Host "  $baseUrl/MatchNow"
Write-Host "  $baseUrl/MatchRespond"
Write-Host "  $baseUrl/Respond"
Write-Host "  $baseUrl/IssueOptInTokens"
Write-Host "  $baseUrl/ExpireMatches"
Write-Host "  $baseUrl/GetMatchContacts"
Write-Host "  $baseUrl/admin"
Write-Host "  $baseUrl/BlockPair"

Write-Host "`nOm dessa fungerar → teorin är bevisad: SWA Functions Runtime är flaskhalsen." -ForegroundColor Green
Write-Host "Om något faller → vi felsöker exakt den funktionen i testmiljön." -ForegroundColor Yellow
