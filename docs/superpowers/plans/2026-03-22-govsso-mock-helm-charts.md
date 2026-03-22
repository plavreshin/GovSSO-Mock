# GovSSO-Mock Helm Charts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Bitnami-style Helm chart at `charts/govsso-mock/` that deploys the GovSSO-Mock application to Kubernetes, with an optional example-client subchart.

**Architecture:** Main chart uses `bitnami/common` v2.36.0 library for standardised labels, image rendering, and value helpers. Config files are rendered into a ConfigMap and mounted via `subPath` per file. TLS and signing key material is sourced from externally-provisioned k8s Secrets. The example client lives as a vendored subchart at `charts/example-client/` and is disabled by default.

**Tech Stack:** Helm v3, bitnami/common 2.36.0 (OCI: `oci://registry-1.docker.io/bitnamicharts/common`), helm-unittest plugin for unit tests.

---

## Important Notes Before Starting

- **Working directory constraint:** The app's `WORKDIR` is `/govsso-mock`. All config paths in `config.json` are relative to this. Never set `workingDir` in the Deployment.
- **subPath mounts:** ConfigMap files are mounted individually with `subPath` so the TLS/id-token secret subdirectory mounts don't conflict.
- **Subchart value passing:** Helm passes parent values to a subchart using a key that matches the subchart's chart name exactly. The subchart is named `example-client` (hyphenated), so the values key in the parent is `example-client:`.
- **Secret key names:** `tls.existingSecret` must have keys `tls.crt` / `tls.key`. `idToken.existingSecret` must have keys `id-token-sign.key.pem` / `id-token-sign.pub.pem`. `example-client.tls.existingSecret` must have keys `keystore.p12` / `truststore.p12`.
- **Helm-unittest:** Install before running tests: `helm plugin install https://github.com/helm-unittest/helm-unittest`

---

## File Map

**Create:**
```
charts/govsso-mock/
  Chart.yaml
  values.yaml
  values.schema.json
  templates/
    _helpers.tpl
    NOTES.txt
    configmap.yaml
    serviceaccount.yaml
    service.yaml
    deployment.yaml
  tests/
    configmap_test.yaml
    serviceaccount_test.yaml
    service_test.yaml
    deployment_test.yaml
    schema_test.yaml
  charts/
    example-client/
      Chart.yaml
      values.yaml
      templates/
        _helpers.tpl
        deployment.yaml
        service.yaml
      tests/
        deployment_test.yaml
```

---

## Task 1: Scaffold directory structure and install helm-unittest

**Files:**
- Create: `charts/govsso-mock/` tree (directories only)

- [ ] **Step 1: Create chart directories**

```bash
mkdir -p charts/govsso-mock/templates
mkdir -p charts/govsso-mock/tests
mkdir -p charts/govsso-mock/charts/example-client/templates
mkdir -p charts/govsso-mock/charts/example-client/tests
```

- [ ] **Step 2: Install helm-unittest plugin**

```bash
helm plugin list | grep unittest || helm plugin install https://github.com/helm-unittest/helm-unittest
```

Expected: `unittest	X.Y.Z	...` line appears in plugin list.

- [ ] **Step 3: Verify helm is available and version**

```bash
helm version --short
```

Expected: `v3.x.x` or `v4.x.x`.

---

## Task 2: Chart.yaml and dependency fetch

**Files:**
- Create: `charts/govsso-mock/Chart.yaml`

- [ ] **Step 1: Write Chart.yaml**

```yaml
# charts/govsso-mock/Chart.yaml
apiVersion: v2
name: govsso-mock
description: Helm chart for deploying GovSSO-Mock to Kubernetes
type: application
version: 0.1.0
appVersion: "latest"
keywords:
  - govsso
  - mock
  - oidc
  - authentication
home: https://github.com/e-gov/GovSSO-Mock
sources:
  - https://github.com/e-gov/GovSSO-Mock
maintainers:
  - name: GovSSO-Mock maintainers
dependencies:
  - name: common
    version: 2.36.0
    repository: oci://registry-1.docker.io/bitnamicharts
```

- [ ] **Step 2: Fetch bitnami/common dependency**

```bash
cd charts/govsso-mock && helm dependency update && cd ../..
```

Expected output includes: `Saving 1 charts` and `charts/common-2.36.0.tgz` appears under `charts/govsso-mock/charts/`.

- [ ] **Step 3: Verify dependency fetched**

```bash
ls charts/govsso-mock/charts/
```

Expected: `common-2.36.0.tgz  example-client/`

- [ ] **Step 4: Commit**

```bash
git add charts/govsso-mock/Chart.yaml charts/govsso-mock/charts/common-2.36.0.tgz charts/govsso-mock/Chart.lock
git commit -m "feat(helm): add Chart.yaml with bitnami/common dependency"
```

---

## Task 3: values.yaml

**Files:**
- Create: `charts/govsso-mock/values.yaml`

- [ ] **Step 1: Write values.yaml**

```yaml
# charts/govsso-mock/values.yaml

## @section Image
## @param image.repository Container image repository (required, no default)
## @param image.tag Container image tag
## @param image.digest Container image digest (takes precedence over tag if set)
## @param image.pullPolicy Image pull policy
## @param image.pullSecrets List of image pull secret names
image:
  repository: ""
  tag: ""
  digest: ""
  pullPolicy: IfNotPresent
  pullSecrets: []

## @section GovSSO-Mock application configuration
## Rendered into config.json and mounted as a ConfigMap
## @param config.host Domain name where the mock is served
## @param config.serverPort TCP port where the mock is served
## @param config.baseHref HTTP base path where the mock is served
## @param config.idTokenSignKeyId `kid` value served at the JWKS endpoint
config:
  host: "govsso-mock.example.com"
  serverPort: "10443"
  baseHref: "/"
  idTokenSignKeyId: "govsso-mock"

## @section Preconfigured users and clients
## Rendered into users.json and clients.json respectively
## @param users Array of preconfigured user objects for the mock login page
## @param clients Array of preconfigured client application objects
users: []
clients: []

## @section TLS and ID-token signing secrets
## Both secrets must exist in the cluster before running helm install.
##
## tls.existingSecret must be a TLS-type Secret with keys:
##   tls.crt  — PEM-encoded TLS certificate
##   tls.key  — PEM-encoded TLS private key
##
## idToken.existingSecret must be a generic Secret with keys:
##   id-token-sign.key.pem  — PEM-encoded RSA private key (used for JWT signing)
##   id-token-sign.pub.pem  — PEM-encoded RSA public key (served at JWKS endpoint)
##
## @param tls.existingSecret Name of existing Secret containing TLS cert/key
## @param idToken.existingSecret Name of existing Secret containing RSA key pair
tls:
  existingSecret: ""
idToken:
  existingSecret: ""

## @section Deployment
## @param replicaCount Number of replicas
replicaCount: 1

## @section Service Account
## @param serviceAccount.create Whether to create a ServiceAccount
## @param serviceAccount.name Override for the ServiceAccount name
## @param serviceAccount.annotations Annotations to add to the ServiceAccount
serviceAccount:
  create: true
  name: ""
  annotations: {}

## @section Service
## @param service.type Kubernetes Service type
## @param service.port Service port (matches containerPort)
service:
  type: ClusterIP
  port: 10443

## @section Resource limits
## @param resources CPU/memory resource requests and limits
resources: {}

## @section Pod security context
## @param podSecurityContext.enabled Enable pod-level security context
## @param podSecurityContext.fsGroup fsGroup for volume ownership
podSecurityContext:
  enabled: true
  fsGroup: 1001

## @section Container security context
## Note: distroless/base-nossl-debian12 (non-nonroot) does not provision UID 1001,
## but any non-zero UID satisfies runAsNonRoot since the binary has no UID requirement.
## @param containerSecurityContext.enabled Enable container-level security context
## @param containerSecurityContext.runAsUser UID to run the container as
## @param containerSecurityContext.runAsNonRoot Require non-root user
## @param containerSecurityContext.readOnlyRootFilesystem Mount root filesystem read-only
## @param containerSecurityContext.allowPrivilegeEscalation Prevent privilege escalation
containerSecurityContext:
  enabled: true
  runAsUser: 1001
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false

## @section Liveness probe
## The app has no dedicated health endpoint. "/" (home page, HTTP 200) is used.
## @param livenessProbe.enabled Enable liveness probe
livenessProbe:
  enabled: true
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
  successThreshold: 1

## @section Readiness probe
## @param readinessProbe.enabled Enable readiness probe
readinessProbe:
  enabled: true
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
  successThreshold: 1

## @section Scheduling
## @param nodeSelector Node selector labels
## @param tolerations Tolerations for pod scheduling
## @param affinity Affinity rules for pod scheduling
nodeSelector: {}
tolerations: []
affinity: {}

## @section Extra configuration
## @param extraEnv Extra environment variables injected into the container
## @param extraVolumes Extra volumes added to the pod
## @param extraVolumeMounts Extra volume mounts added to the container
extraEnv: []
extraVolumes: []
extraVolumeMounts: []

## @section Example client subchart
## The example client (tara-govsso-exampleclient) is an optional companion
## that demonstrates GovSSO authentication flows.
##
## IMPORTANT: Helm passes these values to the subchart using the key "example-client"
## (hyphenated, matching the subchart's chart name). Use --set 'example-client.enabled=true'
## on the command line.
##
## example-client.tls.existingSecret must be a generic Secret with keys:
##   keystore.p12   — PKCS12 keystore for the example client's TLS certificate
##   truststore.p12 — PKCS12 truststore containing the mock's CA certificate
"example-client":
  enabled: false
  image:
    repository: ghcr.io/e-gov/tara-govsso-exampleclient
    tag: "0.7.3"
    digest: ""
    pullPolicy: IfNotPresent
  clientId: "example-client-id"
  ## Provide clientSecret inline (dev) or via existingSecret (production)
  clientSecret: ""
  existingSecret: ""  # Secret key: client-secret
  govSsoIssuerUri: ""
  redirectUri: ""
  postLogoutRedirectUri: ""
  tls:
    existingSecret: ""
    keystorePassword: "changeit"
    truststorePassword: "changeit"
  ## Must be "govsso" to activate GovSSO Spring profile in the example client
  springProfile: "govsso"
  messagesTitle: "GovSSO Client"
  jvmThreadCount: "10"
  service:
    type: ClusterIP
    port: 11443
  resources: {}
```

- [ ] **Step 2: Verify values.yaml is valid YAML**

```bash
helm show values charts/govsso-mock 2>&1 | head -20
```

Expected: Shows the first few lines of values.yaml without errors.

- [ ] **Step 3: Commit**

```bash
git add charts/govsso-mock/values.yaml
git commit -m "feat(helm): add values.yaml with Bitnami-style structure"
```

---

## Task 4: `_helpers.tpl` (main chart)

**Files:**
- Create: `charts/govsso-mock/templates/_helpers.tpl`

- [ ] **Step 1: Write _helpers.tpl**

```
{{/*
charts/govsso-mock/templates/_helpers.tpl
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "govsso-mock.name" -}}
{{- include "common.names.name" . }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "govsso-mock.fullname" -}}
{{- include "common.names.fullname" . }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "govsso-mock.chart" -}}
{{- include "common.names.chart" . }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "govsso-mock.labels" -}}
{{ include "common.labels.standard" (dict "customLabels" .Values.commonLabels "context" $) }}
{{- end }}

{{/*
Selector / match labels
*/}}
{{- define "govsso-mock.matchLabels" -}}
{{ include "common.labels.matchLabels" (dict "customLabels" .Values.commonLabels "context" $) }}
{{- end }}

{{/*
Return the ServiceAccount name to use.
*/}}
{{- define "govsso-mock.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
  {{- default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else }}
  {{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
```

- [ ] **Step 2: Lint to verify helper syntax**

```bash
helm lint charts/govsso-mock --set image.repository=test --set image.tag=1.0 \
  --set tls.existingSecret=test-tls --set idToken.existingSecret=test-id 2>&1
```

Expected: `[INFO] Chart.yaml: icon is recommended` (acceptable) and no ERROR lines.

- [ ] **Step 3: Commit**

```bash
git add charts/govsso-mock/templates/_helpers.tpl
git commit -m "feat(helm): add _helpers.tpl with common.* named templates"
```

---

## Task 5: `configmap.yaml` + unit test

**Files:**
- Create: `charts/govsso-mock/templates/configmap.yaml`
- Create: `charts/govsso-mock/tests/configmap_test.yaml`

- [ ] **Step 1: Write the unit test first (TDD)**

```yaml
# charts/govsso-mock/tests/configmap_test.yaml
suite: configmap
templates:
  - templates/configmap.yaml
tests:
  - it: renders a ConfigMap with three data keys
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
    asserts:
      - isKind:
          of: ConfigMap
      - equal:
          path: data["users.json"]
          value: "[]"
      - equal:
          path: data["clients.json"]
          value: "[]"
      - matchRegex:
          path: data["config.json"]
          pattern: '"host"'
      - matchRegex:
          path: data["config.json"]
          pattern: '"tlsCertificate"'
      - matchRegex:
          path: data["config.json"]
          pattern: '"idTokenSignKeyId"'

  - it: embeds config.host from values
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
      config.host: my-govsso.example.com
    asserts:
      - matchRegex:
          path: data["config.json"]
          pattern: '"host":\s*"my-govsso\.example\.com"'

  - it: embeds users array from values
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
      users:
        - sub: EE38001085718
          given_name: Jaak-Kristjan
          family_name: Joeorg
          birthdate: "1980-01-08"
          amr: idcard
          acr: high
    asserts:
      - matchRegex:
          path: data["users.json"]
          pattern: "EE38001085718"

  - it: hardcodes tls cert path in config.json
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
    asserts:
      - matchRegex:
          path: data["config.json"]
          pattern: 'config/tls/govsso-mock/tls\.crt'
      - matchRegex:
          path: data["config.json"]
          pattern: 'config/id-token/id-token-sign\.key\.pem'
```

- [ ] **Step 2: Run the test — expect FAIL (no template yet)**

```bash
helm unittest charts/govsso-mock -f tests/configmap_test.yaml 2>&1
```

Expected: `Error` or `FAILED` (template doesn't exist yet).

- [ ] **Step 3: Write configmap.yaml**

```yaml
{{/* charts/govsso-mock/templates/configmap.yaml */}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "govsso-mock.fullname" . }}
  namespace: {{ .Release.Namespace | quote }}
  labels: {{- include "govsso-mock.labels" . | nindent 4 }}
data:
  config.json: |-
    {{ dict
        "host"                     .Values.config.host
        "serverPort"               .Values.config.serverPort
        "baseHref"                 .Values.config.baseHref
        "tlsCertificate"           "config/tls/govsso-mock/tls.crt"
        "tlsPrivateKey"            "config/tls/govsso-mock/tls.key"
        "idTokenSignPrivateKeyPath" "config/id-token/id-token-sign.key.pem"
        "idTokenSignPublicKeyPath"  "config/id-token/id-token-sign.pub.pem"
        "idTokenSignKeyId"         .Values.config.idTokenSignKeyId
      | toJson }}
  users.json: |-
    {{ .Values.users | toJson }}
  clients.json: |-
    {{ .Values.clients | toJson }}
```

- [ ] **Step 4: Run the test — expect PASS**

```bash
helm unittest charts/govsso-mock -f tests/configmap_test.yaml 2>&1
```

Expected: `PASS` for all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add charts/govsso-mock/templates/configmap.yaml charts/govsso-mock/tests/configmap_test.yaml
git commit -m "feat(helm): add configmap.yaml rendering config.json, users.json, clients.json"
```

---

## Task 6: `serviceaccount.yaml` + unit test

**Files:**
- Create: `charts/govsso-mock/templates/serviceaccount.yaml`
- Create: `charts/govsso-mock/tests/serviceaccount_test.yaml`

- [ ] **Step 1: Write unit test**

```yaml
# charts/govsso-mock/tests/serviceaccount_test.yaml
suite: serviceaccount
templates:
  - templates/serviceaccount.yaml
tests:
  - it: creates a ServiceAccount when enabled
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
      serviceAccount.create: true
    asserts:
      - isKind:
          of: ServiceAccount
      - equal:
          path: metadata.name
          value: RELEASE-NAME-govsso-mock

  - it: renders no resources when disabled
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
      serviceAccount.create: false
    asserts:
      - hasDocuments:
          count: 0

  - it: uses custom name when provided
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
      serviceAccount.create: true
      serviceAccount.name: my-sa
    asserts:
      - equal:
          path: metadata.name
          value: my-sa
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
helm unittest charts/govsso-mock -f tests/serviceaccount_test.yaml 2>&1
```

- [ ] **Step 3: Write serviceaccount.yaml**

```yaml
{{/* charts/govsso-mock/templates/serviceaccount.yaml */}}
{{- if .Values.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "govsso-mock.serviceAccountName" . }}
  namespace: {{ .Release.Namespace | quote }}
  labels: {{- include "govsso-mock.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations: {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: false
{{- end }}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
helm unittest charts/govsso-mock -f tests/serviceaccount_test.yaml 2>&1
```

- [ ] **Step 5: Commit**

```bash
git add charts/govsso-mock/templates/serviceaccount.yaml charts/govsso-mock/tests/serviceaccount_test.yaml
git commit -m "feat(helm): add serviceaccount.yaml"
```

---

## Task 7: `service.yaml` + unit test

**Files:**
- Create: `charts/govsso-mock/templates/service.yaml`
- Create: `charts/govsso-mock/tests/service_test.yaml`

- [ ] **Step 1: Write unit test**

```yaml
# charts/govsso-mock/tests/service_test.yaml
suite: service
templates:
  - templates/service.yaml
tests:
  - it: renders a ClusterIP Service on port 10443
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
    asserts:
      - isKind:
          of: Service
      - equal:
          path: spec.type
          value: ClusterIP
      - equal:
          path: spec.ports[0].port
          value: 10443
      - equal:
          path: spec.ports[0].targetPort
          value: https
      - equal:
          path: spec.ports[0].name
          value: https

  - it: uses NodePort when service type is overridden
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
      service.type: NodePort
    asserts:
      - equal:
          path: spec.type
          value: NodePort
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
helm unittest charts/govsso-mock -f tests/service_test.yaml 2>&1
```

- [ ] **Step 3: Write service.yaml**

```yaml
{{/* charts/govsso-mock/templates/service.yaml */}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "govsso-mock.fullname" . }}
  namespace: {{ .Release.Namespace | quote }}
  labels: {{- include "govsso-mock.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - name: https
      port: {{ .Values.service.port }}
      targetPort: https
      protocol: TCP
  selector: {{- include "govsso-mock.matchLabels" . | nindent 4 }}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
helm unittest charts/govsso-mock -f tests/service_test.yaml 2>&1
```

- [ ] **Step 5: Commit**

```bash
git add charts/govsso-mock/templates/service.yaml charts/govsso-mock/tests/service_test.yaml
git commit -m "feat(helm): add service.yaml ClusterIP on port 10443"
```

---

## Task 8: `deployment.yaml` + unit tests

**Files:**
- Create: `charts/govsso-mock/templates/deployment.yaml`
- Create: `charts/govsso-mock/tests/deployment_test.yaml`

- [ ] **Step 1: Write unit tests**

```yaml
# charts/govsso-mock/tests/deployment_test.yaml
suite: deployment
templates:
  - templates/deployment.yaml
tests:
  - it: renders a Deployment with correct container name
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
    asserts:
      - isKind:
          of: Deployment
      - equal:
          path: spec.template.spec.containers[0].name
          value: govsso-mock

  - it: uses the provided image repository and tag
    set:
      image.repository: myregistry.example.com/govsso-mock
      image.tag: "2.0.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
    asserts:
      - matchRegex:
          path: spec.template.spec.containers[0].image
          pattern: "myregistry.example.com/govsso-mock:2.0.0"

  - it: exposes named port https on 10443
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
    asserts:
      - equal:
          path: spec.template.spec.containers[0].ports[0].containerPort
          value: 10443
      - equal:
          path: spec.template.spec.containers[0].ports[0].name
          value: https

  - it: mounts config files with subPath
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
    asserts:
      - contains:
          path: spec.template.spec.containers[0].volumeMounts
          content:
            name: config
            mountPath: /govsso-mock/config/config.json
            subPath: config.json
            readOnly: true
      - contains:
          path: spec.template.spec.containers[0].volumeMounts
          content:
            name: config
            mountPath: /govsso-mock/config/users.json
            subPath: users.json
            readOnly: true
      - contains:
          path: spec.template.spec.containers[0].volumeMounts
          content:
            name: tls
            mountPath: /govsso-mock/config/tls/govsso-mock
            readOnly: true
      - contains:
          path: spec.template.spec.containers[0].volumeMounts
          content:
            name: id-token
            mountPath: /govsso-mock/config/id-token
            readOnly: true

  - it: mounts the tls secret by existingSecret name
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: my-tls-secret
      idToken.existingSecret: my-id-secret
    asserts:
      - contains:
          path: spec.template.spec.volumes
          content:
            name: tls
            secret:
              secretName: my-tls-secret
      - contains:
          path: spec.template.spec.volumes
          content:
            name: id-token
            secret:
              secretName: my-id-secret

  - it: applies container security context when enabled
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
      containerSecurityContext.enabled: true
    asserts:
      - equal:
          path: spec.template.spec.containers[0].securityContext.runAsNonRoot
          value: true
      - equal:
          path: spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem
          value: true
      - equal:
          path: spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation
          value: false

  - it: enables liveness probe with HTTPS scheme
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
      livenessProbe.enabled: true
    asserts:
      - equal:
          path: spec.template.spec.containers[0].livenessProbe.httpGet.scheme
          value: HTTPS
      - equal:
          path: spec.template.spec.containers[0].livenessProbe.httpGet.path
          value: /
      - equal:
          path: spec.template.spec.containers[0].livenessProbe.httpGet.port
          value: https

  - it: omits liveness probe when disabled
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
      livenessProbe.enabled: false
    asserts:
      - isNull:
          path: spec.template.spec.containers[0].livenessProbe
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
helm unittest charts/govsso-mock -f tests/deployment_test.yaml 2>&1
```

- [ ] **Step 3: Write deployment.yaml**

```yaml
{{/* charts/govsso-mock/templates/deployment.yaml */}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "govsso-mock.fullname" . }}
  namespace: {{ .Release.Namespace | quote }}
  labels: {{- include "govsso-mock.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels: {{- include "govsso-mock.matchLabels" . | nindent 6 }}
  template:
    metadata:
      labels: {{- include "govsso-mock.labels" . | nindent 8 }}
    spec:
      {{- with include "common.images.pullSecrets" (dict "images" (list .Values.image) "global" .Values.global) | trim }}
      imagePullSecrets: {{- . | nindent 6 }}
      {{- end }}
      serviceAccountName: {{ include "govsso-mock.serviceAccountName" . }}
      {{- if .Values.podSecurityContext.enabled }}
      securityContext:
        fsGroup: {{ .Values.podSecurityContext.fsGroup }}
      {{- end }}
      containers:
        - name: govsso-mock
          image: {{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          {{- if .Values.containerSecurityContext.enabled }}
          securityContext:
            runAsUser: {{ .Values.containerSecurityContext.runAsUser }}
            runAsNonRoot: {{ .Values.containerSecurityContext.runAsNonRoot }}
            readOnlyRootFilesystem: {{ .Values.containerSecurityContext.readOnlyRootFilesystem }}
            allowPrivilegeEscalation: {{ .Values.containerSecurityContext.allowPrivilegeEscalation }}
          {{- end }}
          ports:
            - name: https
              containerPort: 10443
              protocol: TCP
          {{- if .Values.livenessProbe.enabled }}
          livenessProbe:
            httpGet:
              path: /
              port: https
              scheme: HTTPS
            initialDelaySeconds: {{ .Values.livenessProbe.initialDelaySeconds }}
            periodSeconds: {{ .Values.livenessProbe.periodSeconds }}
            timeoutSeconds: {{ .Values.livenessProbe.timeoutSeconds }}
            failureThreshold: {{ .Values.livenessProbe.failureThreshold }}
            successThreshold: {{ .Values.livenessProbe.successThreshold }}
          {{- end }}
          {{- if .Values.readinessProbe.enabled }}
          readinessProbe:
            httpGet:
              path: /
              port: https
              scheme: HTTPS
            initialDelaySeconds: {{ .Values.readinessProbe.initialDelaySeconds }}
            periodSeconds: {{ .Values.readinessProbe.periodSeconds }}
            timeoutSeconds: {{ .Values.readinessProbe.timeoutSeconds }}
            failureThreshold: {{ .Values.readinessProbe.failureThreshold }}
            successThreshold: {{ .Values.readinessProbe.successThreshold }}
          {{- end }}
          {{- with .Values.resources }}
          resources: {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.extraEnv }}
          env: {{- toYaml . | nindent 12 }}
          {{- end }}
          volumeMounts:
            - name: config
              mountPath: /govsso-mock/config/config.json
              subPath: config.json
              readOnly: true
            - name: config
              mountPath: /govsso-mock/config/users.json
              subPath: users.json
              readOnly: true
            - name: config
              mountPath: /govsso-mock/config/clients.json
              subPath: clients.json
              readOnly: true
            - name: tls
              mountPath: /govsso-mock/config/tls/govsso-mock
              readOnly: true
            - name: id-token
              mountPath: /govsso-mock/config/id-token
              readOnly: true
            {{- with .Values.extraVolumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
      volumes:
        - name: config
          configMap:
            name: {{ include "govsso-mock.fullname" . }}
        - name: tls
          secret:
            secretName: {{ .Values.tls.existingSecret }}
        - name: id-token
          secret:
            secretName: {{ .Values.idToken.existingSecret }}
        {{- with .Values.extraVolumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector: {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations: {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity: {{- toYaml . | nindent 8 }}
      {{- end }}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
helm unittest charts/govsso-mock -f tests/deployment_test.yaml 2>&1
```

- [ ] **Step 5: Commit**

```bash
git add charts/govsso-mock/templates/deployment.yaml charts/govsso-mock/tests/deployment_test.yaml
git commit -m "feat(helm): add deployment.yaml with volume mounts and security context"
```

---

## Task 9: `NOTES.txt`

**Files:**
- Create: `charts/govsso-mock/templates/NOTES.txt`

- [ ] **Step 1: Write NOTES.txt**

```
{{/* charts/govsso-mock/templates/NOTES.txt */}}
GovSSO-Mock has been deployed.

  Service: {{ include "govsso-mock.fullname" . }}.{{ .Release.Namespace }}.svc.cluster.local:{{ .Values.service.port }}

IMPORTANT — Required secrets must exist before the pod can start:

  tls.existingSecret: {{ .Values.tls.existingSecret | default "(NOT SET — chart validation should have caught this)" }}
    Required keys:
      tls.crt  — PEM-encoded TLS certificate
      tls.key  — PEM-encoded TLS private key

  idToken.existingSecret: {{ .Values.idToken.existingSecret | default "(NOT SET)" }}
    Required keys:
      id-token-sign.key.pem  — PEM-encoded RSA private key (JWT signing)
      id-token-sign.pub.pem  — PEM-encoded RSA public key (JWKS endpoint)

{{- if index .Values "example-client" | dig "enabled" false }}

Example client is ENABLED.
  Service: {{ .Release.Name }}-example-client.{{ .Release.Namespace }}.svc.cluster.local:11443

  example-client.tls.existingSecret must contain:
    keystore.p12   — PKCS12 keystore for the example client TLS certificate
    truststore.p12 — PKCS12 truststore containing the mock's CA certificate
{{- end }}
```

- [ ] **Step 2: Verify NOTES.txt renders during template**

```bash
helm template test charts/govsso-mock \
  --set image.repository=testrepo \
  --set image.tag=1.0 \
  --set tls.existingSecret=my-tls \
  --set idToken.existingSecret=my-id 2>&1 | grep -A 20 "NOTES:"
```

Expected: Shows the service address and secret requirements.

- [ ] **Step 3: Commit**

```bash
git add charts/govsso-mock/templates/NOTES.txt
git commit -m "feat(helm): add NOTES.txt with post-install instructions"
```

---

## Task 10: `values.schema.json` + schema validation test

**Files:**
- Create: `charts/govsso-mock/values.schema.json`
- Create: `charts/govsso-mock/tests/schema_test.yaml`

- [ ] **Step 1: Write schema validation test**

```yaml
# charts/govsso-mock/tests/schema_test.yaml
suite: schema validation
templates:
  - templates/configmap.yaml  # just needs any template to trigger schema validation
tests:
  - it: passes with all required values set
    set:
      image.repository: testrepo
      image.tag: "1.0"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
    asserts:
      - isKind:
          of: ConfigMap

  - it: uses digest instead of tag
    set:
      image.repository: testrepo
      image.tag: ""
      image.digest: "sha256:abc123def456"
      tls.existingSecret: test-tls
      idToken.existingSecret: test-id
    asserts:
      - isKind:
          of: ConfigMap
```

- [ ] **Step 2: Run schema test — expect PASS (schema doesn't exist yet, so no validation failure)**

```bash
helm unittest charts/govsso-mock -f tests/schema_test.yaml 2>&1
```

- [ ] **Step 3: Write values.schema.json**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["image", "tls", "idToken"],
  "properties": {
    "image": {
      "type": "object",
      "required": ["repository"],
      "properties": {
        "repository": {
          "type": "string",
          "minLength": 1,
          "description": "Container image repository. Required — no default is provided."
        },
        "tag": {
          "type": "string",
          "description": "Image tag. Either tag or digest must be non-empty."
        },
        "digest": {
          "type": "string",
          "description": "Image digest (sha256:...). Takes precedence over tag if non-empty."
        },
        "pullPolicy": {
          "type": "string",
          "enum": ["Always", "IfNotPresent", "Never"]
        },
        "pullSecrets": {
          "type": "array",
          "items": { "type": "string" }
        }
      },
      "anyOf": [
        {
          "properties": { "tag": { "type": "string", "minLength": 1 } },
          "required": ["tag"]
        },
        {
          "properties": { "digest": { "type": "string", "minLength": 1 } },
          "required": ["digest"]
        }
      ]
    },
    "tls": {
      "type": "object",
      "required": ["existingSecret"],
      "properties": {
        "existingSecret": {
          "type": "string",
          "minLength": 1,
          "description": "Name of existing Secret. Required keys: tls.crt, tls.key"
        }
      }
    },
    "idToken": {
      "type": "object",
      "required": ["existingSecret"],
      "properties": {
        "existingSecret": {
          "type": "string",
          "minLength": 1,
          "description": "Name of existing Secret. Required keys: id-token-sign.key.pem, id-token-sign.pub.pem"
        }
      }
    },
    "replicaCount": { "type": "integer", "minimum": 0 },
    "config": {
      "type": "object",
      "properties": {
        "host":              { "type": "string" },
        "serverPort":        { "type": "string" },
        "baseHref":          { "type": "string" },
        "idTokenSignKeyId":  { "type": "string" }
      }
    },
    "users":   { "type": "array" },
    "clients": { "type": "array" },
    "serviceAccount": {
      "type": "object",
      "properties": {
        "create":      { "type": "boolean" },
        "name":        { "type": "string" },
        "annotations": { "type": "object" }
      }
    },
    "service": {
      "type": "object",
      "properties": {
        "type": { "type": "string", "enum": ["ClusterIP", "NodePort", "LoadBalancer"] },
        "port": { "type": "integer" }
      }
    },
    "example-client": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean" }
      },
      "if": {
        "properties": { "enabled": { "const": true } },
        "required": ["enabled"]
      },
      "then": {
        "required": ["clientId", "govSsoIssuerUri", "redirectUri", "postLogoutRedirectUri"],
        "properties": {
          "clientId":                { "type": "string", "minLength": 1 },
          "govSsoIssuerUri":         { "type": "string", "minLength": 1 },
          "redirectUri":             { "type": "string", "minLength": 1 },
          "postLogoutRedirectUri":   { "type": "string", "minLength": 1 },
          "tls": {
            "type": "object",
            "required": ["existingSecret"],
            "properties": {
              "existingSecret": { "type": "string", "minLength": 1 }
            }
          }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Verify schema rejects missing tls.existingSecret**

```bash
helm template test charts/govsso-mock \
  --set image.repository=testrepo \
  --set image.tag=1.0 \
  --set idToken.existingSecret=my-id 2>&1
```

Expected: Error mentioning `tls.existingSecret` is required / fails validation.

- [ ] **Step 5: Verify schema rejects missing image.repository**

```bash
helm template test charts/govsso-mock \
  --set image.tag=1.0 \
  --set tls.existingSecret=my-tls \
  --set idToken.existingSecret=my-id 2>&1
```

Expected: Error mentioning `image.repository`.

- [ ] **Step 6: Verify schema accepts digest instead of tag**

```bash
helm template test charts/govsso-mock \
  --set image.repository=testrepo \
  --set 'image.digest=sha256:abc123' \
  --set tls.existingSecret=my-tls \
  --set idToken.existingSecret=my-id 2>&1 | grep -c "kind: ConfigMap"
```

Expected: `1` (rendered successfully).

- [ ] **Step 7: Run schema_test.yaml**

```bash
helm unittest charts/govsso-mock -f tests/schema_test.yaml 2>&1
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add charts/govsso-mock/values.schema.json charts/govsso-mock/tests/schema_test.yaml
git commit -m "feat(helm): add values.schema.json with required field validation"
```

---

## Task 11: Run full lint on main chart

**Files:** No new files — verification only.

- [ ] **Step 1: Run all unit tests**

```bash
helm unittest charts/govsso-mock 2>&1
```

Expected: All test suites PASS (5 suites: configmap, serviceaccount, service, deployment, schema).

- [ ] **Step 2: Run helm lint with required values**

```bash
helm lint charts/govsso-mock \
  --set image.repository=testrepo \
  --set image.tag=1.0 \
  --set tls.existingSecret=my-tls \
  --set idToken.existingSecret=my-id 2>&1
```

Expected: `1 chart(s) linted, 0 chart(s) failed`.

- [ ] **Step 3: Render all templates and inspect output**

```bash
helm template my-release charts/govsso-mock \
  --set image.repository=testrepo \
  --set image.tag=1.0 \
  --set tls.existingSecret=my-tls \
  --set idToken.existingSecret=my-id \
  --debug 2>&1
```

Expected: Renders Deployment, Service, ServiceAccount, ConfigMap without errors. Verify config.json contains correct paths.

---

## Task 12: example-client subchart

**Files:**
- Create: `charts/govsso-mock/charts/example-client/Chart.yaml`
- Create: `charts/govsso-mock/charts/example-client/values.yaml`
- Create: `charts/govsso-mock/charts/example-client/templates/_helpers.tpl`
- Create: `charts/govsso-mock/charts/example-client/templates/deployment.yaml`
- Create: `charts/govsso-mock/charts/example-client/templates/service.yaml`
- Create: `charts/govsso-mock/charts/example-client/tests/deployment_test.yaml`

- [ ] **Step 1: Write example-client/Chart.yaml**

```yaml
# charts/govsso-mock/charts/example-client/Chart.yaml
apiVersion: v2
name: example-client
description: Optional example client for demonstrating GovSSO authentication flows
type: application
version: 0.1.0
appVersion: "0.7.3"
```

- [ ] **Step 2: Write example-client/values.yaml**

```yaml
# charts/govsso-mock/charts/example-client/values.yaml
# Default values — overridden by parent chart's "example-client:" section.

enabled: false

image:
  repository: ghcr.io/e-gov/tara-govsso-exampleclient
  tag: "0.7.3"
  digest: ""
  pullPolicy: IfNotPresent

clientId: "example-client-id"
clientSecret: ""
existingSecret: ""

govSsoIssuerUri: ""
redirectUri: ""
postLogoutRedirectUri: ""

tls:
  existingSecret: ""
  keystorePassword: "changeit"
  truststorePassword: "changeit"

springProfile: "govsso"
messagesTitle: "GovSSO Client"
jvmThreadCount: "10"

service:
  type: ClusterIP
  port: 11443

resources: {}
```

- [ ] **Step 3: Write example-client/templates/_helpers.tpl**

```
{{/* charts/govsso-mock/charts/example-client/templates/_helpers.tpl */}}

{{- define "example-client.fullname" -}}
{{- printf "%s-example-client" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "example-client.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: example-client
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- end }}

{{- define "example-client.matchLabels" -}}
app.kubernetes.io/name: example-client
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end }}
```

- [ ] **Step 4: Write the unit test first (TDD)**

```yaml
# charts/govsso-mock/charts/example-client/tests/deployment_test.yaml
suite: example-client deployment
templates:
  - templates/deployment.yaml
tests:
  - it: renders no resources when disabled
    set:
      enabled: false
    asserts:
      - hasDocuments:
          count: 0

  - it: renders Deployment when enabled
    set:
      enabled: true
      govSsoIssuerUri: https://govsso-mock.example.com/
      redirectUri: https://client.example.com/login/oauth2/code/govsso
      postLogoutRedirectUri: https://client.example.com/
      tls.existingSecret: client-tls
    asserts:
      - isKind:
          of: Deployment
      - equal:
          path: spec.template.spec.containers[0].name
          value: example-client

  - it: sets SPRING_PROFILES_ACTIVE to govsso by default
    set:
      enabled: true
      govSsoIssuerUri: https://govsso-mock.example.com/
      redirectUri: https://client.example.com/callback
      postLogoutRedirectUri: https://client.example.com/
      tls.existingSecret: client-tls
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: SPRING_PROFILES_ACTIVE
            value: "govsso"

  - it: sets govsso.issuer-uri env var from values
    set:
      enabled: true
      govSsoIssuerUri: https://my-govsso.example.com/
      redirectUri: https://client.example.com/callback
      postLogoutRedirectUri: https://client.example.com/
      tls.existingSecret: client-tls
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: govsso.issuer-uri
            value: "https://my-govsso.example.com/"

  - it: uses secretKeyRef for client-secret when existingSecret is set
    set:
      enabled: true
      govSsoIssuerUri: https://govsso-mock.example.com/
      redirectUri: https://client.example.com/callback
      postLogoutRedirectUri: https://client.example.com/
      tls.existingSecret: client-tls
      existingSecret: my-client-secret
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: govsso.client-secret
            valueFrom:
              secretKeyRef:
                name: my-client-secret
                key: client-secret

  - it: mounts tls secret at correct path
    set:
      enabled: true
      govSsoIssuerUri: https://govsso-mock.example.com/
      redirectUri: https://client.example.com/callback
      postLogoutRedirectUri: https://client.example.com/
      tls.existingSecret: my-client-tls
    asserts:
      - contains:
          path: spec.template.spec.containers[0].volumeMounts
          content:
            name: tls
            mountPath: /var/local/config/tls
            readOnly: true
      - contains:
          path: spec.template.spec.volumes
          content:
            name: tls
            secret:
              secretName: my-client-tls
```

- [ ] **Step 5: Run tests — expect FAIL**

```bash
helm unittest charts/govsso-mock/charts/example-client -f tests/deployment_test.yaml 2>&1
```

- [ ] **Step 6: Write example-client/templates/deployment.yaml**

```yaml
{{/* charts/govsso-mock/charts/example-client/templates/deployment.yaml */}}
{{- if .Values.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "example-client.fullname" . }}
  namespace: {{ .Release.Namespace | quote }}
  labels: {{- include "example-client.labels" . | nindent 4 }}
spec:
  replicas: 1
  selector:
    matchLabels: {{- include "example-client.matchLabels" . | nindent 6 }}
  template:
    metadata:
      labels: {{- include "example-client.labels" . | nindent 8 }}
    spec:
      containers:
        - name: example-client
          image: {{ printf "%s:%s" .Values.image.repository .Values.image.tag | quote }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            - name: server.port
              value: "11443"
            - name: govsso.client-id
              value: {{ .Values.clientId | quote }}
            - name: govsso.client-secret
              {{- if .Values.existingSecret }}
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.existingSecret | quote }}
                  key: client-secret
              {{- else }}
              value: {{ .Values.clientSecret | quote }}
              {{- end }}
            - name: govsso.redirect-uri
              value: {{ .Values.redirectUri | quote }}
            - name: govsso.post-logout-redirect-uri
              value: {{ .Values.postLogoutRedirectUri | quote }}
            - name: govsso.issuer-uri
              value: {{ .Values.govSsoIssuerUri | quote }}
            - name: govsso.trust-store
              value: "file:/var/local/config/tls/truststore.p12"
            - name: govsso.trust-store-password
              value: {{ .Values.tls.truststorePassword | quote }}
            - name: server.ssl.key-store
              value: "file:/var/local/config/tls/keystore.p12"
            - name: server.ssl.key-store-type
              value: "PKCS12"
            - name: server.ssl.key-store-password
              value: {{ .Values.tls.keystorePassword | quote }}
            - name: SPRING_PROFILES_ACTIVE
              value: {{ .Values.springProfile | quote }}
            - name: example-client.messages.title
              value: {{ .Values.messagesTitle | quote }}
            - name: BPL_JVM_THREAD_COUNT
              value: {{ .Values.jvmThreadCount | quote }}
          ports:
            - name: https
              containerPort: 11443
              protocol: TCP
          {{- with .Values.resources }}
          resources: {{- toYaml . | nindent 12 }}
          {{- end }}
          volumeMounts:
            - name: tls
              mountPath: /var/local/config/tls
              readOnly: true
      volumes:
        - name: tls
          secret:
            secretName: {{ .Values.tls.existingSecret }}
{{- end }}
```

- [ ] **Step 7: Write example-client/templates/service.yaml**

```yaml
{{/* charts/govsso-mock/charts/example-client/templates/service.yaml */}}
{{- if .Values.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "example-client.fullname" . }}
  namespace: {{ .Release.Namespace | quote }}
  labels: {{- include "example-client.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - name: https
      port: {{ .Values.service.port }}
      targetPort: https
      protocol: TCP
  selector: {{- include "example-client.matchLabels" . | nindent 4 }}
{{- end }}
```

- [ ] **Step 8: Run tests — expect PASS**

```bash
helm unittest charts/govsso-mock/charts/example-client -f tests/deployment_test.yaml 2>&1
```

- [ ] **Step 9: Verify main chart lint still passes with example-client enabled**

```bash
helm lint charts/govsso-mock \
  --set image.repository=testrepo \
  --set image.tag=1.0 \
  --set tls.existingSecret=my-tls \
  --set idToken.existingSecret=my-id \
  --set 'example-client.enabled=true' \
  --set 'example-client.govSsoIssuerUri=https://govsso.example.com/' \
  --set 'example-client.clientId=example-client-id' \
  --set 'example-client.redirectUri=https://client.example.com/cb' \
  --set 'example-client.postLogoutRedirectUri=https://client.example.com/' \
  --set 'example-client.tls.existingSecret=client-tls' 2>&1
```

Expected: `1 chart(s) linted, 0 chart(s) failed`.

- [ ] **Step 10: Commit**

```bash
git add charts/govsso-mock/charts/example-client/
git commit -m "feat(helm): add optional example-client subchart"
```

---

## Task 13: Final verification and full test run

**Files:** No new files — verification only.

- [ ] **Step 1: Run all unit tests across both charts**

```bash
helm unittest charts/govsso-mock && helm unittest charts/govsso-mock/charts/example-client 2>&1
```

Expected: All suites PASS, 0 failures.

- [ ] **Step 2: Full template render — main chart only**

```bash
helm template production charts/govsso-mock \
  --set image.repository=ghcr.io/e-gov/govsso-mock \
  --set image.tag=1.0.0 \
  --set tls.existingSecret=govsso-mock-tls \
  --set idToken.existingSecret=govsso-mock-id-token \
  --set config.host=govsso-mock.dev.example.com \
  --namespace govsso 2>&1
```

Expected: Valid YAML for ConfigMap, Deployment, Service, ServiceAccount. Verify:
- ConfigMap `data["config.json"]` has `"host":"govsso-mock.dev.example.com"` and correct file paths
- Deployment has `tls` and `id-token` volume mounts at correct paths
- Deployment container port named `https` on `10443`

- [ ] **Step 3: Full template render — with example client**

```bash
helm template production charts/govsso-mock \
  --set image.repository=ghcr.io/e-gov/govsso-mock \
  --set image.tag=1.0.0 \
  --set tls.existingSecret=govsso-mock-tls \
  --set idToken.existingSecret=govsso-mock-id-token \
  --set 'example-client.enabled=true' \
  --set 'example-client.govSsoIssuerUri=https://govsso-mock.dev.example.com/' \
  --set 'example-client.clientId=example-client-id' \
  --set 'example-client.redirectUri=https://client.dev.example.com/login/oauth2/code/govsso' \
  --set 'example-client.postLogoutRedirectUri=https://client.dev.example.com/' \
  --set 'example-client.tls.existingSecret=example-client-tls' \
  --namespace govsso 2>&1
```

Expected: Renders 6 resources total (ConfigMap, Deployment×2, Service×2, ServiceAccount). Verify:
- Example client Deployment has `SPRING_PROFILES_ACTIVE=govsso` env var
- Example client TLS mounted at `/var/local/config/tls`

- [ ] **Step 4: Verify schema rejects invalid config**

```bash
helm template test charts/govsso-mock \
  --set image.repository=testrepo \
  --set image.tag=1.0 \
  --set tls.existingSecret="" \
  --set idToken.existingSecret=my-id 2>&1
```

Expected: Schema validation error mentioning `tls.existingSecret`.

- [ ] **Step 5: Commit final state**

```bash
git add charts/
git commit -m "feat(helm): complete GovSSO-Mock Helm chart with example-client subchart"
```
