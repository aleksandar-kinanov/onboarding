# argocd-onboarding

Local, throwaway `kind` sandbox for learning GitOps-managed platform
tooling. ArgoCD deploys everything below, all driven declaratively from
this repo (see "Apps" further down for the full detail on each):

- Crossplane, its Keycloak provider, and Keycloak itself (realm/client/
  user/role/group claims, plus a custom `KeycloakUser` XRD/Composition)
- Strimzi Kafka, and a Python producer/consumer app running against it
- HAProxy + Coraza SPOA WAF demo, fronting `httpbin`
- Grafana + Loki, fed by Alloy shipping the WAF demo's logs
- nginx, exercising Kustomize's Helm chart inflation, patches,
  `replacements`, and a component together

## Prerequisites

- `kind`, `kubectl`, `helm`, `docker`, `yq` on your PATH
- An SSH keypair whose **public** half is added as a read-only **Deploy key**
  on this GitHub repo (`aleksandar-kinanov/onboarding`). Defaults to
  `~/.ssh/id_ed25519`; override with `SSH_KEY_PATH`.

## Quick start

```bash
git clone git@github.com:aleksandar-kinanov/onboarding.git && cd onboarding
./setup.sh up          # kind cluster -> ArgoCD -> GitHub connection -> root Application
./setup.sh endpoints    # print every app's URL/credentials and port-forward command
./setup.sh down         # deletes the kind cluster (everything in it goes with it)
```

`up` is the only time anything is applied by hand:

- Creates the `kind` cluster
- Builds and `kind load`s the `python-kafka-test` image
- Installs ArgoCD
- Wires up the GitHub repo credentials
- Applies `argocd/root-application.yaml` once

From there, ArgoCD owns the rest — the root Application manages
`argocd/applicationset.yaml`, which creates one Application per `apps/*`
folder. Any future change anywhere in the repo is picked up by ArgoCD's
normal sync, no more manual `kubectl`/`helm`.

Every app is ClusterIP-only, so `endpoints` is the way in — it prints the
`kubectl port-forward` command, local URL, and login for each one.

## Repo structure

```
kind/config.yaml              kind cluster config
setup.sh                      up / down / endpoints
argocd/root-application.yaml  Bootstrap Application (applied once by setup.sh);
                               manages this argocd/ folder, including itself
argocd/applicationset.yaml    Generates one Application per apps/* folder
argocd/values-tls-certs.yaml  Helm values for ArgoCD's own install (proxy CA
                               trust) — applied via `helm upgrade`, not synced
apps/<name>/                  One self-contained app per folder (Helm chart or
                               Kustomize build); folder name = Application name
                               = destination namespace. Add a folder, it's
                               deployed automatically.
```

Apps:

- `apps/keycloak/`
  - Keycloak (codecentric keycloakx chart)
  - Crossplane Keycloak provider
  - Realm/client/user/role/group claims
  - Example custom `KeycloakUser` XRD + Composition (Crossplane
    composite resource), abstracting over the raw User/Roles claims
- `apps/crossplane-system/`
  - Crossplane core install
- `apps/strimzi/`
  - Strimzi Kafka Operator
  - A KRaft `Kafka`/`KafkaNodePool`
  - A demo `KafkaTopic`/`KafkaUser`
- `apps/python-kafka-test/`
  - Small Python producer/consumer app (`app/`: source + Dockerfile,
    built and `kind load`ed by `setup.sh`, not pulled from a registry)
  - Its own `KafkaTopic`/`KafkaUser`
  - A `ConfigMap` wiring both into the Pod's env via Kustomize
- `apps/coraza-haproxy/`
  - HAProxy + Coraza SPOA WAF demo
  - `httpbin` backend behind it
- `apps/monitoring/`
  - Grafana, with a Loki datasource and a dashboard auto-provisioned
    from a ConfigMap (no manual UI import)
  - Loki, single-tenant, storing `coraza-haproxy`'s logs
- `apps/alloy/`
  - Alloy, shipping `coraza-haproxy`'s logs into Loki
- `apps/nginx/`
  - Demo backend exercising Kustomize fully: Helm chart inflation
    (`helmCharts:`), a `configMapGenerator`, patches, `replacements`,
    and a component

## Conventions

- Everything is managed via Git + ArgoCD sync. Never `kubectl apply`/`edit`
  a resource ArgoCD manages — change the source manifest and let sync apply
  it, or the next auto-sync will silently revert your change.
- This is a local, throwaway sandbox: `kind delete cluster` and
  `argocd app sync --force` are fine to run freely here, no confirmation
  needed.
- Don't commit real secrets, even though this never leaves your machine —
  use placeholder/test credentials.
