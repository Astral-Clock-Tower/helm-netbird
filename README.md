<p align="center">
  <img width="234" src="https://github.com/netbirdio/netbird/raw/main/docs/media/logo-full.png" style="vertical-align: middle; margin: 0 1.5rem" />
  <img src="https://github.com/kubernetes/kubernetes/raw/master/logo/logo.png" width="60" style="vertical-align: middle;" />
</p>

# Netbird Helm Chart

This chart provides a means of deploying Netbird to kubernetes.


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
       vpn: myvpn.example.com  # The domain to be used for VPN clients.  Will default to global domain if not set.
     server:
       encryption_key: ''  # `openssl rand -base64 32`
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
| global.namespace                  | Namespace for Netbird                                                                                | `'netbird'`              |
| global.domain.global              | Domain name used for access (e.g. netbird.example.com)                                               | `''`                     |
| global.domain.vpn                 | Domain name used for peer overlay network (eg peer1.netbird-vpn.example.com)                         | `<global.domain.global>` |
| global.dashboard.port             | Dashboard HTTP port                                                                                  | `80`                     |
| global.server.port                | Server HTTP port                                                                                     | `80`                     |
| global.server.stun_port           | Server STUN port                                                                                     | `3478`                   |
| global.route.enabled              | Enable GatewayAPI access                                                                             | `false`                  |
| global.route.vendor               | Type of GatewayAPI installed, eg. `envoy`.  Automatically installs traffic policies to fix timeouts. | `''`                     |
| global.route.parentRefs           | The gateway parentRefs                                                                               | `[]`                     |
| global.route.stunParentRefs       | STUN likely uses a different port in the gateway, so you can specify a different parent ref here     | `[]`                     |
| global.route.annotations          | Annotations to apply to GatewayAPI resources                                                         | `{}`                     |
| global.serviceAccount.create      | Create service account                                                                               | `true`                   |
| global.serviceAccount.automount   | Auto-mount service account                                                                           | `true`                   |
| global.serviceAccount.annotations | Service account annotations                                                                          | `{}`                     |
| global.serviceAccount.name        | Service account name                                                                                 | `""`                     |

## Component Specific Settings

| config                             | description                | default                      |
|------------------------------------|----------------------------|------------------------------|
| dashboard.image.repository         | Dashboard image repository | `'netbirdio/dashboard'`      |
| dashboard.image.tag                | Dashboard image tag        | `'v2.33.0'`                  |
| dashboard.image.pullPolicy         | Image pull policy          | `'IfNotPresent'`             |
| dashboard.annotations              | Pod annotations            | `{}`                         |
| dashboard.labels                   | Pod labels                 | `{}`                         |
| dashboard.nodeSelector             | Node selector              | `{}`                         |
| dashboard.tolerations              | Tolerations array          | `[]`                         |
| dashboard.affinity                 | Affinity rules             | `{}`                         |
| dashboard.replicaCount             | Replica count              | `1`                          |
| dashboard.resources                | Resource limits/requests   | `{}`                         |
| dashboard.livenessProbe            | Liveness probe settings    |                              |
| dashboard.readinessProbe           | Readiness probe settings   |                              |
| dashboard.service.type             | Dashboard service type     | `'ClusterIP'`                |
| dashboard.extra_volumes            | Additional volumes         | `[]`                         |
| dashboard.extra_volumeMounts       | Additional volume mounts   | `[]`                         |
| **Server**                         |                            |                              |
| server.image.repository            | Server image repository    | `'netbirdio/netbird-server'` |
| server.image.tag                   | Server image tag           | `'0.66.0'`                   |
| server.image.pullPolicy            | Image pull policy          | `'IfNotPresent'`             |
| server.annotations                 | Pod annotations            | `{}`                         |
| server.labels                      | Pod labels                 | `{}`                         |
| server.nodeSelector                | Node selector              | `{}`                         |
| server.tolerations                 | Tolerations                | `[]`                         |
| server.affinity                    | Affinity rules             | `{}`                         |
| server.replicaCount                | Replica count              | `1`                          |
| server.resources                   | Resource limits/requests   | `{}`                         |
| server.livenessProbe               | Liveness probe settings    |                              |
| server.readinessProbe              | Readiness probe settings   |                              |
| server.service.type                | Service type               | `'ClusterIP'`                |
| server.extra_volumes               | Additional volumes         | `[]`                         |
| server.extra_volumeMounts          | Additional volume mounts   | `[]`                         |
| server.extra_args                  | Additional CLI arguments   | `[]`                         |
| server.persistence.enabled         | Enable persistence         | `true`                       |
| server.persistence.storageClass    | Storage class name         |                              |
| server.persistence.volumeName      | Name of persistent volume  | `'data'`                     |
| server.persistence.existingClaim   | Use existing PVC           | `''`                         |
| server.persistence.mountPath       | Where to mount storage     | `'/var/lib/netbird'`         |
| server.persistence.configMountPath | Where to mount config      | `'/etc/netbird/config.yaml'` |
| server.persistence.subPath         | SubPath for mount          | `''`                         |
| server.persistence.accessModes     | AccessModes list           | `[ReadWriteOnce]`            |
| server.persistence.size            | Requested disk size        | `'1Gi'`                      |
| server.persistence.volumeMode      | Volume mode                |                              |
| server.persistence.annotations     | Volume/PVC annotations     | `{}`                         |
| server.persistence.labels          | Volume/PVC labels          | `{}`                         |
| server.persistence.selector        | Selector map for PVC       | `{}`                         |
| server.persistence.dataSource      | PVC data source            | `{}`                         |

