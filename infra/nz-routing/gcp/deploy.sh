#!/usr/bin/env bash
set -euo pipefail

# Invoke in WSL, after node infra/nz-routing/verify-artifact.mjs on the host.
# Default prints the plan. --apply creates only this private staging service.
project=kiwi-lens-2026-sam
region=australia-southeast1
service=waybi-nz-routing-staging
environment=staging
if [[ "${1:-}" == --production ]]; then
  service=waybi-nz-routing
  environment=production
  shift
  [[ -n "${WAYBI_ROUTING_IMAGE:-}" ]] || { printf '%s\n' 'Production requires a previously tested immutable image' >&2; exit 1; }
fi
repository=waybi-routing-staging
runtime=waybi-routing-runtime
gcloud_bin="${WAYBI_GCLOUD_BIN:-gcloud}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image_prefix="$region-docker.pkg.dev/$project/$repository/valhalla"
image="${WAYBI_ROUTING_IMAGE:-$image_prefix:nz-$(date -u +%Y%m%d%H%M%S)}"
if [[ -n "${WAYBI_ROUTING_IMAGE:-}" && ! "$image" =~ ^$image_prefix@sha256:[a-f0-9]{64}$ ]]; then
  printf '%s\n' 'WAYBI_ROUTING_IMAGE must be an immutable digest in the owned staging repository' >&2
  exit 1
fi
printf 'Project: %s\nRegion: %s\nService: %s\nImage: %s\n' "$project" "$region" "$service" "$image"
printf '%s\n' 'Private IAM; 1 vCPU / 1 GiB; concurrency 1; min 0; max 1; CPU throttling; no startup boost.'
printf '%s\n' 'Cloud Build, registry storage, and outbound traffic have separate pricing. Free usage is shared.'
[[ "${1:-}" == --apply ]] || exit 0

# Verify locally before spending build time. Only Python's standard library is
# needed in WSL. Never upload a partial or accidentally rebuilt graph.
python3 - "$root/artifact" <<'PY'
import hashlib, json, pathlib, sys
p = pathlib.Path(sys.argv[1])
m = json.loads((p / 'manifest.json').read_text())
assert m['region'] == 'NZ' and m['engine'] == 'Valhalla 3.9.1'
for name in ('valhalla_tiles.tar', 'admins.sqlite', 'timezones.sqlite'):
    with (p / name).open('rb') as f:
        assert hashlib.file_digest(f, 'sha256').hexdigest() == m['hashes'][name], name
c = json.loads((p / 'valhalla.json').read_text())
assert c['httpd']['service']['listen'] == 'tcp://*:8002'
assert sorted(c['loki']['actions']) == ['route', 'status']
for field, name in [('tile_extract', 'valhalla_tiles.tar'), ('admin', 'admins.sqlite'), ('timezone', 'timezones.sqlite')]:
    assert c['mjolnir'][field] == '/data/' + name
print('Verified immutable graph:', m['generatedAt'])
PY
if ! "$gcloud_bin" artifacts repositories describe "$repository" --location="$region" --project="$project" >/dev/null 2>&1; then
  "$gcloud_bin" artifacts repositories create "$repository" --repository-format=docker \
    --location="$region" --project="$project" --description='Waybi private NZ routing staging images' --quiet
fi
email="$runtime@$project.iam.gserviceaccount.com"
if ! "$gcloud_bin" iam service-accounts describe "$email" --project="$project" >/dev/null 2>&1; then
  "$gcloud_bin" iam service-accounts create "$runtime" --project="$project" \
    --display-name='Waybi routing runtime (no project roles)' --quiet
fi
if [[ -z "${WAYBI_ROUTING_IMAGE:-}" ]]; then
  build_id="$("$gcloud_bin" builds submit "$root" --project="$project" --region="$region" \
    --config="$root/gcp/cloudbuild.yaml" --substitutions="_IMAGE=$image" --format='value(id)' --suppress-logs --quiet)"
  digest="$("$gcloud_bin" builds describe "$build_id" --project="$project" --region="$region" \
    --format='value(results.images[0].digest)')"
  [[ "$digest" == sha256:* ]] || { printf '%s\n' 'Build did not produce an immutable digest' >&2; exit 1; }
  image="$image_prefix@$digest"
fi
"$gcloud_bin" run deploy "$service" --project="$project" --region="$region" \
  --image="$image" --port=8002 --cpu=1 --memory=1Gi --concurrency=1 \
  --min=0 --max=1 --min-instances=0 --max-instances=1 --timeout=15s \
  --cpu-throttling --no-cpu-boost --execution-environment=gen2 --no-deploy-health-check \
  --service-account="$email" --no-allow-unauthenticated --invoker-iam-check \
  --labels="app=waybi,component=nz-routing,environment=$environment" \
  --startup-probe='httpGet.path=/status,httpGet.port=8002,initialDelaySeconds=0,periodSeconds=1,timeoutSeconds=1,failureThreshold=60' \
  --quiet
"$gcloud_bin" run services describe "$service" --project="$project" --region="$region" \
  --format='yaml(status.url,status.latestReadyRevisionName,spec.template.spec.containers[0].image)'
printf '%s\n' "$environment Cloud Run origin deployed. Worker routing is configured separately."
