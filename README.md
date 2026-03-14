# OpenMetadata Flux Deployment

## Prerequisites

- `kubectl` configured with access to the target cluster
- The target namespace already exists
- A GitHub token with read access to the `encore-infrastructure` repository

## Folder Structure

```text
openmetadata/
├── app/
│   ├── base/                # Shared HelmRepository + HelmRelease
│   └── overlays/<env>/      # Environment-specific patches and secrets
└── clusters/<env>/          # Flux GitRepository + Kustomization per environment

deploy.sh                    # Bash deploy script
deploy.ps1                   # PowerShell deploy script
```

## Deploying OpenMetadata

### Bash

```bash
bash deploy.sh --env dev
```

### PowerShell

```powershell
.\deploy.ps1 -Environment dev
```

## What the script does

1. Reads the target namespace from `openmetadata/app/overlays/<env>/kustomization.yaml`
2. Checks whether that namespace already exists
3. Checks whether the Git auth secret exists and prompts for a GitHub token if missing
4. Applies the `GitRepository` source from `openmetadata/clusters/<env>/gitrepository.yaml`
5. Applies the Flux `Kustomization` from `openmetadata/clusters/<env>/openmetadata.yaml`

If the namespace does not exist, the script prints a message and exits. It does not create the namespace.

## Monitoring

```bash
kubectl get kustomization openmetadata -n cx-fluxed-openmetadata-encore-ns
kubectl get helmrelease -n cx-fluxed-openmetadata-encore-ns
kubectl get pods -n cx-fluxed-openmetadata-encore-ns
```

## Deploying to other environments

Create the corresponding overlay and cluster config, then run:

```bash
bash deploy.sh --env test
bash deploy.sh --env prod
```

## Cleanup

```bash
kubectl delete kustomization.kustomize.toolkit.fluxcd.io openmetadata -n cx-fluxed-openmetadata-encore-ns
kubectl delete gitrepository encore-infrastructure -n cx-fluxed-openmetadata-encore-ns
kubectl delete helmrelease openmetadata -n cx-fluxed-openmetadata-encore-ns
kubectl delete helmrepository open-metadata -n cx-fluxed-openmetadata-encore-ns
```

If a resource gets stuck deleting, remove its finalizer:

```bash
kubectl patch <resource-type> <name> -n cx-fluxed-openmetadata-encore-ns --type json -p "[{\"op\":\"remove\",\"path\":\"/metadata/finalizers\"}]"
```

Flux reconcile commands:
```bash
# fetch the Git repo again
flux reconcile source git encore-apps-openmetadata -n cx-fluxed-openmetadata-encore-ns
# tells kustomize-controller to rebuild and apply the overlay from the latest Git artifact     
flux reconcile kustomization openmetadata -n cx-fluxed-openmetadata-encore-ns         
# a specific healm release
flux reconcile helmrelease openmetadata-dependencies -n cx-fluxed-openmetadata-encore-ns                                                         
flux reconcile helmrelease openmetadata -n cx-fluxed-openmetadata-encore-ns     
```