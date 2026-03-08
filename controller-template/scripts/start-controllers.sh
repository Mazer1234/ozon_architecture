#!/usr/bin/env sh

set -eu

usage() {
  cat <<'EOF'
Usage:
  sh start-controllers.sh --count N [options]

Options:
  --count N                     Required. Number of controllers to start.
  --start-index N               Default: 1
  --project-prefix VALUE        Default: ctrl
  --controller-id-prefix VALUE  Default: ctrl
  --city VALUE                  Default: random (pick from --cities)
  --telemetry-topic VALUE       Default: telemetry.v1
  --command-topic VALUE         Default: command.v1
  --kafka-bootstrap VALUE       Default: host.docker.internal:29092
  --kafka-producer-acks VALUE   Default: all
  --kafka-idempotence VALUE     Default: true
  --kafka-retries N             Default: 5
  --kafka-retry-backoff-ms N    Default: 100
  --kafka-request-timeout-ms N  Default: 30000
  --send-interval-sec N         Default: 5
  --base-watts N                Default: 120
  --noise-watts N               Default: 30
  --netem-delay-ms N            Default: 0
  --netem-jitter-ms N           Default: 0
  --netem-loss-pct VALUE        Default: 0
  --build                       Pass --build to docker compose up
  --cities "a b c"              Default: moscow spb kazan ekb novgorod perm rostov sochi
  -h, --help
EOF
}

is_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Список городов для рандома
CITIES="moscow spb kazan ekb novgorod perm rostov sochi"

pick_city_for_id() {
  id="$1"

  # Число из cksum (встроено почти везде)
  num="$(printf '%s' "$id" | cksum | awk '{print $1}')"

  # Кол-во городов
  n="$(printf '%s\n' "$CITIES" | awk '{print NF}')"

  # Индекс 1..n
  idx=$(( (num % n) + 1 ))

  # Вернуть idx-й город
  printf '%s\n' "$CITIES" | awk -v i="$idx" '{print $i}'
}

COUNT=""
START_INDEX=1
PROJECT_PREFIX="ctrl"
CONTROLLER_ID_PREFIX="ctrl"
CITY="random"
TELEMETRY_TOPIC="telemetry.v1"
COMMAND_TOPIC="command.v1"
KAFKA_BOOTSTRAP_SERVERS="host.docker.internal:29092"
KAFKA_PRODUCER_ACKS="all"
KAFKA_PRODUCER_ENABLE_IDEMPOTENCE="true"
KAFKA_PRODUCER_RETRIES=5
KAFKA_PRODUCER_RETRY_BACKOFF_MS=100
KAFKA_PRODUCER_REQUEST_TIMEOUT_MS=30000
SEND_INTERVAL_SEC=5
BASE_WATTS=120
NOISE_WATTS=30
NETEM_DELAY_MS=0
NETEM_JITTER_MS=0
NETEM_LOSS_PCT=0
BUILD=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --count)
      COUNT="${2:-}"
      shift 2
      ;;
    --start-index)
      START_INDEX="${2:-}"
      shift 2
      ;;
    --project-prefix)
      PROJECT_PREFIX="${2:-}"
      shift 2
      ;;
    --controller-id-prefix)
      CONTROLLER_ID_PREFIX="${2:-}"
      shift 2
      ;;
    --city)
      CITY="${2:-}"
      shift 2
      ;;
    --telemetry-topic)
      TELEMETRY_TOPIC="${2:-}"
      shift 2
      ;;
    --command-topic)
      COMMAND_TOPIC="${2:-}"
      shift 2
      ;;
    --kafka-bootstrap)
      KAFKA_BOOTSTRAP_SERVERS="${2:-}"
      shift 2
      ;;
    --kafka-producer-acks)
      KAFKA_PRODUCER_ACKS="${2:-}"
      shift 2
      ;;
    --kafka-idempotence)
      KAFKA_PRODUCER_ENABLE_IDEMPOTENCE="${2:-}"
      shift 2
      ;;
    --kafka-retries)
      KAFKA_PRODUCER_RETRIES="${2:-}"
      shift 2
      ;;
    --kafka-retry-backoff-ms)
      KAFKA_PRODUCER_RETRY_BACKOFF_MS="${2:-}"
      shift 2
      ;;
    --kafka-request-timeout-ms)
      KAFKA_PRODUCER_REQUEST_TIMEOUT_MS="${2:-}"
      shift 2
      ;;
    --send-interval-sec)
      SEND_INTERVAL_SEC="${2:-}"
      shift 2
      ;;
    --base-watts)
      BASE_WATTS="${2:-}"
      shift 2
      ;;
    --noise-watts)
      NOISE_WATTS="${2:-}"
      shift 2
      ;;
    --netem-delay-ms)
      NETEM_DELAY_MS="${2:-}"
      shift 2
      ;;
    --netem-jitter-ms)
      NETEM_JITTER_MS="${2:-}"
      shift 2
      ;;
    --netem-loss-pct)
      NETEM_LOSS_PCT="${2:-}"
      shift 2
      ;;
    --build)
      BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --cities)
      CITIES="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$COUNT" ] || ! is_int "$COUNT" || [ "$COUNT" -lt 1 ]; then
  echo "Error: --count must be an integer >= 1" >&2
  exit 1
fi

if ! is_int "$START_INDEX" || [ "$START_INDEX" -lt 1 ]; then
  echo "Error: --start-index must be an integer >= 1" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is not installed or not in PATH" >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
COMPOSE_FILE="$TEMPLATE_DIR/docker-compose.yaml"
COMPOSE_DEV_FILE="$TEMPLATE_DIR/docker-compose.dev.yaml"
ENV_DIR="$TEMPLATE_DIR/.generated-env"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Error: compose file was not found: $COMPOSE_FILE" >&2
  exit 1
fi

mkdir -p "$ENV_DIR"

i=0
while [ "$i" -lt "$COUNT" ]; do
  index=$((START_INDEX + i))
  project_name=$(printf '%s_%04d' "$PROJECT_PREFIX" "$index" | tr '[:upper:]' '[:lower:]')
  controller_id=$(printf '%s-%04d' "$CONTROLLER_ID_PREFIX" "$index")
  env_file="$ENV_DIR/$project_name.env"
  if [ "$CITY" = "__RANDOM__" ] || [ "$CITY" = "random" ] || [ "$CITY" = "" ]; then
    city_for_controller="$(pick_city_for_id "$controller_id")"
  else
    city_for_controller="$CITY"
  fi

  cat >"$env_file" <<EOF
CONTROLLER_ID=$controller_id
CITY=$city_for_controller
TELEMETRY_TOPIC=$TELEMETRY_TOPIC
COMMAND_TOPIC=$COMMAND_TOPIC
KAFKA_BOOTSTRAP_SERVERS=$KAFKA_BOOTSTRAP_SERVERS
KAFKA_PRODUCER_ACKS=$KAFKA_PRODUCER_ACKS
KAFKA_PRODUCER_ENABLE_IDEMPOTENCE=$KAFKA_PRODUCER_ENABLE_IDEMPOTENCE
KAFKA_PRODUCER_RETRIES=$KAFKA_PRODUCER_RETRIES
KAFKA_PRODUCER_RETRY_BACKOFF_MS=$KAFKA_PRODUCER_RETRY_BACKOFF_MS
KAFKA_PRODUCER_REQUEST_TIMEOUT_MS=$KAFKA_PRODUCER_REQUEST_TIMEOUT_MS
SEND_INTERVAL_SEC=$SEND_INTERVAL_SEC
BASE_WATTS=$BASE_WATTS
NOISE_WATTS=$NOISE_WATTS
NETEM_DELAY_MS=$NETEM_DELAY_MS
NETEM_JITTER_MS=$NETEM_JITTER_MS
NETEM_LOSS_PCT=$NETEM_LOSS_PCT
EOF

  if [ "$BUILD" -eq 1 ]; then
    docker compose -f "$COMPOSE_FILE" -f "$COMPOSE_DEV_FILE" --project-name "$project_name" --env-file "$env_file" up -d --build
  else
    docker compose -f "$COMPOSE_FILE" -f "$COMPOSE_DEV_FILE" --project-name "$project_name" --env-file "$env_file" up -d
  fi

  echo "[started] project=$project_name controller_id=$controller_id env_file=$env_file"
  i=$((i + 1))
done
