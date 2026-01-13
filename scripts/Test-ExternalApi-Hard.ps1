Write-Host "=== HARD-CODED TEST SUPER SCRIPT ===" -ForegroundColor Cyan

# Hard-coded values
$tenantId = "4a48b9bf-1b63-4bc4-b36d-c7aea033944b"
$subscriptionId = "29ef583c-6cc5-418a-a80d-1b492a8cbc70"
$resourceGroup = "singel-generator-test-rg"
$location = "westeurope"
$functionApp = "singel-generator-api-test"
$storageAccount = "singelgenapiteststore"

Write-Host "`nLogging out and clearing Azure CLI context..." -ForegroundColor Yellow
az logout
az account clear
az cache purge

Write-Host "`nLogging in to correct tenant..." -ForegroundColor Yellow
az login --tenant $tenantId --output none

Write-Host "`nSetting subscription..." -ForegroundColor Yellow
az account set --subscription $subscriptionId

Write-Host "`nConfiguring ARM defaults..." -ForegroundColor Yellow
az configure --defaults tenant=$tenantId subscription=$subscriptionId

Write-Host "`nValidating ARM access..." -ForegroundColor Yellow
$groups = az group list --output json
if ($LASTEXITCODE -ne 0) {
    Write-Error "ARM access failed. Azure CLI is still in wrong tenant. Stopping."
    exit 1
}

Write-Host "ARM access OK." -ForegroundColor Green

Write-Host "`nEnsuring Resource Group..." -ForegroundColor Yellow
az group create --name $resourceGroup --location $location --output none

Write-Host "`nEnsuring Storage Account..." -ForegroundColor Yellow
az storage account create `
    --name $storageAccount `
    --resource-group $resourceGroup `
    --location $location `
    --sku Standard_LRS `
    --kind StorageV2 `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create storage account. Stopping."
    exit 1
}

Write-Host "Storage account OK." -ForegroundColor Green

Write-Host "`nCreating Function App..." -ForegroundColor Yellow
az functionapp create `
    --name $functionApp `
    --resource-group $resourceGroup `
    --storage-account $storageAccount `
    --consumption-plan-location $location `
    --runtime node `
    --runtime-version 20 `
    --functions-version 4 `
    --os-type Linux `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Function App. Stopping."
    exit 1
}

Write-Host "Function App OK." -ForegroundColor Green

Write-Host "`nDeploying API..." -ForegroundColor Yellow
Push-Location .\api
func azure functionapp publish $functionApp
Pop-Location

Write-Host "`n=== TEST API READY ===" -ForegroundColor Cyan
$baseUrl = "https://$functionApp.azurewebsites.net/api"
Write-Host "Test endpoints:" -ForegroundColor Yellow
Write-Host "$baseUrl/Ping"
Write-Host "$baseUrl/GetProfiles"
Write-Host "$baseUrl/SubmitProfile"
Write-Host "$baseUrl/MatchNow"
Write-Host "$baseUrl/MatchRespond"
Write-Host "$baseUrl/Respond"
Write-Host "$baseUrl/IssueOptInTokens"
Write-Host "$baseUrl/ExpireMatches"
Write-Host "$baseUrl/GetMatchContacts"
Write-Host "$baseUrl/admin"
Write-Host "$baseUrl/BlockPair"
