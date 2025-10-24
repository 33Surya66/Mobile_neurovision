<#
Deploy helper for NeuroVision backend (PowerShell)

Usage (local run):
  PS> .\deploy.ps1 -Action build-and-run

Usage (build only):
  PS> .\deploy.ps1 -Action build

Usage (push to Docker Hub):
  PS> $env:DOCKER_USER='yourhubuser'; $env:DOCKER_REPO='yourrepo/neurovision-backend'; .\deploy.ps1 -Action push

Notes:
- Requires Docker installed and running.
- Uses `backend/.env` for runtime env vars when running locally.
- Pushing requires you to be logged in to Docker (docker login).
#>
param(
    [ValidateSet('build','build-and-run','push')]
    [string]$Action = 'build-and-run',

    # Optional image name override
    [string]$ImageName = 'neurovision-backend:local',

    # Optional Docker Hub repo (user/repo). If provided and Action=push will tag and push to it.
    [string]$DockerHubRepo = $env:DOCKER_REPO
)

function Check-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error "Docker CLI not found. Install Docker Desktop and ensure 'docker' is on PATH."
        exit 1
    }
}

function Build-Image {
    Write-Host "Building Docker image: $ImageName" -ForegroundColor Cyan
    Push-Location -Path $PSScriptRoot
    docker build -t $ImageName .
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { throw "docker build failed (exit $code)" }
}

function Run-Image {
    Write-Host "Running Docker image (port 5000 -> container 5000)" -ForegroundColor Cyan
    # Use --env-file to load environment variables from backend/.env
    docker run --rm -it -p 5000:5000 --env-file .\.env $ImageName
}

function Push-Image {
    param($Repo)
    if (-not $Repo) { throw "DockerHub repo not specified. Set env DOCKER_REPO or pass -DockerHubRepo 'user/repo'" }
    $tag = "$Repo:latest"
    Write-Host "Tagging $ImageName -> $tag" -ForegroundColor Cyan
    docker tag $ImageName $tag
    Write-Host "Pushing $tag" -ForegroundColor Cyan
    docker push $tag
}

# --- main
Check-Docker
if ($Action -eq 'build' -or $Action -eq 'build-and-run') {
    Build-Image
}
if ($Action -eq 'build-and-run') {
    Run-Image
} elseif ($Action -eq 'push') {
    Push-Image -Repo $DockerHubRepo
}
