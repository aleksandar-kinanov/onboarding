# CLAUDE.md

## Project overview

Local onboarding/practice environment for a Principal DevOps role. Goal is
to stand up a local platform stack on `kind` and use it to learn/demo
GitOps-managed identity: ArgoCD deploying Keycloak, Crossplane, and a
Crossplane Keycloak provider, then testing realm creation and
application/user configuration in Keycloak driven declaratively (not via
the Keycloak UI/API by hand).

This is a learning sandbox, not a production repo — favor clarity and
working examples over hardening.

## Stack

- Cluster: `kind` (local Kubernetes)
- GitOps/delivery: ArgoCD
- Identity: Keycloak (deployed via ArgoCD)
- Infra-as-code for K8s resources: Crossplane + a Keycloak provider for
  Crossplane, itself managed via ArgoCD (Crossplane `Provider`/
  `ProviderConfig` + Keycloak XRDs/claims for realms, clients, users)

## Milestones (current focus first)

1. Bring up a `kind` cluster
2. Install ArgoCD into the cluster
3. Use ArgoCD to deploy Keycloak
4. Use ArgoCD to deploy Crossplane + the Keycloak provider for Crossplane
5. Author Crossplane manifests (via ArgoCD) to create a Keycloak realm
6. Extend those manifests to configure clients/applications and users in
   that realm
7. Verify end-to-end by logging into Keycloak and confirming the realm,
   clients, and users match the manifests

## Repo structure

```
kind/                        kind cluster config
argocd/applicationset.yaml   ApplicationSet (git directory generator): one
                              Application per apps/* folder, folder name
                              used as both Application name and namespace.
                              The one manifest still applied by hand once.
argocd/values-tls-certs.yaml Helm values for ArgoCD's own install (repo-server
                              CA trust for this network's TLS-inspecting
                              proxy) — applied via `helm upgrade`, not synced
                              by ArgoCD, since ArgoCD can't bootstrap itself.
apps/keycloak/                Umbrella Helm chart: depends on codecentric's
                              keycloakx chart, plus local templates/ for the
                              Crossplane Provider, ProviderConfig, provider
                              credentials Secret, and Realm/Client/User claims.
                              Everything keycloak-related lives here, in the
                              `keycloak` namespace.
apps/crossplane-system/       Umbrella Helm chart: depends on the crossplane
                              chart, plus a local template for the registry
                              CA bundle ConfigMap. Namespace `crossplane-system`.
```

Each `apps/*` folder is a self-contained Helm chart (`Chart.yaml` + `values.yaml`
+ `templates/`) that mixes an external chart dependency with our own local
manifests. `helm dependency build`/`Chart.lock`/`charts/` are gitignored —
ArgoCD's repo-server resolves the dependency itself at sync time.

Adding a new app = add a new `apps/<name>/` folder with a `Chart.yaml`; the
ApplicationSet picks it up automatically and deploys it into a `<name>`
namespace, no new Application manifest needed.

## Common commands

```bash
# Cluster
kind create cluster --name onboarding --config kind/config.yaml
kind delete cluster --name onboarding

kubectl get nodes
kubectl -n argocd get applications

# ArgoCD
argocd app get <app-name>
argocd app diff <app-name>
argocd app sync <app-name>

# Crossplane
kubectl get providers.pkg.crossplane.io
kubectl get providerconfigs
kubectl get managed   # all Crossplane managed resources across the Keycloak provider's GVKs
```

## Conventions / safety rules

- Everything Keycloak-side (realms, clients, users) should be created via
  Crossplane manifests synced by ArgoCD, not by clicking in the Keycloak
  admin console — the point of this exercise is GitOps-managed identity.
- Never `kubectl apply`/`kubectl edit` a resource ArgoCD manages — change
  the source manifest and let sync apply it.
- Treat `kind delete cluster` and `argocd app sync --force` as fine to run
  freely here (throwaway local sandbox) — no prod-style confirmation
  needed within this repo.
- Don't commit real secrets even though this is local-only; use
  placeholder/test credentials for Keycloak admin and any client secrets.
