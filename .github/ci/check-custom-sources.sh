#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

nix eval --impure --json --file "$repo_root/.github/ci/custom-sources.nix" \
  > "$work_dir/sources.json"

# Download to a new local file on every run. Supplying an expected hash directly
# to a Nix fetch command could let it reuse a store path without contacting the
# original URL. Hash the actual download first, then compare with the pin.
jq -r '.downloads[] | [.label, .url, .hash, .unpack, .name] | @tsv' \
  "$work_dir/sources.json" > "$work_dir/downloads.tsv"
while IFS=$'\t' read -r label url expected unpack store_name; do
  echo "::group::Check source: $label"
  archive="$work_dir/$label.download"
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 30 --max-time 300 \
    --output "$archive" "$url"
  prefetch_args=(--json --name "$store_name")
  if [[ "$unpack" == true ]]; then
    prefetch_args+=(--unpack)
  fi
  actual="$(nix store prefetch-file "${prefetch_args[@]}" "file://$archive" | jq -er '.hash')"
  expected="$(nix hash convert --hash-algo sha256 --to sri "$expected")"
  if [[ "$actual" != "$expected" ]]; then
    echo "::error::Source hash mismatch for $label: expected $expected, got $actual"
    exit 1
  fi
  rm -- "$archive"
  echo "::endgroup::"
done < "$work_dir/downloads.tsv"

# These are fetchers, not application builds. --rebuild is required when the
# output already exists; allowSubstitutes=false handles a fresh runner. Build
# dependencies may still use public caches, without bypassing these fetchers.
jq -r '.bundles[] | [.label, .drvPath, .outputPath] | @tsv' \
  "$work_dir/sources.json" > "$work_dir/bundles.tsv"
while IFS=$'\t' read -r label drv_path out_path; do
  echo "::group::Check dependency bundle: $label"
  build_args=(--no-link -L)
  if nix path-info --offline "$out_path" > /dev/null 2>&1; then
    build_args+=(--rebuild)
  fi
  nix build "${build_args[@]}" "$drv_path^*"
  echo "::endgroup::"
done < "$work_dir/bundles.tsv"
