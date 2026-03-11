param(
    [Parameter(Mandatory=$true)]
    [Alias("env")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppName = "openmetadata"

$OverlayDir = Join-Path $ScriptDir "openmetadata/app/overlays/$Environment"
$OverlayKustomizationFile = Join-Path $OverlayDir "kustomization.yaml"
$ClusterDir = Join-Path $ScriptDir "openmetadata/clusters/$Environment"
$GitRepoFile = Join-Path $ClusterDir "gitrepository.yaml"
$KustomizationFile = Join-Path $ClusterDir "$AppName.yaml"

foreach ($f in @($OverlayKustomizationFile, $GitRepoFile, $KustomizationFile)) {
    if (-not (Test-Path $f)) {
        Write-Error "Required file not found: $f"
        exit 1
    }
}

$NamespaceContent = Get-Content $OverlayKustomizationFile -Raw
if ($NamespaceContent -match 'namespace:\s*(\S+)') {
    $TargetNS = $Matches[1]
} else {
    Write-Error "Could not extract namespace from $OverlayKustomizationFile"
    exit 1
}

Write-Host "=== Deploying app: $AppName (env: $Environment) ==="
Write-Host "    Target namespace: $TargetNS"

$nsExists = kubectl get namespace $TargetNS --ignore-not-found -o name
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($nsExists)) {
    Write-Host "[OK] Namespace '$TargetNS' already exists"
} else {
    Write-Host "[..] Namespace '$TargetNS' not found"
    Write-Host "Create the namespace first, then rerun this script."
    exit 1
}

$GitRepoContent = Get-Content $GitRepoFile -Raw
if ($GitRepoContent -match 'secretRef:\s*\n\s*name:\s*(\S+)') {
    $SecretName = $Matches[1]
    $secretExists = kubectl get secret $SecretName -n $TargetNS --ignore-not-found -o name
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($secretExists)) {
        Write-Host "[OK] Git secret '$SecretName' already exists"
    } else {
        Write-Host "[..] Git secret '$SecretName' not found in namespace '$TargetNS'"
        $GhToken = Read-Host "     Enter GitHub token"
        kubectl create secret generic $SecretName `
            --namespace $TargetNS `
            --from-literal=username=git `
            --from-literal=password=$GhToken
        if ($LASTEXITCODE -ne 0) { exit 1 }
        Write-Host "[OK] Git secret '$SecretName' created"
    }
}

Write-Host "[..] Applying GitRepository..."
kubectl apply -f $GitRepoFile
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "[OK] GitRepository applied"

Write-Host "[..] Applying Flux Kustomization..."
kubectl apply -f $KustomizationFile
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "[OK] Flux Kustomization applied"

Write-Host ""
Write-Host "=== Deployment initiated for '$AppName' (env: $Environment) ==="
Write-Host "    Monitor with:"
Write-Host "    kubectl get kustomization $AppName -n $TargetNS"
Write-Host "    kubectl get helmrelease -n $TargetNS"
