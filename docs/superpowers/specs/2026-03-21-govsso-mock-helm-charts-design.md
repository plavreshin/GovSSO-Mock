# GovSSO-Mock Helm Charts Design

**Date:** 2026-03-21
**Status:** Approved

---

## Context

GovSSO-Mock is a stateless Go application that implements the GovSSO protocol for development and testing purposes. It:

- Serves HTTPS **only** on port 10443 (no plain HTTP mode)
- Stores all state in memory (no database, no disk writes)
- Requires three config JSON files: `config.json`, `users.json`, `clients.json`
- Requires a TLS certificate + private key (for serving HTTPS)
- Requires an RSA key pair (for signing ID tokens and Logout tokens)
- Logs to stdout only
- Runs as a distroless container

The existing deployment mechanism is Docker Compose. This design adds Helm charts for Kubernetes deployment.

---

## Goals

- Deploy GovSSO-Mock to Kubernetes via Helm
- Follow Bitnami chart conventions and use `bitnami/common` library
- Charts live inside the GovSSO-Mock repository at `charts/govsso-mock/`
- Optionally deploy the example client (`tara-govsso-exampleclient`) as a toggleable subchart
- TLS certs and signing keys are provisioned externally and referenced as existing Kubernetes Secrets
- No default image repository (must be set at install time)

## Non-Goals

- cert-manager integration
- Ingress TLS termination (app cannot run over plain HTTP)
- Horizontal Pod Autoscaling (stateless but single-replica is fine for dev/test)
- Helm chart publishing to a chart repository

---

## Approach

Use **Bitnami-style chart with `bitnami/common` library** (Option B).

The `bitnami/common` library provides:
- `common.images.image` — standardised image reference rendering
- `common.labels` / `common.matchLabels` — consistent label sets
- `common.tplvalues.render` — template value rendering with `tpl` support
- `common.capabilities.*` — k8s API version negotiation

This avoids boilerplate for security contexts, probes, affinity, tolerations, and resource limits while staying aligned with the Bitnami superset chart pattern referenced in the requirements.

---

## Chart Layout

```
charts/
└── govsso-mock/
    ├── Chart.yaml                   # apiVersion v2; declares bitnami/common dependency
    ├── values.yaml                  # all defaults with documentation
    ├── values.schema.json           # JSON Schema: enforces required fields
    ├── templates/
    │   ├── _helpers.tpl             # named templates using common.* helpers
    │   ├── NOTES.txt                # post-install instructions
    │   ├── deployment.yaml          # main app Deployment
    │   ├── service.yaml             # ClusterIP Service on port 10443
    │   ├── serviceaccount.yaml      # optional ServiceAccount
    │   └── configmap.yaml           # config.json, users.json, clients.json
    └── charts/
        └── example-client/          # optional subchart
            ├── Chart.yaml
            ├── values.yaml
            └── templates/
                ├── deployment.yaml
                └── service.yaml
```

---

## `values.yaml` Structure

```yaml
## Image — no default repository (must be set at install time)
image:
  repository: ""
  tag: ""
  pullPolicy: IfNotPresent
  pullSecrets: []

## GovSSO-Mock application config (rendered into config.json)
config:
  host: "govsso-mock.example.com"
  serverPort: "10443"
  baseHref: "/"
  idTokenSignKeyId: "govsso-mock"

## JSON config files rendered into ConfigMap
users: []       # array of user objects → users.json
clients: []     # array of client objects → clients.json

## Secrets — must be created externally before helm install
tls:
  existingSecret: ""        # keys: tls.crt, tls.key
idToken:
  existingSecret: ""        # keys: id-token-sign.key.pem, id-token-sign.pub.pem

## Standard Bitnami deployment knobs
replicaCount: 1
serviceAccount:
  create: true
  name: ""
  annotations: {}
service:
  type: ClusterIP
  port: 10443
resources: {}
podSecurityContext:
  enabled: true
  fsGroup: 1001
containerSecurityContext:
  enabled: true
  runAsUser: 1001
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
livenessProbe:
  enabled: true
  initialDelaySeconds: 10
  periodSeconds: 10
readinessProbe:
  enabled: true
  initialDelaySeconds: 5
  periodSeconds: 5
nodeSelector: {}
tolerations: []
affinity: {}
extraEnv: []
extraVolumes: []
extraVolumeMounts: []

## Example client subchart
exampleClient:
  enabled: false
  image:
    repository: ghcr.io/e-gov/tara-govsso-exampleclient
    tag: "0.7.3"
    pullPolicy: IfNotPresent
  clientId: "example-client-id"
  clientSecret: ""
  existingSecret: ""          # alternative: Secret with key client-secret
  govSsoIssuerUri: ""
  redirectUri: ""
  postLogoutRedirectUri: ""
  tls:
    existingSecret: ""        # keys: keystore.p12, truststore.p12
  service:
    type: ClusterIP
    port: 11443
  resources: {}
```

---

## Template Details

### `configmap.yaml`

Renders three ConfigMap keys:

| Key | Source |
|-----|--------|
| `config.json` | Built from `values.config.*` via `tpl` + `toJson` |
| `users.json` | `values.users \| toJson` |
| `clients.json` | `values.clients \| toJson` |

Mounted read-only at `/govsso-mock/config/`.

The `config.json` paths are hardcoded to match mount points:
```json
{
  "tlsCertificate": "config/tls/govsso-mock/tls.crt",
  "tlsPrivateKey": "config/tls/govsso-mock/tls.key",
  "idTokenSignPrivateKeyPath": "config/id-token/id-token-sign.key.pem",
  "idTokenSignPublicKeyPath": "config/id-token/id-token-sign.pub.pem"
}
```

### `deployment.yaml`

Single container with three volume mounts:

| Volume | Source | Mount path |
|--------|--------|------------|
| `config` | ConfigMap | `/govsso-mock/config/` |
| `tls` | Secret (`tls.existingSecret`) | `/govsso-mock/config/tls/govsso-mock/` |
| `id-token` | Secret (`idToken.existingSecret`) | `/govsso-mock/config/id-token/` |

- Image rendered via `common.images.image`
- Named port `https` on 10443
- `readOnlyRootFilesystem: true` is safe — the app writes nothing to disk
- Liveness/readiness: HTTPS GET on port 10443, path `/`, `httpGet` with scheme `HTTPS`
- Security context applied via Bitnami pattern with `enabled` flag guards

### `service.yaml`

ClusterIP service, port 10443, named `https`, targeting pod port `https`.

### `example-client` subchart

Mirrors docker-compose environment variables as container env vars. Key env vars:

- `govsso.client-id` ← `exampleClient.clientId`
- `govsso.client-secret` ← from Secret or inline value
- `govsso.issuer-uri` ← `exampleClient.govSsoIssuerUri`
- `govsso.redirect-uri` ← `exampleClient.redirectUri`
- `govsso.post-logout-redirect-uri` ← `exampleClient.postLogoutRedirectUri`
- `govsso.trust-store` ← path to mounted truststore
- `server.ssl.key-store` ← path to mounted keystore

TLS secret mounted at `/var/local/config/tls/`.

### `values.schema.json`

Enforces at `helm install` / `helm upgrade` time:
- `tls.existingSecret` — non-empty string, required
- `idToken.existingSecret` — non-empty string, required
- `image.repository` — non-empty string, required
- `image.tag` — non-empty string, required
- When `exampleClient.enabled=true`: `exampleClient.govSsoIssuerUri`, `exampleClient.tls.existingSecret` are required

### `NOTES.txt`

Post-install message showing:
- The mock's HTTPS Service address
- Reminder that `tls.existingSecret` and `idToken.existingSecret` must contain valid PEM-encoded material
- When example client is enabled: its Service address and reminder about keystore/truststore secrets

---

## Security Considerations

- `readOnlyRootFilesystem: true` — safe, app writes nothing to disk
- `runAsNonRoot: true` + `runAsUser: 1001` — matches distroless non-root user
- `allowPrivilegeEscalation: false` — no privilege escalation needed
- Secrets are never rendered into ConfigMaps — only referenced by name
- Client secret for example client supports both inline value (dev convenience) and `existingSecret` (production)

---

## Bitnami Conventions Followed

- `bitnami/common` library dependency in `Chart.yaml`
- `values.yaml` structure mirrors bitnami/superset: image block, security contexts with `enabled` guards, probe blocks with `enabled` guards, `extraEnv`, `extraVolumes`, `extraVolumeMounts`
- `values.schema.json` for input validation
- Labels use `common.labels` and `common.matchLabels`
- `_helpers.tpl` extends common helpers with chart-specific named templates
- `NOTES.txt` provides actionable post-install instructions

---

## Out of Scope

The following are explicitly excluded from this design:

- Generating TLS certificates or RSA key pairs (use external tooling)
- Ingress resource (app serves HTTPS directly; ingress passthrough is cluster-specific)
- HorizontalPodAutoscaler (dev/test tool, single replica is appropriate)
- NetworkPolicy
- PodDisruptionBudget
- Publishing chart to OCI or traditional chart repository
