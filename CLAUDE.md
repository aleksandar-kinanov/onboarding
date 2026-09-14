# CLAUDE.md

## Project overview

Local onboarding/practice environment for a Principal DevOps role: a
`kind`-based platform stack used to learn/demo GitOps-managed identity and
event streaming. ArgoCD deploys everything else — Keycloak, Crossplane (+
its Keycloak provider), Strimzi Kafka, and a small Python Kafka
producer/consumer app — driven declaratively from this repo, not by hand
via UIs/APIs.

This is a learning sandbox, not a production repo — favor clarity and
working examples over hardening. See `README.md` for setup/usage; this
file is oriented at how the repo is put together and how to work in it.

## Stack

- Cluster: `kind` (local Kubernetes), brought up via `./setup.sh up`
- GitOps/delivery: ArgoCD, self-managing (see "How ArgoCD bootstraps
  itself" below)
- Identity: Keycloak, configured via Crossplane + its Keycloak provider
  (Realm/Client/User/Role/Group claims, plus a custom `KeycloakUser` XR)
- Event streaming: Strimzi Kafka Operator (KRaft mode), with a demo
  `KafkaTopic`/`KafkaUser` and a small Python producer/consumer app
  (`apps/python-kafka-test/`) running in-cluster against it
- Infra-as-code for K8s resources: Crossplane

## Milestones — all complete; extend rather than re-derive

1. ✅ Bring up a `kind` cluster
2. ✅ Install ArgoCD into the cluster
3. ✅ Use ArgoCD to deploy Keycloak
4. ✅ Use ArgoCD to deploy Crossplane + the Keycloak provider for Crossplane
5. ✅ Author Crossplane manifests (via ArgoCD) to create a Keycloak realm
6. ✅ Extend those manifests to configure clients/applications, users,
   roles, and groups in that realm
7. ✅ Verify end-to-end by logging into Keycloak and confirming the realm,
   clients, and users match the manifests
8. ✅ Deploy Strimzi and a Kafka cluster (KRaft, SCRAM-SHA-512 auth, one
   plaintext + one TLS listener), with a demo `KafkaTopic`/`KafkaUser`
9. ✅ Build a Python producer/consumer app, load its image into `kind`
   directly (no registry), and deploy it as its own ArgoCD app with its
   own `KafkaTopic`/`KafkaUser`
10. ✅ Make ArgoCD bootstrap itself (root Application) and script the whole
    bring-up/teardown (`setup.sh`)

Possible next steps if continuing this sandbox: a Crossplane composition
for Kafka topics/users (mirroring the `KeycloakUser` XR pattern), an
ingress controller so apps are reachable without `kubectl port-forward`,
or wiring Keycloak as an OIDC identity source for ArgoCD itself.

## How ArgoCD bootstraps itself

`setup.sh up` is the only time anything is applied by hand, and it only
ever applies one manifest: `argocd/root-application.yaml`. That
Application's source is the `argocd/` folder itself (including its own
manifest), so it manages `argocd/applicationset.yaml` — and itself — the
same way any other ArgoCD-managed resource is managed. The
ApplicationSet's git-directory generator then creates one Application per
`apps/*` folder. Net effect: after the one bootstrap apply, every future
change anywhere in this repo (including to the bootstrap chain itself)
flows through normal ArgoCD sync — no more manual `kubectl`/`helm`.

## Repo structure

```
kind/config.yaml               kind cluster config
setup.sh                       up / down / endpoints — see README.md
argocd/root-application.yaml   Bootstrap Application (applied once by setup.sh);
                                manages this argocd/ folder, including itself
argocd/applicationset.yaml     Generates one Application per apps/* folder
argocd/values-tls-certs.yaml   Helm values for ArgoCD's own install: proxy CA
                                trust for both its git/Helm-index HTTP client
                                (configs.tls.certificates) and its repo-server
                                container's own OS trust store (an initContainer,
                                needed for OCI Helm chart deps like Strimzi's) —
                                applied via `helm upgrade`, not ArgoCD-synced
apps/<name>/                   One self-contained app per folder (Helm chart or
                                Kustomize build); folder name = Application name
                                = destination namespace. Add a folder, it's
                                deployed automatically.
```

Apps:

- `apps/keycloak/` — umbrella Helm chart: codecentric's keycloakx chart +
  local templates for the Crossplane Provider/ProviderConfig, provider
  credentials Secret, and Realm/Client/User/Role/Group claims (plus an
  example custom `KeycloakUser` XRD/Composition).
- `apps/crossplane-system/` — Crossplane core install.
- `apps/strimzi/` — Strimzi Kafka Operator (OCI Helm chart dependency from
  `quay.io`), a KRaft `Kafka`/`KafkaNodePool`, and a demo
  `KafkaTopic`/`KafkaUser`.
- `apps/python-kafka-test/` — Kustomize (no Helm): a `Deployment` running
  an image built from the sibling `~/projects/python-kafka-test` repo and
  `kind load`ed (not pulled from a registry), plus its own
  `KafkaTopic`/`KafkaUser` and a `ConfigMap` wired into the Pod's env via
  `envFrom` + Kustomize `replacements` (so the topic/username come from the
  `KafkaTopic`/`KafkaUser` resource names, not duplicated literals).
- `apps/coraza-haproxy/` — HAProxy + Coraza SPOA WAF demo.
- `apps/monitoring/`, `apps/alloy/` — Grafana + Loki, fed by Alloy shipping
  `coraza-haproxy`'s logs.
- `apps/nginx/` — Helm chart base extended via Kustomize, demo backend.

Each Helm-based `apps/*` folder mixes an external chart dependency with its
own `templates/`. `helm dependency build`/`Chart.lock`/`charts/` are
gitignored — ArgoCD's repo-server resolves the dependency itself at sync
time.

## Common commands

```bash
# Whole sandbox
./setup.sh up         # kind cluster -> ArgoCD -> GitHub connection -> root Application
./setup.sh endpoints  # print every app's URL/credentials/port-forward command
./setup.sh down       # deletes the kind cluster

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

# Strimzi / Kafka
kubectl get kafka,kafkatopic,kafkauser -n strimzi
```

## Conventions / safety rules

- Everything (Keycloak realms/clients/users, Kafka topics/users, app
  Deployments) is created via manifests synced by ArgoCD, not by clicking
  in a UI or `kubectl apply`ing by hand — that's the point of the exercise.
- Never `kubectl apply`/`kubectl edit` a resource ArgoCD manages — change
  the source manifest and let sync apply it, or the next auto-sync will
  silently revert the change.
- Any resource whose CRD comes from a Crossplane provider (e.g. everything
  under `keycloak.crossplane.io`/`*.keycloak.crossplane.io`) needs the
  annotation `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true`.
  Without it, ArgoCD refuses to sync *any* resource in that Application on
  a fresh cluster — including the `Provider` itself — because the CRD
  doesn't exist until the provider package finishes installing, which
  deadlocks bootstrap. Apply the same annotation to any new
  provider-backed resource kind added later.
- Treat `kind delete cluster` and `argocd app sync --force` as fine to run
  freely here (throwaway local sandbox) — no prod-style confirmation
  needed within this repo.
- Don't commit real secrets even though this is local-only; use
  placeholder/test credentials (Keycloak admin, client secrets, etc.).
