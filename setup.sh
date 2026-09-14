#!/usr/bin/env bash
# Brings up or tears down the entire local onboarding sandbox:
#   up        - kind cluster -> ArgoCD (with the Zscaler CA trust) -> GitHub
#               repo connection -> root Application (which takes over from
#               here), then prints every app's endpoint/port-forward command.
#   down      - deletes the kind cluster (everything in it goes with it).
#   endpoints - reprints the endpoint/port-forward list any time, without
#               re-running the rest of `up`.
#
# After `up`, ArgoCD owns the rest: the root Application manages
# argocd/applicationset.yaml, which in turn creates one Application per
# apps/* folder. No further manual kubectl/helm steps are needed.
set -euo pipefail

CLUSTER_NAME="onboarding"
ARGOCD_NAMESPACE="argocd"
GIT_REPO_URL="git@github.com:aleksandar-kinanov/onboarding.git"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_KAFKA_TEST_DIR="$SCRIPT_DIR/apps/python-kafka-test/app"
PYTHON_KAFKA_TEST_IMAGE="ghcr.io/aleksandar-kinanov/onboarding/python-kafka-test:latest"

usage() {
  echo "Usage: $0 {up|down|endpoints}" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

# Blocks `up` here until ArgoCD is confirmed up, instead of trusting a single
# rollout-status call: polls up to 15 times, 5s apart (75s max), and aborts
# the whole run if it never comes up rather than pressing on regardless.
wait_for_argocd() {
  local max_retries=15
  local delay=5
  local attempt=1
  while [[ "$attempt" -le "$max_retries" ]]; do
    if kubectl -n "$ARGOCD_NAMESPACE" get deployment argocd-server \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -qx '[1-9][0-9]*'; then
      echo "==> ArgoCD is up and running"
      return 0
    fi
    echo "  ArgoCD not ready yet (attempt $attempt/$max_retries), retrying in ${delay}s..."
    sleep "$delay"
    attempt=$((attempt + 1))
  done
  echo "ArgoCD did not become ready after $((max_retries * delay))s - aborting." >&2
  exit 1
}

print_argocd_access() {
  local argocd_pw
  argocd_pw="$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)"
  cat <<EOF
ArgoCD UI
  kubectl -n $ARGOCD_NAMESPACE port-forward svc/argocd-server 8443:443
  https://localhost:8443  user: admin  password: ${argocd_pw:-<not found - is ArgoCD installed?>}
EOF
}

up() {
  for cmd in kind kubectl helm docker yq; do require_cmd "$cmd"; done

  echo "==> Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --name "$CLUSTER_NAME" --config "$SCRIPT_DIR/kind/config.yaml"

  echo "==> Trusting the Zscaler root CA on kind nodes (containerd image pulls)"
  # kind nodes run their own containerd with its own OS trust store, separate
  # from the host Docker daemon, so this network's TLS-inspecting proxy needs
  # to be trusted there too or image pulls fail with x509 errors. Reuses the
  # same cert already in argocd/values-tls-certs.yaml as the single source.
  local ca_cert_tmp
  ca_cert_tmp="$(mktemp)"
  yq '.configs.tls.certificates."codecentric.github.io"' "$SCRIPT_DIR/argocd/values-tls-certs.yaml" > "$ca_cert_tmp"
  for node in $(kind get nodes --name "$CLUSTER_NAME"); do
    docker cp "$ca_cert_tmp" "$node:/usr/local/share/ca-certificates/zscaler-root-ca.crt"
    docker exec "$node" update-ca-certificates
    docker exec "$node" systemctl restart containerd
  done
  rm -f "$ca_cert_tmp"

  echo "==> Building the python-kafka-test image and loading it into kind"
  # This image is loaded straight into kind's containerd (not pulled from
  # ghcr.io), so it must exist locally before ArgoCD schedules its Pod, or
  # the Deployment's imagePullPolicy: IfNotPresent will try (and fail) to
  # pull it from the registry instead.
  docker build -t "$PYTHON_KAFKA_TEST_IMAGE" "$PYTHON_KAFKA_TEST_DIR"
  kind load docker-image "$PYTHON_KAFKA_TEST_IMAGE" --name "$CLUSTER_NAME"

  echo "==> Adding/updating the argo-helm repo"
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
  helm repo update argo >/dev/null

  echo "==> Installing ArgoCD (Zscaler root CA trust from argocd/values-tls-certs.yaml)"
  kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install argocd argo/argo-cd \
    -n "$ARGOCD_NAMESPACE" \
    -f "$SCRIPT_DIR/argocd/values-tls-certs.yaml" \
    --wait --timeout 5m

  echo "==> Waiting for ArgoCD server to be ready (up to 15 retries, 5s apart)"
  wait_for_argocd
  echo
  print_argocd_access
  echo

  echo "==> Configuring the GitHub repo connection (SSH deploy key)"
  if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "No SSH private key found at $SSH_KEY_PATH." >&2
    echo "Generate one (ssh-keygen -t ed25519 -f $SSH_KEY_PATH) and add its" >&2
    echo ".pub half as a read-only Deploy key on the GitHub repo, then re-run." >&2
    exit 1
  fi
  kubectl create secret generic repo-onboarding -n "$ARGOCD_NAMESPACE" \
    --from-literal=type=git \
    --from-literal=url="$GIT_REPO_URL" \
    --from-literal=name=onboarding \
    --from-literal=project=default \
    --from-file=sshPrivateKey="$SSH_KEY_PATH" \
    --dry-run=client -o yaml \
    | kubectl label -f - --local -o yaml argocd.argoproj.io/secret-type=repository \
    | kubectl apply -f -

  echo "==> Bootstrapping the root Application (manages everything else from here)"
  kubectl apply -f "$SCRIPT_DIR/argocd/root-application.yaml"

  echo
  echo "==> Done. The apps below will keep coming up in the background as"
  echo "    ArgoCD finishes syncing them (Keycloak/Kafka can take a minute or two)."
  echo
  endpoints
}

# Every app here is ClusterIP-only (no ingress controller in this sandbox),
# so the only way in is `kubectl port-forward`. Safe to run any time, even
# before every app has finished syncing - it just prints what to run once
# each one is up.
endpoints() {
  echo "==> Endpoints (run each port-forward in its own terminal)"
  echo
  print_argocd_access
  cat <<EOF

Keycloak admin console
  kubectl -n keycloak port-forward svc/keycloak-keycloakx-http 8080:80
  http://localhost:8080  user: admin  password: admin

Grafana (dashboards over Loki logs)
  kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
  http://localhost:3000  user: admin  password: admin

nginx demo
  kubectl -n nginx port-forward svc/nginx 8081:80
  http://localhost:8081

coraza-haproxy WAF demo
  kubectl -n coraza-haproxy port-forward svc/coraza-haproxy 8082:80
  http://localhost:8082

Kafka bootstrap (for an external client; python-kafka-test itself runs
in-cluster and needs none of this)
  kubectl -n strimzi port-forward svc/my-cluster-kafka-bootstrap 9092:9092
  localhost:9092, SASL_PLAINTEXT, SCRAM-SHA-512
  (get a KafkaUser's password: kubectl -n strimzi get secret <user-name> -o jsonpath='{.data.password}' | base64 -d)
EOF
}

down() {
  echo "==> Deleting kind cluster '$CLUSTER_NAME'"
  kind delete cluster --name "$CLUSTER_NAME"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  endpoints) endpoints ;;
  *) usage ;;
esac
