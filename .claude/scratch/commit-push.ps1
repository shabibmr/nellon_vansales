param(
    [string]$Message = ""
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

if (-not $Message) {
    $Message = "Update $timestamp"
}

Write-Host "Staging all changes..." -ForegroundColor Cyan
git add -A

Write-Host "Committing..." -ForegroundColor Cyan
git commit -m $Message

if ($LASTEXITCODE -ne 0) {
    Write-Error "Commit failed."
    exit 1
}

Write-Host "Pushing to origin..." -ForegroundColor Cyan
git push

if ($LASTEXITCODE -ne 0) {
    Write-Error "Push failed."
    exit 1
}

Write-Host "Done." -ForegroundColor Green
