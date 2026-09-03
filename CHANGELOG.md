# Changelog

This is a fork of [cclloyd/helm-netbird](https://github.com/cclloyd/helm-netbird).
Versions are chart versions, not NetBird versions.

## 2.0.0

Diverges from cclloyd/helm-netbird 1.2.0.

### Breaking

- **`global.server.encryption_key` and `global.server.auth_secret` are now
  required.** A values file that omitted them used to render and now fails.
  Upstream shipped a hardcoded `auth_secret` that is public in its git history,
  so treat any relay token issued under it as compromised and generate a new
  one with `openssl rand -base64 32`.
- **`global.domain.global` is now required when `global.route.enabled` is set.**
  It always was in practice - without it the routes rendered an empty hostname
  that the API server rejects - but the render used to succeed.
- **Both Deployments now run under the chart's ServiceAccount** rather than
  `default`, which the chart created and then never used. If you attached
  `imagePullSecrets` or RBAC to the `default` ServiceAccount in the release
  namespace, move them, or set `global.serviceAccount.create=false` and
  `global.serviceAccount.name=default`.
- **The `-server` Service is h2c-only.** It carries
  `appProtocol: kubernetes.io/h2c` so gRPC works, and HTTP/1.1 traffic moved to
  a new `-server-http` Service. The chart's own routes were repointed; anything
  of yours aimed at `-server` for HTTP - your own HTTPRoute, an Ingress, an
  external probe - has to move to `-server-http`.
- **`global.namespace` is gone; resources follow `--namespace` and Argo's
  destination.** Every object took `metadata.namespace` from that value, which
  defaulted to `netbird`, so `helm -n prod install` recorded the release in
  `prod` and created the resources in `netbird`. An Argo Application with a
  `prod` destination did the same, or failed the sync if the AppProject did not
  permit `netbird`. Templates now use `.Release.Namespace`.

  If your `-n` already matched `global.namespace`, nothing moves. If it did not,
  your resources have been in the namespace named by `global.namespace` all
  along, and this release will try to recreate them under `-n` - including a
  new, **empty** PVC, because PVCs are namespaced and the old one stays where it
  is. The safe move is to keep installing with `-n <the old global.namespace>`
  so nothing relocates; migrate deliberately, with a volume snapshot, if you
  want them somewhere else.

- **The server Deployment uses `strategy: Recreate`.** Upgrades now stop the
  old pod before starting the new one, so they take a short outage instead of
  risking two servers on one sqlite file.
- **Removed values that no template read:** `global.domain.vpn`,
  `global.ingress.*`, `global.persistence.overrideVolume` and
  `global.persistence.overrideVolumeMount`. Setting them never did anything;
  they are gone from `values.yaml` so nobody expects them to.

### Added

- `global.server.existingConfigSecret` - point at a Secret holding the whole
  `config.yaml` and the chart renders none of its own. Fails the render if a
  value that only reaches NetBird through that file is also set.
- `global.auth.*` - issuer, authority, client id, audience, scopes and redirect
  URIs for an external OIDC provider. Credentials come from values or from
  `global.auth.existingSecret`, whose key names are configurable; set
  `global.auth.publicClient` for a PKCE client with no secret.
- `global.route.annotations` applies to every rendered route, with
  `dashboardAnnotations` / `serverAnnotations` / `stunAnnotations` merged over
  it per route.
- `global.server.stun.enabled`, `.port` and `.external` - serve STUN on a
  chosen port, advertise external STUN servers, or turn local STUN off
  entirely.
- `global.route.apiTimeout`, pod and container `securityContext` on both
  components, `dashboard.extra_env`.

### Fixed

- Streaming paths (`/relay`, `/ws-proxy`) get an unlimited request timeout and
  no idle timeout, so long-lived connections stay open.
- The Envoy `BackendTrafficPolicy` namespace is templated instead of hardcoded
  to `ecumene`.
- The `UDPRoute` only renders when `global.route.stunParentRefs` is set, and no
  longer emits a `hostnames` field that `UDPRoute` does not have.
- Service annotations, and the PVC's `volumeMode`, `selector`, `dataSource` and
  `labels`, are honoured - `values.yaml` declared them and no template read
  them.
- `global.persistence.storageClass: ''` now renders `storageClassName: ""`
  (bind a pre-created PV) rather than being treated as unset.

### Changed

- NetBird 0.66.0 -> 0.77.1, dashboard v2.33.0 -> v2.39.0. The sqlite store is
  migrated in place, so snapshot the PVC before upgrading.
- Charts publish to this fork's GHCR namespace.
