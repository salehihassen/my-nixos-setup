#!/usr/bin/env bash

# List the names of variables exported by ~/.bash_secrets without printing values.
# The default mode parses the file as text and never executes it.

set -u

SECRETS_FILE="${BASH_SECRETS_FILE:-$HOME/.bash_secrets}"
MODE=parse
SHOW_STATUS=0

usage() {
  cat <<'EOF'
Usage: list-secret-names.sh [options]

Print the names of environment variables exported by ~/.bash_secrets,
one per line, sorted. Values are never printed.

Options:
  --status       Append "set" or "unset" for the calling environment
  --evaluate     Source the file in a clean subshell and list what it exports
                 (catches loops/set -a/conditionals, but runs the file)
  --file PATH    Secrets file (default: $BASH_SECRETS_FILE or ~/.bash_secrets)
  -h, --help     Show this help
EOF
}

while (($#)); do
  case "$1" in
    --status)
      SHOW_STATUS=1
      shift
      ;;
    --evaluate)
      MODE=evaluate
      shift
      ;;
    --file)
      SECRETS_FILE="${2:?missing path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -r "$SECRETS_FILE" ]]; then
  echo "Cannot read secrets file: $SECRETS_FILE" >&2
  exit 1
fi

# Static parse: keep export/declare -x/typeset -x lines, drop quoted values,
# command substitutions and trailing comments, then keep identifier names only.
parse_names() {
  local words word name exported
  grep -E '^[[:space:]]*(export|declare|typeset)[[:space:]]' "$SECRETS_FILE" |
    sed -E \
      -e "s/'[^']*'//g" \
      -e 's/"([^"\\]|\\.)*"//g' \
      -e 's/\$\([^)]*\)//g' \
      -e 's/`[^`]*`//g' \
      -e 's/(^|[[:space:]])#.*$//' |
    while read -r -a words; do
      ((${#words[@]})) || continue
      exported=0
      [[ ${words[0]} == export ]] && exported=1
      for word in "${words[@]:1}"; do
        if [[ $word == -* ]]; then
          [[ $word == *f* ]] && exported=0
          [[ ${words[0]} == export && $word == *n* ]] && exported=0
          [[ ${words[0]} != export && $word == *x* ]] && exported=1
          continue
        fi
        ((exported)) || break
        name=${word%%=*}
        [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && printf '%s\n' "$name"
      done
    done
}

# Exact but executes the file: diff exported names against an empty shell.
evaluate_names() {
  local baseline
  baseline=$(env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc -c 'compgen -e')
  env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc -c \
    '. "$1" >/dev/null 2>&1 </dev/null; compgen -e' _ "$SECRETS_FILE" |
    grep -vxF -f <(printf '%s\n' "$baseline")
}

if [[ $MODE == evaluate ]]; then
  names=$(evaluate_names)
else
  names=$(parse_names)
fi

[[ -n $names ]] || exit 0

while IFS= read -r name; do
  if ((SHOW_STATUS)); then
    if [[ -n ${!name+x} ]]; then
      printf '%s\tset\n' "$name"
    else
      printf '%s\tunset\n' "$name"
    fi
  else
    printf '%s\n' "$name"
  fi
done <<<"$names" | LC_ALL=C sort -u
