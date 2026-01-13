Write-Host 'Återställer backup...' -ForegroundColor Yellow
Copy-Item -Recurse -Force '.\backup-20260113-011555\api' .\api
Copy-Item -Force '.\backup-20260113-011555\staticwebapp.config.json' .\staticwebapp.config.json -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force '.\backup-20260113-011555\workflows' .\.github\workflows -ErrorAction SilentlyContinue
Write-Host 'Rollback klar.' -ForegroundColor Green
