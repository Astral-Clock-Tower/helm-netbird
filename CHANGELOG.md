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

- **The server Deployment carries a `checksum/config` annotation.** Every
  install gains one pod-template field, so the first upgrade to 2.0.0 rolls the
  server pod once. Without it a config change never reached the container:
  `config.yaml` is mounted with `subPath`, which never receives Secret updates,
  and nothing else in the pod template changed - so `helm upgrade` reported
  success while the running server kept the config it started with. Rotating
  `encryption_key`, `auth_secret` or any OIDC setting was silently a no-op
  until someone restarted the pod by hand. Not applied when
  `existingConfigSecret` is set, since the chart cannot read that Secret to
  hash it; changing that one still needs `kubectl rollout restart`.

- **The server Deployment uses `strategy: Recreate`.** Upgrades now stop the
  old pod before starting the new one, so they take a short outage instead of
  risking two servers on one sqlite file.
- **Removed values that no template read:** `global.domain.vpn`,
  `global.ingress.*`, `global.persistence.overrideVolume` and
  `global.persistence.overrideVolumeMount`. Setting them never did anything;
  they are gone from `values.yaml` so nobody expects them to.

- **`global.auth.authority` and `global.auth.issuerUrl` must name
  `global.domain.global`, or the render fails.** Both configure NetBird's own
  embedded Dex, so a foreign host there was never going to work: the server
  ignores it and keeps issuing through Dex, while the dashboard goes off to the
  other provider, logs the user in and then has its token rejected. That
  combination used to render happily and fail at login with
  `unable to find appropriate key`. Checked from the dashboard Deployment as
  well as the config Secret, so it fires under `existingConfigSecret` too.

  If you set these to an external provider, unset them and attach the provider
  to Dex as a connector - see [Authentication](README.md#authentication).
- **`global.auth.issuerUrl` no longer falls back to `global.auth.authority`.**
  It defaults straight to `https://<domain.global>/oauth2`. With the check
  above the two can only ever share a host, so the fallback made no difference
  to what rendered; it only made it look like pointing `authority` elsewhere
  would move the issuer with it.
- **`global.server.reverseProxy` now fails the render when
  `existingConfigSecret` is also set**, joining `encryption_key`, `auth_secret`
  and `stun.external`. It only reaches NetBird through the config file the
  chart writes, so with that file replaced it was silently ignored. Only a
  customised block trips this - the shipped default does not, so existing
  `existingConfigSecret` installs keep rendering.

### Added

- `global.server.existingConfigSecret` - point at a Secret holding the whole
  `config.yaml` and the chart renders none of its own. Fails the render if a
  value that only reaches NetBird through that file is also set.
- `global.auth.*` - issuer, authority, client id, audience, scopes and redirect
  URIs for NetBird's **embedded** Dex identity provider, and the dashboard's
  view of it. Credentials come from values or from `global.auth.existingSecret`,
  whose key names are configurable; set `global.auth.publicClient` for a PKCE
  client with no secret.

  These do **not** point NetBird at an external OIDC provider, and an earlier
  draft of this entry wrongly said they did. The combined image this chart runs
  hardcodes its embedded Dex on and overwrites the server's issuer, audience,
  JWKS location and discovery endpoint with Dex's own values; no `config.yaml`
  field changes that. External providers attach to Dex as upstream connectors
  instead - see [Authentication](README.md#authentication).
- `global.auth.localAuthDisabled`, `cliRedirectURIs`, `postLogoutRedirectURIs`,
  `grantTypes`, `sessionCookieEncryptionKey`, `owner.*` and `mfa.*` - the
  embedded IdP settings the combined image actually accepts, none of which the
  chart previously emitted. `owner` seeds an initial admin as a Dex static
  password, which Dex re-applies on every boot, so the first-run "create the
  first admin account" screen can be skipped declaratively.

  `owner.passwordHash` is named for what it holds: NetBird calls the field
  `password` but stores the value verbatim as the bcrypt hash, so a plaintext
  password there yields an account nobody can log into. The chart rejects
  anything that is not a bcrypt hash.
- `global.server.authStore.*` - engine, DSN and file for the embedded IdP's own
  store (Dex users, connectors, sessions), which defaults to sqlite at
  `<dataDir>/idp.db` alongside the main store.
- `global.route.annotations` applies to every rendered route, with
  `dashboardAnnotations` / `serverAnnotations` / `stunAnnotations` merged over
  it per route.
- `global.server.stun.enabled`, `.port` and `.external` - serve STUN on a
  chosen port, advertise external STUN servers, or turn local STUN off
  entirely.
- `global.server.reverseProxy.*` - passed through to NetBird's `reverseProxy`
  config block key for key, so `trustedHTTPProxies`, `trustedHTTPProxiesCount`,
  `trustedPeers`, `accessLogRetentionDays` and `accessLogCleanupIntervalHours`
  are all reachable, and a field left empty is omitted so NetBird's own default
  applies. `trustedHTTPProxies` keeps its previous hardcoded `0.0.0.0/0`, which
  trusts `X-Forwarded-For` from anywhere - narrow it to your gateway's pod
  CIDR. Setting `trustedPeers` also clears NetBird's boot warning that the
  default allows connection IP spoofing.

- `global.server.metrics.port` / `.exposed` - the metrics port was hardcoded to
  9090 in the config and published nowhere, so nothing could scrape it. Now
  configurable and, by default, published as a container port and on the
  `-server-http` Service. That is a ClusterIP, and no route points at the
  metrics port, so it stays reachable only from inside the cluster.

- `global.server.legacyGrpc.port` / `.exposed` - NetBird starts a gRPC listener
  on 33073 for peers older than v0.29 whether or not you want it; the chart can
  now publish that port. Off by default, since anything from v0.29 on uses the
  consolidated port.

- `server.deploymentAnnotations` and `dashboard.deploymentAnnotations` -
  custom annotations on the Deployment object. `annotations` only ever reached
  the pod template, so anything that reads the workload object itself could not
  be set through this chart. Values are coerced to strings, so a bare `true` is
  not rejected as a boolean at apply time.

- `server.reloadOnConfigChange` (default `true`) - whether to emit the
  `checksum/config` annotation described above. Turn it off if something else
  is responsible for restarting the pod when the config changes.

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

- NetBird 0.66.0 -> 0.78.1, dashboard v2.33.0 -> v2.92.0. The sqlite store is
  migrated in place, so snapshot the PVC before upgrading.

  The dashboard now builds its Content-Security-Policy at container start from
  `AUTH_AUTHORITY`, `NETBIRD_MGMT_API_ENDPOINT` and `LETSENCRYPT_DOMAIN`, then
  reloads nginx - and exits non-zero if that reload fails, where previously it
  could not fail. It also hard-exits when `AUTH_AUTHORITY`, `AUTH_CLIENT_ID`,
  `AUTH_AUDIENCE`, `AUTH_SUPPORTED_SCOPES`, `USE_AUTH0` or
  `NETBIRD_MGMT_API_ENDPOINT` is empty; the chart sets all six.
- `LETSENCRYPT_DOMAIN` on the dashboard comes from the new
  `dashboard.letsencrypt.domain` (with `.email` alongside it) and defaults to
  empty rather than the hardcoded `"none"`. Certbot stays off either way -
  `init_cert.sh` reads an empty value as `none` - but the new CSP builder
  treats any non-empty value as a real domain, so `"none"` was putting a junk
  `https://none` into `connect-src`.
- Charts publish to this fork's GHCR namespace.
