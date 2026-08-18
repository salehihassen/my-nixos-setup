#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_dir="$(realpath "$script_dir/..")"
readonly source_dir="$repo_dir/dotfiles"
readonly target_dir="${HOME:-}"
readonly -a packages=(
  bash
  git
  neovim
  niri
  noctalia
  ssh
  tmux
  wallpapers
)

usage() {
  cat <<'EOF'
Usage: stow-dotfiles.sh [--dry-run | --delete]

  (no option)  Restow all managed packages.
  --dry-run    Show verbosely what restowing would change.
  --delete     Remove links owned by all managed packages.
EOF
}

mode="restow"
case "${1:-}" in
  "") ;;
  --dry-run) mode="dry-run" ;;
  --delete) mode="delete" ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if (( $# > 1 )); then
  usage >&2
  exit 2
fi

if [[ ! -d "$source_dir" || -L "$source_dir" ]]; then
  printf 'Refusing to continue: source must be a real directory: %s\n' "$source_dir" >&2
  exit 1
fi

if [[ -z "$target_dir" || "$target_dir" != /* || "$target_dir" == "/" ]]; then
  printf 'Refusing unsafe HOME target: %s\n' "${target_dir:-<unset>}" >&2
  exit 1
fi

if [[ ! -d "$target_dir" || -L "$target_dir" || ! -w "$target_dir" ]]; then
  printf 'Refusing to continue: target must be a real, writable directory: %s\n' "$target_dir" >&2
  exit 1
fi

canonical_source="$(realpath "$source_dir")"
canonical_target="$(realpath "$target_dir")"
if [[ "$canonical_source" != "$source_dir" || "$canonical_target" != "$target_dir" ]]; then
  printf 'Refusing non-canonical source or target path: %s -> %s, %s -> %s\n' \
    "$source_dir" "$canonical_source" "$target_dir" "$canonical_target" >&2
  exit 1
fi

for package in "${packages[@]}"; do
  if [[ ! -d "$source_dir/$package" || -L "$source_dir/$package" ]]; then
    printf 'Refusing to continue: missing or unsafe Stow package: %s\n' "$package" >&2
    exit 1
  fi
done

if ! command -v stow >/dev/null 2>&1; then
  printf 'GNU Stow is not available in PATH.\n' >&2
  exit 127
fi

# Home Manager may have deliberately left an existing regular file in place
# when it was byte-for-byte identical to a formerly managed source. Stow still
# treats that file as a conflict. During a real restow, remove only such exact
# duplicates so Stow can replace them with links. Never alter differing files,
# ignored Bash files, dry-run targets, or rollback targets.
if [[ "$mode" == "restow" ]]; then
  shopt -s dotglob globstar nullglob

  for package in "${packages[@]}"; do
    package_dir="$source_dir/$package"

    for source_file in "$package_dir"/**; do
      [[ -f "$source_file" && ! -L "$source_file" ]] || continue

      relative_path="${source_file#"$package_dir"/}"
      case "$relative_path" in
        .stow-local-ignore|bash_secrets|network-diagnostics.sh)
          continue
          ;;
      esac

      target_file="$target_dir/$relative_path"
      if [[ -f "$target_file" && ! -L "$target_file" ]] && cmp --silent -- "$source_file" "$target_file"; then
        printf 'Removing identical legacy file before Stow links it: %s\n' "$target_file"
        rm -- "$target_file"
      fi
    done
  done
fi

stow_args=(
  --dir="$source_dir"
  --target="$target_dir"
  --no-folding
)

case "$mode" in
  restow)
    stow_args+=(--restow)
    ;;
  dry-run)
    stow_args+=(--restow --simulate --verbose=2)
    ;;
  delete)
    stow_args+=(--delete)
    ;;
esac

stow "${stow_args[@]}" "${packages[@]}"
