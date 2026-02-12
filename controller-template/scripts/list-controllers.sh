#!/usr/bin/env sh

set -eu

usage() {
  cat <<'EOF'
Usage:
  sh list-controllers.sh [--project-prefix VALUE]
EOF
}

PROJECT_PREFIX=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-prefix)
      PROJECT_PREFIX="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is not installed or not in PATH" >&2
  exit 1
fi

ids=$(docker ps --filter "label=com.docker.compose.service=controller" --format '{{.ID}}')

if [ -z "$ids" ]; then
  echo "No running controller containers were found."
  exit 0
fi

printf '%-20s %-36s %-18s %-12s %-10s\n' "Project" "Container" "ControllerId" "City" "Status"
printf '%-20s %-36s %-18s %-12s %-10s\n' "-------" "---------" "------------" "----" "------"

prefix_lc=$(printf '%s' "$PROJECT_PREFIX" | tr '[:upper:]' '[:lower:]')

for id in $ids; do
  project=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$id")
  project_lc=$(printf '%s' "$project" | tr '[:upper:]' '[:lower:]')
  if [ -n "$prefix_lc" ]; then
    case "$project_lc" in
      "$prefix_lc"*) ;;
      *) continue ;;
    esac
  fi

  container=$(docker inspect --format '{{.Name}}' "$id" | sed 's#^/##')
  status=$(docker inspect --format '{{.State.Status}}' "$id")
  env_data=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$id")
  controller_id=$(printf '%s\n' "$env_data" | sed -n 's/^CONTROLLER_ID=//p' | head -n 1)
  city=$(printf '%s\n' "$env_data" | sed -n 's/^CITY=//p' | head -n 1)

  printf '%-20s %-36s %-18s %-12s %-10s\n' "$project" "$container" "$controller_id" "$city" "$status"
done

