# PowerShell script to create a GitHub release with Windows binary (using godror/CGO)
# Usage: .\create-release-windows.ps1 v1.0.0

param(
    [Parameter(Mandatory=$true)]
    [string]$Version
)

# Exit on any error
$ErrorActionPreference = "Stop"

Write-Host "Starting Windows release build for version $Version" -ForegroundColor Green

# Check if release already exists and delete it
Write-Host "Checking for existing release..." -ForegroundColor Yellow
try {
    gh release view $Version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Release $Version already exists. Deleting..." -ForegroundColor Yellow
        gh release delete $Version --yes
        Write-Host "Existing release deleted." -ForegroundColor Green
    }
} catch {
    Write-Host "No existing release found." -ForegroundColor Gray
}

# Check if tag already exists and delete it
Write-Host "Checking for existing tag..." -ForegroundColor Yellow
try {
    git rev-parse $Version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Tag $Version already exists. Deleting..." -ForegroundColor Yellow
        git tag -d $Version
        git push origin ":refs/tags/$Version" 2>$null
        Write-Host "Existing tag deleted." -ForegroundColor Green
    }
} catch {
    Write-Host "No existing tag found." -ForegroundColor Gray
}

# Build Windows x64 binary with godror
Write-Host "`nBuilding Windows x64 binary with godror for $Version..." -ForegroundColor Cyan
$env:GOOS = "windows"
$env:GOARCH = "amd64"
$env:CGO_ENABLED = "1"

go build -tags godror -o oracledb_exporter-windows-amd64.exe main.go

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Build successful!" -ForegroundColor Green

# Create zip archive
Write-Host "Creating zip archive..." -ForegroundColor Cyan
Compress-Archive -Path oracledb_exporter-windows-amd64.exe -DestinationPath oracledb_exporter-windows-amd64.zip -Force
Write-Host "Archive created." -ForegroundColor Green

# Create git tag
Write-Host "`nCreating git tag..." -ForegroundColor Cyan
git tag $Version
git push origin $Version

# Create GitHub release
Write-Host "Creating GitHub release..." -ForegroundColor Cyan
gh release create $Version `
    oracledb_exporter-windows-amd64.zip `
    --title $Version `
    --generate-notes

Write-Host "`nDone! Release created at: https://github.com/davidbudac/oracle-db-appdev-monitoring/releases/tag/$Version" -ForegroundColor Green

# Cleanup
Write-Host "`nCleaning up..." -ForegroundColor Yellow
Remove-Item oracledb_exporter-windows-amd64.exe -ErrorAction SilentlyContinue
Remove-Item oracledb_exporter-windows-amd64.zip -ErrorAction SilentlyContinue
Write-Host "Cleanup complete." -ForegroundColor Green
