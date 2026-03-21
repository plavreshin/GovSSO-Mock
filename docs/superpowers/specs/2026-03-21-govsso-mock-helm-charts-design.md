# GovSSO-Mock Helm Charts Design

**Date:** 2026-03-21
**Status:** Approved

---

## Context

GovSSO-Mock is a stateless Go application that implements the GovSSO protocol for development and testing purposes. It:

- Serves HTTPS **only** on port 10443 (no plain HTTP mode)
- Stores all state in memory (no database, no disk writes)
- Reads config from three JSON files: `config.json`, `users.json`, `clients.json` — resolved relative to the working directory `/govsso-mock` (set by `WORKDIR` in the Dockerfile)
- Requires a TLS certificate + private key (for serving HTTPS)
- Requires an RSA key pair (for signing ID tokens and Logout tokens)
- Logs to stdout only
- Runs as a distroless container (`gcr.io/distroless/base-nossl-debian12`, non-`nonroot` variant)

The existing deployment mechanism is Docker Compose. This design adds Helm charts for Kubernetes deployment.

---

## Goals

- Deploy GovSSO-Mock to Kubernetes via Helm
- Follow Bitnami chart conventions and use `bitnami/common` library
- Charts live inside the repo at `charts/govsso-mock/`
- Optionally deploy the example client (`tara-govsso-exampleclient`) as a toggleable subchart
- TLS certs and signing keys are provisioned externally and referenced as existing Kubernetes Secrets
- No default image repository (must be set at install time)

## Non-Goals

- cert-manager integration
- Ingress TLS termination (app cannot run over plain HTTP)
- Horizontal Pod Autoscaler (dev/test tool; single replica is appropriate)
- NetworkPolicy (cluster network topology is environment-specific and cannot be defaulted)
- PodDisruptionBudget
- Publishing chart to OCI or traditional chart repository

---

## Approach

Use **Bitnami-style chart with `bitnami/common` library** (Option B).

The `bitnami/common` library provides:
- `common.images.image` — standardised image reference rendering
- `common.labels` / `common.matchLabels` — consistent label sets
- `common.tplvalues.render` — template value rendering with `tpl` support
- `common.capabilities.*` — k8s API version negotiation

This avoids boilerplate for security contexts, probes, affinity, tolerations, and resource limits while staying aligned with the Bitnami superset chart pattern.

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
    │   ├── NOTES.txt                # post-install instructions with exact secret key names
    │   ├── deployment.yaml          # main app Deployment
    │   ├── service.yaml             # ClusterIP Service on port 10443
    │   ├── serviceaccount.yaml      # optional ServiceAccount
    │   └── configmap.yaml           # config.json, users.json, clients.json
    └── charts/
        └── example-client/          # optional subchart
            ├── Chart.yaml
            ├── values.yaml
            ├── templates/
            │   ├── _helpers.tpl     # subchart label helpers
            │   ├── deployment.yaml
            │   └── service.yaml
```

---

## `values.yaml` Structure

```yaml
## Image — no default repository (must be set at install time)
image:
  repository: ""
  tag: ""
  digest: ""              # alternative to tag, takes precedence if set
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
## tls.existingSecret must contain keys: tls.crt, tls.key
## idToken.existingSecret must contain keys: id-token-sign.key.pem, id-token-sign.pub.pem
tls:
  existingSecret: ""
idToken:
  existingSecret: ""

## Standard Bitnami deployment knobs
replicaCount: 1
serviceAccount:
  create: true
  name: ""
  annotations: {}
service:
  type: ClusterIP
  port: 10443
  targetPort: https       # must match the named port in the Deployment container spec
resources: {}
podSecurityContext:
  enabled: true
  fsGroup: 1001
containerSecurityContext:
  enabled: true
  ## Note: distroless/base-nossl-debian12 (non-nonroot) does not provision UID 1001.
  ## Any non-zero UID is acceptable since the binary does not require a specific UID.
  runAsUser: 1001
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
livenessProbe:
  enabled: true
  ## The app has no dedicated health endpoint; "/" (home page, HTTP 200) is used.
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
  successThreshold: 1
readinessProbe:
  enabled: true
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
  successThreshold: 1
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
    digest: ""
    pullPolicy: IfNotPresent
  clientId: "example-client-id"
  ## clientSecret: provide inline (dev) or via existingSecret (production)
  clientSecret: ""
  existingSecret: ""          # Secret key: client-secret
  govSsoIssuerUri: ""
  redirectUri: ""
  postLogoutRedirectUri: ""
  ## tls.existingSecret must contain keys: keystore.p12 and truststore.p12
  ## keystorePassword and truststorePassword are separate configurable values.
  tls:
    existingSecret: ""
    keystorePassword: "changeit"
    truststorePassword: "changeit"
  ## Spring profile — must be "govsso" for the example client to activate GovSSO configuration
  springProfile: "govsso"
  messagesTitle: "GovSSO Client"
  jvmThreadCount: "10"
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

The `config.json` paths are hardcoded to match mount points. The app resolves all paths relative to its working directory `/govsso-mock` (set by `WORKDIR` in the Dockerfile — this must never be overridden in the Deployment's `workingDir` field):

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

- Image rendered via `common.images.image` (supports both `tag` and `digest`)
- `imagePullSecrets` wired from `image.pullSecrets` via `common.images.pullSecrets`
- Named port `https` on 10443 — Service `targetPort: https` references this name
- `readOnlyRootFilesystem: true` is safe — the app writes nothing to disk
- `workingDir` must NOT be set (must inherit the Dockerfile `WORKDIR /govsso-mock`)
- Liveness/readiness: HTTPS GET on port 10443, path `/`, scheme `HTTPS`
  - The app has no dedicated health endpoint; `/` renders the home page (HTTP 200) and is the only viable probe path
- All probe fields included: `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`, `successThreshold`
- Security context applied via Bitnami pattern with `enabled` flag guards

### `service.yaml`

ClusterIP service, port 10443, named `https`. `targetPort: https` references the named port in the Deployment container spec — the linkage is by name, not number, ensuring consistency if the port number changes.

### `_helpers.tpl` (main chart)

Extends `bitnami/common` with chart-specific helpers:
- `govsso-mock.fullname` — release-prefixed name
- `govsso-mock.labels` — wraps `common.labels`
- `govsso-mock.matchLabels` — wraps `common.matchLabels`
- `govsso-mock.serviceAccountName` — conditional SA name resolution

### `example-client` subchart

#### `_helpers.tpl`

Provides subchart-scoped label helpers using the subchart's own release context:
- `example-client.fullname`
- `example-client.labels`
- `example-client.matchLabels`

#### `deployment.yaml` — environment variables

All env vars from docker-compose are represented:

| Env var | Source |
|---------|--------|
| `server.port` | `11443` (hardcoded, matches `service.port`) |
| `govsso.client-id` | `exampleClient.clientId` |
| `govsso.client-secret` | From `existingSecret` key `client-secret`, or inline `clientSecret` |
| `govsso.redirect-uri` | `exampleClient.redirectUri` |
| `govsso.post-logout-redirect-uri` | `exampleClient.postLogoutRedirectUri` |
| `govsso.issuer-uri` | `exampleClient.govSsoIssuerUri` |
| `govsso.trust-store` | `file:/var/local/config/tls/truststore.p12` |
| `govsso.trust-store-password` | `exampleClient.tls.truststorePassword` |
| `server.ssl.key-store` | `file:/var/local/config/tls/keystore.p12` |
| `server.ssl.key-store-type` | `PKCS12` (hardcoded) |
| `server.ssl.key-store-password` | `exampleClient.tls.keystorePassword` |
| `SPRING_PROFILES_ACTIVE` | `exampleClient.springProfile` (default: `"govsso"`) |
| `example-client.messages.title` | `exampleClient.messagesTitle` |
| `BPL_JVM_THREAD_COUNT` | `exampleClient.jvmThreadCount` |

TLS secret mounted at `/var/local/config/tls/` (keys: `keystore.p12`, `truststore.p12`).

### `values.schema.json`

Enforces at `helm install` / `helm upgrade` time:

**Always required:**
- `image.repository` — non-empty string
- `image.tag` — non-empty string (required unless `image.digest` is set; schema enforces at least one)
- `tls.existingSecret` — non-empty string
- `idToken.existingSecret` — non-empty string

**Required when `exampleClient.enabled=true`:**
- `exampleClient.govSsoIssuerUri` — non-empty string
- `exampleClient.tls.existingSecret` — non-empty string
- `exampleClient.clientId` — non-empty string
- `exampleClient.redirectUri` — non-empty string
- `exampleClient.postLogoutRedirectUri` — non-empty string

### `NOTES.txt`

Post-install message showing:
- The mock's HTTPS Service address
- Required Secret formats:

```
tls.existingSecret must be a TLS Secret with keys:
  tls.crt  — PEM-encoded TLS certificate
  tls.key  — PEM-encoded TLS private key

idToken.existingSecret must be a generic Secret with keys:
  id-token-sign.key.pem  — PEM-encoded RSA private key (for signing)
  id-token-sign.pub.pem  — PEM-encoded RSA public key (served at JWKS endpoint)
```

- When example client is enabled: its Service address, reminder about keystore/truststore secrets with key names `keystore.p12` and `truststore.p12`

---

## Security Considerations

- `readOnlyRootFilesystem: true` — safe, app writes nothing to disk
- `runAsNonRoot: true` + `runAsUser: 1001` — the distroless base image (non-`nonroot` variant) does not provision UID 1001, but any non-zero UID is acceptable since the binary does not require a specific UID; this satisfies the `runAsNonRoot` constraint
- `allowPrivilegeEscalation: false` — no privilege escalation needed
- `fsGroup: 1001` — included for consistency with Bitnami convention; functionally unnecessary since `readOnlyRootFilesystem: true` and no writable volume mounts exist
- Secrets are never rendered into ConfigMaps — only referenced by name via `existingSecret` pattern
- Client secret for example client supports both inline value (dev convenience) and `existingSecret` (production)
- `imagePullSecrets` wired from `image.pullSecrets`

---

## Bitnami Conventions Followed

- `bitnami/common` library dependency in `Chart.yaml`
- `values.yaml` structure mirrors bitnami/superset: image block with `digest` field, security contexts with `enabled` guards, probe blocks with all fields, `extraEnv`, `extraVolumes`, `extraVolumeMounts`
- `values.schema.json` for input validation including conditional subchart requirements
- Labels use `common.labels` and `common.matchLabels`
- `_helpers.tpl` in both main chart and subchart
- `NOTES.txt` provides actionable post-install instructions with exact secret key names
- Service `targetPort` uses named port reference for maintainability
