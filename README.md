<p align="center">
  <img width="234" src="https://github.com/netbirdio/netbird/raw/main/docs/media/logo-full.png" style="vertical-align: middle; margin: 0 1.5rem" />
  <img src="https://github.com/kubernetes/kubernetes/raw/master/logo/logo.png" width="60" style="vertical-align: middle;" />
</p>

# Netbird Helm Chart

This chart provides a means of deploying Netbird to kubernetes.

Upgrading, or coming from [cclloyd/helm-netbird](https://github.com/cclloyd/helm-netbird)?
See [CHANGELOG.md](CHANGELOG.md).


---

# Minimal Setup

To use the minimal setup, you will require

- A working kubernetes cluster with GatewayAPI enabled
- A default storage class with space to provision a PVC (default 4Gi)
- A valid hostname and the ability to access it via https and UDP 3478 through the Gateway

1. Fill out the required config
   ```yaml
   global:
     domain: 
       global: netbird.example.com
     server:
       encryption_key: ''  # `openssl rand -base64 32`
       auth_secret: ''     # `openssl rand -base64 32`
     route:
       enabled: true
       vendor: 'envoy'  # Will automatically set timeoutes.  If not using envoy, you may have to adjust timeouts manually.
       parentRefs:
         - name: eg
           namespace: eg
           sectionName: https
       stunParentRefs:
         - name: eg
           namespace: eg
           sectionName: netbird-stun
   # If upgrading from pre v0.66.0, you may need to adjust your persistence subPath, as the default was changed to `server`.
   # server:
   #   persistence:
   #     subPath: 'management'
   ```
2. Ensure your chosen ports are accessible to the gateway (default 443 TCP/3478 UDP).
3. Run helm install (recommend pinning a specific chart version instead of latest)
   ```shell
   helm install netbird oci://ghcr.io/cclloyd/helm-netbird/netbird --version 0.0.0-latest -n netbird -f path/to/values.yaml
   ```
4. Once it's done setting itself, up, access it at your external URL. Once you go through the setup, you can enable
   additional auth options.

---

# Full Configuration

## Global Settings

| config                            | description                                                                                          | default                  |
|-----------------------------------|------------------------------------------------------------------------------------------------------|--------------------------|
| global.domain.global              | Domain name used for access (e.g. netbird.example.com)                                               | `''`                     |
| global.dashboard.port             | Dashboard HTTP port                                                                                  | `80`                     |
| global.server.port                | Server HTTP port                                                                                     | `80`                     |
| global.server.stun_port           | Server STUN port                                                                                     | `3478`                   |
| global.server.metrics.port        | Port NetBird serves Prometheus metrics on (config `metricsPort`)                                     | `9090`                   |
| global.server.metrics.exposed     | Publish that port as a container port and on the `-server-http` Service                              | `true`                   |
| global.server.legacyGrpc.port     | Port of NetBird's gRPC listener for pre-v0.29 peers                                                  | `33073`                  |
| global.server.legacyGrpc.exposed  | Publish that port.  Only needed if you have pre-v0.29 peers                                          | `false`                  |
| global.server.stun.enabled        | Serve STUN from the server pod: config `stunPorts`, container port, Service port and UDPRoute        | `true`                   |
| global.server.stun.port           | Server STUN port.  Overrides `stun_port` when set.                                                   | `<global.server.stun_port>` |
| global.server.stun.external       | External STUN servers to advertise to peers, eg `['stun:stun.l.google.com:19302']`                   | `[]`                     |
| global.server.reverseProxy        | Passed through to NetBird's `reverseProxy` config block; empty fields are omitted                    | see `values.yaml`        |
| global.server.encryption_key      | Data store encryption key.  Required.                                                                | `''`                     |
| global.server.auth_secret         | Shared HMAC secret the relay uses to validate peer tokens.  Required.                                | `''`                     |
| global.server.existingConfigSecret | Name of a Secret holding the whole `config.yaml`.  Suppresses the chart's own config Secret; the render fails if a config-only value is also set. | `''`                     |
| global.persistence.enabled        | Enable persistence                                                                                   | `true`                   |
| global.persistence.storageClass   | PVC storage class.  Unset lets the cluster default decide; `''` means bind a pre-created PV.         |                          |
| global.persistence.volumeName     | Name of the volume, and the suffix of the generated PVC                                              | `'data'`                 |
| global.persistence.existingClaim  | Use an existing PVC instead of rendering one                                                         | `''`                     |
| global.persistence.accessModes    | AccessModes list                                                                                     | `[ReadWriteOnce]`        |
| global.persistence.size           | Requested disk size                                                                                  | `4Gi`                    |
| global.persistence.volumeMode     | Volume mode                                                                                          |                          |
| global.persistence.annotations    | PVC annotations                                                                                      | `{}`                     |
| global.persistence.labels         | PVC labels                                                                                           | `{}`                     |
| global.persistence.selector       | Selector map for the PVC                                                                             | `{}`                     |
| global.persistence.dataSource     | PVC data source                                                                                      | `{}`                     |
| global.route.enabled              | Enable GatewayAPI access                                                                             | `false`                  |
| global.route.vendor               | Type of GatewayAPI installed, eg. `envoy`.  Automatically installs traffic policies to fix timeouts. | `''`                     |
| global.route.parentRefs           | The gateway parentRefs                                                                               | `[]`                     |
| global.route.stunParentRefs       | STUN likely uses a different port in the gateway, so you can specify a different parent ref here     | `[]`                     |
| global.route.apiTimeout           | Timeout for `/api` and `/oauth2`.  Streaming paths always use `0s`.                                  | `'3600s'`                |
| global.route.annotations          | Annotations to apply to GatewayAPI resources                                                         | `{}`                     |
| global.route.dashboardAnnotations | Merged over `annotations` for the dashboard route alone                                              | `{}`                     |
| global.route.serverAnnotations    | Merged over `annotations` for the server routes alone                                                | `{}`                     |
| global.route.stunAnnotations      | Merged over `annotations` for the STUN route alone                                                   | `{}`                     |
| global.auth.issuerUrl             | Issuer the server validates tokens against.  Falls back to `authority`.                              | `<global.auth.authority>` |
| global.auth.authority             | OIDC provider the dashboard talks to                                                                 | `https://<domain.global>/oauth2` |
| global.auth.clientId              | OIDC client id                                                                                       | `netbird-dashboard`      |
| global.auth.clientSecret          | OIDC client secret.  Prefer `existingSecret`.                                                        | `''`                     |
| global.auth.existingSecret        | Secret holding the OIDC client credentials                                                           | `''`                     |
| global.auth.existingSecretClientIdKey | Key to read the client id from inside `existingSecret`                                           | `clientId`               |
| global.auth.existingSecretClientSecretKey | Key to read the client secret from inside `existingSecret`                                   | `clientSecret`           |
| global.auth.publicClient          | Client uses PKCE and has no secret; stops reading a client-secret key at all                         | `false`                  |
| global.auth.audience              | OIDC audience                                                                                        | `netbird-dashboard`      |
| global.auth.supportedScopes       | OIDC scopes                                                                                          | `openid profile email groups` |
| global.auth.redirectURI           | OIDC redirect URI                                                                                    | `/nb-auth`               |
| global.auth.silentRedirectURI     | OIDC silent redirect URI                                                                             | `/nb-silent-auth`        |
| global.auth.useAuth0              | Use Auth0                                                                                            | `false`                  |
| global.serviceAccount.create      | Create service account                                                                               | `true`                   |
| global.serviceAccount.automount   | Auto-mount service account                                                                           | `true`                   |
| global.serviceAccount.annotations | Service account annotations                                                                          | `{}`                     |
| global.serviceAccount.name        | Service account name                                                                                 | `""`                     |

## Component Specific Settings

| config                             | description                | default                      |
|------------------------------------|----------------------------|------------------------------|
| **Chart**                          |                            |                              |
| nameOverride                       | Replace the chart name     | `''`                         |
| fullnameOverride                   | Replace the whole name     | `''`                         |
| **Dashboard**                      |                            |                              |
| dashboard.image.repository         | Dashboard image repository | `'netbirdio/dashboard'`      |
| dashboard.image.tag                | Dashboard image tag        | `'v2.39.0'`                  |
| dashboard.image.pullPolicy         | Image pull policy          | `'IfNotPresent'`             |
| dashboard.annotations              | Pod annotations            | `{}`                         |
| dashboard.deploymentAnnotations    | Deployment-object annotations (Reloader etc.) | `{}`      |
| dashboard.labels                   | Pod labels                 | `{}`                         |
| dashboard.nodeSelector             | Node selector              | `{}`                         |
| dashboard.tolerations              | Tolerations array          | `[]`                         |
| dashboard.affinity                 | Affinity rules             | `{}`                         |
| dashboard.replicaCount             | Replica count              | `1`                          |
| dashboard.podSecurityContext       | Pod securityContext        | `{}`                         |
| dashboard.securityContext          | Container securityContext  | `{}`                         |
| dashboard.resources                | Resource limits/requests   | `{}`                         |
| dashboard.livenessProbe            | Liveness probe settings    |                              |
| dashboard.readinessProbe           | Readiness probe settings   |                              |
| dashboard.service.type             | Dashboard service type     | `'ClusterIP'`                |
| dashboard.service.annotations      | Dashboard service annotations | `{}`                      |
| dashboard.extra_env                | Additional env vars        | `[]`                         |
| dashboard.extra_volumes            | Additional volumes         | `[]`                         |
| dashboard.extra_volumeMounts       | Additional volume mounts   | `[]`                         |
| **Server**                         |                            |                              |
| server.image.repository            | Server image repository    | `'netbirdio/netbird-server'` |
| server.image.tag                   | Server image tag           | `'0.77.1'`                   |
| server.image.pullPolicy            | Image pull policy          | `'IfNotPresent'`             |
| server.annotations                 | Pod annotations            | `{}`                         |
| server.deploymentAnnotations       | Deployment-object annotations (Reloader etc.) | `{}`      |
| server.reloadOnConfigChange        | Roll the pod when config.yaml changes | `true`             |
| server.labels                      | Pod labels                 | `{}`                         |
| server.nodeSelector                | Node selector              | `{}`                         |
| server.tolerations                 | Tolerations                | `[]`                         |
| server.affinity                    | Affinity rules             | `{}`                         |
| server.replicaCount                | Replica count              | `1`                          |
| server.podSecurityContext          | Pod securityContext        | `{}`                         |
| server.securityContext             | Container securityContext  | `{}`                         |
| server.resources                   | Resource limits/requests   | `{}`                         |
| server.livenessProbe               | Liveness probe settings    |                              |
| server.readinessProbe              | Readiness probe settings   |                              |
| server.service.type                | Service type               | `'ClusterIP'`                |
| server.service.annotations         | Applied to both server Services | `{}`                    |
| server.extra_volumes               | Additional volumes         | `[]`                         |
| server.extra_volumeMounts          | Additional volume mounts   | `[]`                         |
| server.extra_args                  | Additional CLI arguments   | `[]`                         |
| server.persistence.dataDir         | Server `dataDir` in config | `'/var/lib/netbird'`         |
| server.persistence.mountPath       | Where to mount storage     | `'/var/lib/netbird'`         |
| server.persistence.configMountPath | Where to mount config      | `'/etc/netbird/config.yaml'` |
| server.persistence.subPath         | SubPath for mount          | `'server'`                   |

