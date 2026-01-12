param(
  [Parameter(Mandatory=$true)][string]$SwaName,
  [Parameter(Mandatory=$true)][string]$KeyName
)

$ErrorActionPreference = "Stop"

# Ensure logged in
try { az account show | Out-Null } catch { az login | Out-Null }

# Read secret without echo
$secure = Read-Host -Prompt "Paste value for $KeyName (input hidden)" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

# Set as SWA application setting (runtime env var for /api functions)
az staticwebapp appsettings set -n $SwaName --setting-names "$KeyName=$value" | Out-Null

Write-Host "DONE. Set app setting '$KeyName' on SWA '$SwaName'."
