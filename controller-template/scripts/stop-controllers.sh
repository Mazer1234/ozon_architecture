#!/usr/bin/env sh

set -eu

usage() {
  cat <<'EOF'
Usage:
  sh stop-controllers.sh [options]

Options:
  --project-prefix VALUE   Stop only projects with this prefix
  --remove-volumes         Pass -v to docker compose down
  -h, --help
EOF
}

PROJECT_PREFIX=""
REMOVE_VOLUMES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-prefix)
      PROJECT_PREFIX="${2:-}"
      shift 2
      ;;
    --remove-volumes)
      REMOVE_VOLUMES=1
      shift
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

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
COMPOSE_FILE="$TEMPLATE_DIR/docker-compose.yaml"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Error: compose file was not found: $COMPOSE_FILE" >&2
  exit 1
fi

ids=$(docker ps -a --filter "label=com.docker.compose.service=controller" --format '{{.ID}}')
if [ -z "$ids" ]; then
  echo "No controller containers were found."
  exit 0
fi

prefix_lc=$(printf '%s' "$PROJECT_PREFIX" | tr '[:upper:]' '[:lower:]')
projects=""

for id in $ids; do
  project=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$id")
  [ -n "$project" ] || continue

  project_lc=$(printf '%s' "$project" | tr '[:upper:]' '[:lower:]')
  if [ -n "$prefix_lc" ]; then
    case "$project_lc" in
      "$prefix_lc"*) ;;
      *) continue ;;
    esac
  fi

  if ! printf '%s\n' "$projects" | grep -qx "$project"; then
    projects=$(printf '%s\n%s' "$projects" "$project")
  fi
done

projects=$(printf '%s\n' "$projects" | sed '/^$/d')
if [ -z "$projects" ]; then
  echo "No matching controller projects were found."
  exit 0
fi

printf '%s\n' "$projects" | while IFS= read -r project; do
  [ -n "$project" ] || continue
  if [ "$REMOVE_VOLUMES" -eq 1 ]; then
    if ! docker compose -f "$COMPOSE_FILE" --project-name "$project" down --remove-orphans -v; then
      echo "Warning: failed to stop project '$project'" >&2
      continue
    fi
  else
    if ! docker compose -f "$COMPOSE_FILE" --project-name "$project" down --remove-orphans; then
      echo "Warning: failed to stop project '$project'" >&2
      continue
    fi
  fi

  echo "[stopped] project=$project"
done

