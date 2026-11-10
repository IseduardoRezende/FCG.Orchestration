param(
    [string]$ClusterName = "fcg"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$images = @("fcg-users-api", "fcg-catalog-api", "fcg-payments-api", "fcg-notifications-api")

Write-Host "1) Building the service images with Docker Compose" -ForegroundColor Cyan
docker compose -f "$root/docker-compose.yml" build
if ($LASTEXITCODE -ne 0) { throw "docker compose build failed." }

Write-Host "2) Creating the Kind cluster '$ClusterName' (if needed)" -ForegroundColor Cyan
if (-not (kind get clusters | Select-String -Pattern "^$ClusterName$" -Quiet)) {
    kind create cluster --name $ClusterName
    if ($LASTEXITCODE -ne 0) { throw "kind create cluster failed." }
}

Write-Host "3) Loading the local images into the cluster" -ForegroundColor Cyan
foreach ($image in $images) {
    kind load docker-image "${image}:latest" --name $ClusterName
    if ($LASTEXITCODE -ne 0) { throw "kind load docker-image $image failed." }
}

Write-Host "4) Applying the manifests (infrastructure + 4 microservices)" -ForegroundColor Cyan
kubectl apply -k "$root/k8s"
if ($LASTEXITCODE -ne 0) { throw "kubectl apply failed." }

Write-Host "5) Waiting for the deployments" -ForegroundColor Cyan
kubectl -n fcg rollout status deployment/postgres --timeout=180s
kubectl -n fcg rollout status deployment/rabbitmq --timeout=180s
foreach ($image in $images) {
    kubectl -n fcg rollout status "deployment/$image" --timeout=300s
}

kubectl -n fcg get pods
