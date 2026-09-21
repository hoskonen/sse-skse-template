param()

$ErrorActionPreference = "Stop"

function Run-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Command $($Arguments -join ' ')"
    }
}

Write-Host ""
Write-Host "SKSE Plugin Template Setup"
Write-Host "=========================="
Write-Host ""

# Make sure the script is being run from the repository root.
if (-not (Test-Path "xmake.lua") -or -not (Test-Path ".gitmodules")) {
    throw "Run setup.ps1 from the repository root."
}

$xmake = Get-Content "xmake.lua" -Raw

if ($xmake -notmatch "__PROJECT_NAME__") {
    throw "This project appears to have already been initialized. __PROJECT_NAME__ was not found in xmake.lua."
}

$projectName = Read-Host "Project name"

if ([string]::IsNullOrWhiteSpace($projectName)) {
    throw "Project name cannot be empty."
}

$description = Read-Host "Description"

if ([string]::IsNullOrWhiteSpace($description)) {
    throw "Description cannot be empty."
}

Write-Host ""
Write-Host "Initializing project '$projectName'..."

# Update project metadata.
$xmake = $xmake.Replace("__PROJECT_NAME__", $projectName)
$xmake = $xmake.Replace("__PROJECT_DESCRIPTION__", $description)
Set-Content "xmake.lua" $xmake -NoNewline

# Replace the template README heading and introduction.
$readme = Get-Content "README.md" -Raw
$readme = $readme -replace '^# SKSE Plugin Template', "# $projectName"
Set-Content "README.md" $readme -NoNewline

# Make sure CommonLibSSE-NG and its nested dependencies are initialized.
Write-Host "Initializing Git submodules..."
Run-Command git submodule update --init --recursive

# Create a new root history while preserving the Git index and submodule gitlink.
Write-Host "Creating fresh Git history..."
Run-Command git checkout --orphan project-main

Run-Command git add -A
Run-Command git commit -m "Initial project setup"

# Remove the template branch and make the new root branch main.
$mainExists = git branch --list main

if ($mainExists) {
    Run-Command git branch -D main
}

Run-Command git branch -m main

# Remove the template repository as origin.
$origin = git remote get-url origin 2>$null

if ($LASTEXITCODE -eq 0 -and $origin) {
    Run-Command git remote remove origin
}

# Verify that CommonLib is still registered as a submodule/gitlink.
$submoduleEntry = git ls-files --stage lib/commonlibsse-ng

if (-not $submoduleEntry.StartsWith("160000")) {
    throw "CommonLibSSE-NG is not registered as a Git submodule after initialization."
}

# Configure the normal development build.
Write-Host "Configuring XMake..."
Run-Command xmake f -m releasedbg --skyrim_vr=n

Write-Host ""
Write-Host "Project initialized successfully."
Write-Host ""
Write-Host "Project:     $projectName"
Write-Host "Description: $description"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Create an empty GitHub repository."
Write-Host "  2. Add it as origin:"
Write-Host "       git remote add origin <repository-url>"
Write-Host "  3. Push:"
Write-Host "       git push -u origin main"
Write-Host "  4. Build:"
Write-Host "       xmake"
Write-Host ""