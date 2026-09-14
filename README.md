# argocd-onboarding

Local, throwaway `kind` sandbox for learning GitOps-managed identity and
platform tooling: ArgoCD deploying Keycloak, Crossplane (+ its Keycloak
provider), and Strimzi Kafka, all driven declaratively from this repo.

## Prerequisites

- `kind`, `kubectl`, `helm`, `docker`, `yq` on your PATH
- An SSH keypair whose **public** half is added as a read-only **Deploy key**
  on this GitHub repo (`aleksandar-kinanov/onboarding`). By default the
  script uses `~/.ssh/id_ed25519`; point it elsewhere with `SSH_KEY_PATH`.
- The sibling `python-kafka-test` repo checked out locally (default
  `~/projects/python-kafka-test`; override with `PYTHON_KAFKA_TEST_DIR`) —
  its image is built and `kind load`ed by `setup.sh`, not pulled from a
  registry. If it's not found, that step is skipped.
- If you're behind a TLS-inspecting proxy (e.g. Zscaler), its root CA is
  already baked into `argocd/values-tls-certs.yaml`, and `setup.sh` also:
  - installs it into each kind node's OS trust store, so containerd can
    pull images through the proxy;
  - trusts it inside the ArgoCD repo-server's own container filesystem
    (via an initContainer), so `helm dependency build` can resolve OCI
    Helm charts (e.g. `apps/strimzi`'s `oci://quay.io` dependency) through
    the proxy too — the app-level cert config alone only covers ArgoCD's
    own git/Helm-index HTTP client, not subprocess Helm/OCI calls.
  Add a new hostname key to `argocd/values-tls-certs.yaml` (same cert
  value) if a later app pulls from a new external host.

## Quick start

```bash
./setup.sh up     # kind cluster -> ArgoCD -> GitHub connection -> root Application
./setup.sh down   # deletes the kind cluster (everything in it goes with it)
```

`up` is the only time anything gets applied by hand. It:

1. Creates the `kind` cluster (`kind/config.yaml`).
2. Trusts the proxy CA on every kind node.
3. Builds the `python-kafka-test` image and `kind load`s it in.
4. Installs ArgoCD via Helm (`argo/argo-cd`, with the proxy CA trust from
   `argocd/values-tls-certs.yaml`).
5. Creates the ArgoCD repository credentials Secret (SSH deploy key) so
   ArgoCD can pull this repo.
6. Applies `argocd/root-application.yaml` once.

From there, ArgoCD owns itself: the root `Application` manages
`argocd/applicationset.yaml`, whose git-directory generator creates one
`Application` per `apps/*` folder. Any future change to the ApplicationSet,
the root Application, or any app under `apps/` is picked up by ArgoCD's
normal sync — no more manual `kubectl apply`.

Get the ArgoCD admin password and UI at the end of `setup.sh up`'s output, or
any time via:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argocd-server 8443:443   # https://localhost:8443
```

## Repo structure

```
kind/config.yaml              kind cluster config
setup.sh                      up/down: bring the whole sandbox up or tear it down
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

Notable apps:

- `apps/keycloak/` — Keycloak (codecentric keycloakx chart) + Crossplane
  Keycloak provider + realm/client/user claims.
- `apps/crossplane-system/` — Crossplane core install.
- `apps/strimzi/` — Strimzi Kafka Operator, a KRaft `Kafka`/`KafkaNodePool`,
  and a demo `KafkaTopic`/`KafkaUser`.
- `apps/python-kafka-test/` — a small Python producer/consumer app (image
  built from the sibling `python-kafka-test` repo, loaded into `kind` with
  `kind load docker-image`, not pulled from a registry) with its own
  `KafkaTopic`/`KafkaUser`, wired into the Pod's env via Kustomize.
- `apps/coraza-haproxy/`, `apps/monitoring/`, `apps/alloy/`, `apps/nginx/` —
  a WAF demo (HAProxy + Coraza SPOA) with logs shipped through Alloy into
  Loki/Grafana.

## Conventions

- Everything is managed via Git + ArgoCD sync. Never `kubectl apply`/`edit`
  a resource ArgoCD manages — change the source manifest and let sync apply
  it, or the next auto-sync will silently revert your change.
- This is a local, throwaway sandbox: `kind delete cluster` and
  `argocd app sync --force` are fine to run freely here, no confirmation
  needed.
- Don't commit real secrets, even though this never leaves your machine —
  use placeholder/test credentials.
