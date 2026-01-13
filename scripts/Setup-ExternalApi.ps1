<#
.SYNOPSIS
  Super-skript för att flytta API från SWA inbyggd Functions till extern Azure Functions App
  och koppla SWA till den externa API:n.

.FÖRUTSÄTTNINGAR
  - Du står i repo-roten (där .git ligger)
  - Du har Azure CLI (az), Azure Functions Core Tools (func), Git och Node installerat
  - Du är inloggad i GitHub remote (origin redan satt)

#>

Write-Host "=== SUPER-SKRIPT: Setup External Azure Functions API for SWA ===" -ForegroundColor Cyan

# --- 1. KONTROLLERA ATT VI ÄR I ETT GIT-REPO ---

if (-not (Test-Path ".git")) {
    Write-Error "Det här verkar inte vara repo-roten (ingen .git-katalog). Gå till rätt katalog och kör igen."
    exit 1
}

# --- 2. PARAMETRAR (FRÅGA DIG EN GÅNG) ---

$subscriptionId = Read-Host "Ange Azure Subscription ID (t.ex. 00000000-0000-0000-0000-000000000000)"
$resourceGroup  = Read-Host "Ange Resource Group namn för Functions App (skapas om den inte finns)"
$location       = Read-Host "Ange Azure region (t.ex. westeurope)"
$functionApp    = Read-Host "Ange namn för nya Functions App (måste vara globalt unikt, t.ex. singel-generator-api-func)"
$storageAccount = Read-Host "Ange namn för Storage Account (3-24 tecken, små bokstäver/siffror, t.ex. singelgenapistorage)"
$swaUrlOrName   = Read-Host "Ange din Static Web App URL (t.ex. https://agreeable-ground-0ee11971e.1.azurestaticapps.net) eller bara namnet"

if ([string]::IsNullOrWhiteSpace($subscriptionId) -or
    [string]::IsNullOrWhiteSpace($resourceGroup) -or
    [string]::IsNullOrWhiteSpace($location) -or
    [string]::IsNullOrWhiteSpace($functionApp) -or
    [string]::IsNullOrWhiteSpace($storageAccount)) {
    Write-Error "Alla fält är obligatoriska. Kör skriptet igen och fyll i allt."
    exit 1
}

# --- 3. LOGGA IN OCH SÄTT SUBSCRIPTION ---

Write-Host "`n=== Loggar in mot Azure och sätter subscription ===" -ForegroundColor Cyan
az account show 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Du verkar inte vara inloggad. Öppnar az login..." -ForegroundColor Yellow
    az login
}
az account set --subscription $subscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Error "Kunde inte sätta subscription. Kontrollera Subscription ID."
    exit 1
}

# --- 4. SKAPA RESOURCE GROUP (OM DEN SAKNAS) ---

Write-Host "`n=== Säkerställer Resource Group ===" -ForegroundColor Cyan
$rgExists = az group show --name $resourceGroup 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Resource group '$resourceGroup' finns inte. Skapar..." -ForegroundColor Yellow
    az group create --name $resourceGroup --location $location | Out-Null
} else {
    Write-Host "Resource group '$resourceGroup' finns redan." -ForegroundColor Green
}

# --- 5. SKAPA STORAGE ACCOUNT (OM DET SAKNAS) ---

Write-Host "`n=== Säkerställer Storage Account ===" -ForegroundColor Cyan
$stExists = az storage account show --name $storageAccount --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Storage account '$storageAccount' finns inte. Skapar..." -ForegroundColor Yellow
    az storage account create `
        --name $storageAccount `
        --resource-group $resourceGroup `
        --location $location `
        --sku Standard_LRS `
        --kind StorageV2 | Out-Null
} else
{
    Write-Host "Storage account '$storageAccount' finns redan." -ForegroundColor Green
}

# --- 6. SKAPA FUNCTIONS APP (NODE 20, LINUX, CONSUMPTION) ---

Write-Host "`n=== Säkerställer Azure Functions App ===" -ForegroundColor Cyan
$faExists = az functionapp show --name $functionApp --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Functions App '$functionApp' finns inte. Skapar..." -ForegroundColor Yellow
    az functionapp create `
        --name $functionApp `
        --resource-group $resourceGroup `
        --storage-account $storageAccount `
        --consumption-plan-location $location `
        --runtime node `
        --runtime-version 20 `
        --functions-version 4 `
        --os-type Linux | Out-Null
} else {
    Write-Host "Functions App '$functionApp' finns redan." -ForegroundColor Green
}

# --- 7. UPPDATERA api/package.json FÖR EXTERN FUNCTIONS APP ---

Write-Host "`n=== Uppdaterar api/package.json för extern Functions App ===" -ForegroundColor Cyan

if (-not (Test-Path ".\api")) {
    Write-Error "Katalogen '.\api' hittas inte. Är du i rätt repo? Finns api-mappen?"
    exit 1
}

# Här sätter vi upp ett säkert package.json som funkar i en extern Functions App
# OBS: Anpassa dependencies om du har fler paket, men vi behåller det du redan använt (tedious + azure SDKs)
@"
{
  "name": "api",
  "version": "1.0.0",
  "type": "commonjs",
  "engines": {
    "node": ">=18.0.0"
  },
  "dependencies": {
    "tedious": "^14.0.0",
    "@azure-rest/core-client": "1.1.0",
    "@azure/core-auth": "1.7.2",
    "@azure/core-client": "1.9.2",
    "@azure/core-http-compat": "2.2.0",
    "@azure/core-rest-pipeline": "1.15.0",
    "@azure/core-tracing": "1.2.0",
    "@azure/core-util": "1.8.0",
    "@azure/logger": "1.1.0"
  }
}
"@ | Set-Content -Path ".\api\package.json" -Encoding UTF8

Write-Host "Körde om api/package.json med Node 18+-kompatibla dependencies." -ForegroundColor Green

# --- 8. INSTALLERA DEPENDENCIES LOKALT (VALFRITT MEN BRA) ---

Write-Host "`n=== Installerar npm-dependencies för API lokalt ===" -ForegroundColor Cyan
Push-Location .\api
npm install --omit=dev
if ($LASTEXITCODE -ne 0) {
    Write-Host "npm install gav fel, men fortsätter. Kontrollera senare lokalt." -ForegroundColor Yellow
}
Pop-Location

# --- 9. SKAPA GITHUB ACTIONS WORKFLOW FÖR FUNCTIONS APP ---

Write-Host "`n=== Skapar GitHub Actions workflow för Azure Functions API ===" -ForegroundColor Cyan

$workflowDir = ".github\workflows"
if (-not (Test-Path $workflowDir)) {
    New-Item -ItemType Directory -Path $workflowDir | Out-Null
}

$functionsWorkflowPath = Join-Path $workflowDir "azure-functions-api.yml"

@"
name: Deploy Azure Functions API

on:
  push:
    branches:
      - main

env:
  AZURE_FUNCTIONAPP_NAME: '$functionApp'
  AZURE_FUNCTIONAPP_PACKAGE_PATH: 'api'
  NODE_VERSION: '20.x'

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: \${{ env.NODE_VERSION }}

      - name: Install dependencies
        working-directory: \${{ env.AZURE_FUNCTIONAPP_PACKAGE_PATH }}
        run: npm install --omit=dev

      - name: Build (if needed)
        working-directory: \${{ env.AZURE_FUNCTIONAPP_PACKAGE_PATH }}
        run: |
          if [ -f "build.sh" ]; then
            bash build.sh
          else
            echo "No build step for Functions."
          fi

      - name: Azure Functions Action
        uses: Azure/functions-action@v1
        with:
          app-name: \${{ env.AZURE_FUNCTIONAPP_NAME }}
          package: \${{ env.AZURE_FUNCTIONAPP_PACKAGE_PATH }}
          publish-profile: \${{ secrets.AZURE_FUNCTIONAPP_PUBLISH_PROFILE }}
"@ | Set-Content -Path $functionsWorkflowPath -Encoding UTF8

Write-Host "Skapade workflow: $functionsWorkflowPath" -ForegroundColor Green
Write-Host "GLÖM INTE: Lägg till secret 'AZURE_FUNCTIONAPP_PUBLISH_PROFILE' i GitHub repo settings (Deployment Center -> Get publish profile i Azure)." -ForegroundColor Yellow

# --- 10. UPPDATERA staticwebapp.config.json FÖR ATT PEKA PÅ EXTERN API ---

Write-Host "`n=== Uppdaterar staticwebapp.config.json för extern API-URL ===" -ForegroundColor Cyan

$staticConfigPath = ".\staticwebapp.config.json"
if (-not (Test-Path $staticConfigPath)) {
    Write-Host "staticwebapp.config.json fanns inte. Skapar en ny minimal." -ForegroundColor Yellow
    @"
{
  "navigationFallback": {
    "rewrite": "/index.html"
  },
  "responseOverrides": {
    "404": {
      "rewrite": "/index.html"
    }
  }
}
"@ | Set-Content -Path $staticConfigPath -Encoding UTF8
}

# Läs in nuvarande config och injicera api.uri
$configJson = Get-Content $staticConfigPath -Raw | ConvertFrom-Json

if (-not $configJson.api) {
    $configJson | Add-Member -MemberType NoteProperty -Name "api" -Value (@{} | ConvertTo-Json | ConvertFrom-Json)
}

# Om användaren angav full URL använder vi den, annars bygger vi en URL
if ($swaUrlOrName -like "http*") {
    $functionApiUrl = "https://$functionApp.azurewebsites.net"
} else {
    # Om användaren bara gav SWA-namnet, använder vi ändå Function App URL som extern API
    $functionApiUrl = "https://$functionApp.azurewebsites.net"
}

$configJson.api | Add-Member -MemberType NoteProperty -Name "uri" -Value $functionApiUrl -Force

$configJson | ConvertTo-Json -Depth 10 | Set-Content -Path $staticConfigPath -Encoding UTF8

Write-Host "Satte api.uri i staticwebapp.config.json till: $functionApiUrl" -ForegroundColor Green

# --- 11. VISA GIT STATUS OCH FÖRESLÅ COMMIT ---

Write-Host "`n=== Git status efter ändringar ===" -ForegroundColor Cyan
git status

Write-Host "`nFöreslagen commit:" -ForegroundColor Cyan
Write-Host "  git add api/package.json staticwebapp.config.json .github/workflows/azure-functions-api.yml" -ForegroundColor Yellow
Write-Host '  git commit -m "Move API to external Azure Functions App and connect SWA"' -ForegroundColor Yellow
Write-Host "  git push" -ForegroundColor Yellow

Write-Host "`n=== KLART (lokalt) ===" -ForegroundColor Cyan
Write-Host "1) Lägg till Azure publish profile i GitHub repo secrets som 'AZURE_FUNCTIONAPP_PUBLISH_PROFILE'." -ForegroundColor Yellow
Write-Host "2) Kör commit & push." -ForegroundColor Yellow
Write-Host "3) Vänta på två pipelines:" -ForegroundColor Yellow
Write-Host "   - SWA deploy (frontend)" -ForegroundColor Yellow
Write-Host "   - Azure Functions API deploy (nya workflow:t)" -ForegroundColor Yellow
Write-Host "`nNär de är klara ska SWA-anropen gå till din externa Functions App: $functionApiUrl" -ForegroundColor Green
