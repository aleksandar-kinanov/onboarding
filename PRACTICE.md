# Practice exercises

Once `./setup.sh up` is running, don't just leave the stack idle — use it to
practice the underlying tools. Every exercise below is done the same way:
add/edit a manifest under `apps/`, commit, push, and watch ArgoCD sync it.
Never `kubectl apply`/`edit` directly (see the main README's Conventions).
If you get stuck on one, that's the point — dig into the CRD before looking
anywhere else:

```bash
kubectl explain <kind>.<group>          # e.g. kubectl explain client.openidclient.keycloak.crossplane.io
kubectl describe <kind> <name> -n keycloak   # check .status for the provider's own error messages
```

## Keycloak / Crossplane

1. **Realm creation** — add a second `Realm` claim (see
   `apps/keycloak/templates/realm-onboarding.yaml`) under its own name.
2. **Users, groups, roles** — add a `User`, put them in a `Group` (see
   `group-onboarding.yaml`'s `Group`/`Memberships` pair), and give them a
   `Roles` claim so their access follows a `Role` you define.
3. **Client creation/configuration** — add a `Client`
   (`openidclient.keycloak.crossplane.io`) for a hypothetical app: pick
   `PUBLIC` vs `CONFIDENTIAL`, set redirect URIs, and for `CONFIDENTIAL`
   wire up a `clientSecretSecretRef` (see `client-test-broker.yaml`).
4. **Client scopes** — create a `ClientScope` and attach it to a client, so
   it's only issued to clients that ask for it instead of living on every
   token by default.
5. **Mappers** — add a protocol mapper to a client or client scope (e.g. map
   a user attribute, or a group membership, into a token claim), then
   decode a token from that client and confirm the claim is there.
6. **Federation between two realms** — this repo already has a second
   realm (`realm-merge.yaml`) and a broker `Client`
   (`client-test-broker.yaml`) as a starting point: finish wiring one realm
   as an Identity Provider for the other, then add an IdP mapper so a login
   through the broker lands the user in the right group/role automatically.

## Kafka

7. Add a second `KafkaTopic`/`KafkaUser` pair and point a copy of
   `python-kafka-test` at it via its `ConfigMap` (see how the existing app
   wires topic/username through `envFrom` + Kustomize `replacements`).
8. Lock the new `KafkaUser`'s ACLs down to only its own topic, then confirm
   a client using the *old* user can't read/write it.

## WAF / observability

9. Send a request through `coraza-haproxy` designed to trip a Coraza rule
   (e.g. a SQLi-looking query string) and find the blocked request's log
   line in Grafana via the Loki datasource.
10. Add a new panel to the provisioned Grafana dashboard (edit the
    ConfigMap in `apps/monitoring/`) that graphs blocked vs. allowed
    request counts.

## Kustomize

11. Add your own patch/`replacements` entry to `apps/nginx/` that changes
    something observable in the response (e.g. a response header), so you
    can see the Helm-inflation + Kustomize-patch layering in action.
