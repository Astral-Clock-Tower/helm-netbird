#!/usr/bin/env bash
#
# Sets the chart version, and optionally the app version, in every file that
# repeats it.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
usage: scripts/set-version.sh <major|minor|patch> [--rc]
       scripts/set-version.sh rc
       scripts/set-version.sh <x.y.z>
       ... [--app <version>] [--dashboard <tag>]

  major|minor|patch  bump that part of the chart version
  --rc               make it a release candidate: 2.1.0 -> 2.1.0-rc.1
  rc                 increment an existing -rc.N
  <x.y.z>            set the chart version explicitly

  --app              NetBird version -> Chart.yaml appVersion, values.yaml
                     server.image.tag, and the README row for it
  --dashboard        dashboard tag -> values.yaml and its README row

A prerelease is a prerelease OF its version, so `patch` on 3.0.0-rc.4 finalises
it to 3.0.0 rather than skipping to 3.0.1.
USAGE
  exit "${1:-1}"
}

semver='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'
target='' app='' dashboard='' rc=false

while [ $# -gt 0 ]; do
  case "$1" in
    --app)       app="${2:?--app needs a version}"; shift 2 ;;
    --dashboard) dashboard="${2:?--dashboard needs a tag}"; shift 2 ;;
    --rc)        rc=true; shift ;;
    -h|--help)   usage 0 ;;
    *)           target="$1"; shift ;;
  esac
done

[ -n "$target" ] || usage

current="$(grep -E '^version:' Chart.yaml | awk '{print $2}')"
base="${current%%-*}"                                   # 2.1.0-rc.4 -> 2.1.0
pre="${current#"$base"}"; pre="${pre#-}"                # 2.1.0-rc.4 -> rc.4
IFS=. read -r X Y Z <<EOF
$base
EOF

case "$target" in
  major) version="$(( X + 1 )).0.0" ;;
  minor) version="${X}.$(( Y + 1 )).0" ;;
  # A prerelease is a prerelease OF base, so patching one finalises it.
  patch) [ -n "$pre" ] && version="$base" || version="${X}.${Y}.$(( Z + 1 ))" ;;
  rc)
    case "$pre" in
      rc.*) version="${base}-rc.$(( ${pre#rc.} + 1 ))" ;;
      *) echo "current version $current is not an -rc.N; use e.g. 'patch --rc'" >&2; exit 1 ;;
    esac ;;
  *) version="$target" ;;
esac

if [ "$rc" = true ]; then
  case "$target" in
    rc) echo "--rc is redundant with the rc verb" >&2; exit 1 ;;
    *)  version="${version}-rc.1" ;;
  esac
fi

for v in "$version" ${app:+"$app"}; do
  printf '%s' "$v" | grep -Eq "$semver" || { echo "not semver: $v" >&2; exit 1; }
done

edit() {
  local file="$1" tmp="$1.tmp"
  sed -E "$2" "$file" > "$tmp"
  if cmp -s "$file" "$tmp"; then rm -f "$tmp"; echo "  unchanged: $3"; return; fi
  cat "$tmp" > "$file"; rm -f "$tmp"
  echo "  updated:   $3"
}

echo "chart version: $current -> $version"
edit Chart.yaml "s|^version: .*|version: $version|" "Chart.yaml version"

if [ -n "$app" ]; then
  echo "app version: -> $app"
  edit Chart.yaml  "s|^appVersion: .*|appVersion: \"$app\"|"  "Chart.yaml appVersion"
  edit values.yaml "s|^(    tag: )[0-9].*|\1$app|"            "values.yaml server.image.tag"
  edit README.md   "/^[|] server[.]image[.]tag /s@\`'[^']*'\`@\`'$app'\`@" \
                   "README.md server.image.tag row"
fi

if [ -n "$dashboard" ]; then
  echo "dashboard tag: -> $dashboard"
  edit values.yaml "s|^(    tag: )v[0-9].*|\1$dashboard|"     "values.yaml dashboard.image.tag"
  edit README.md   "/^[|] dashboard[.]image[.]tag /s@\`'[^']*'\`@\`'$dashboard'\`@" \
                   "README.md dashboard.image.tag row"
fi

helm template check . \
  --set global.domain.global=example.com \
  --set global.server.encryption_key=dummy \
  --set global.server.auth_secret=dummy >/dev/null
echo "renders cleanly"
