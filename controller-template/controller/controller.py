import asyncio
import json
import os
import random
from datetime import datetime, timezone

from aiokafka import AIOKafkaProducer, AIOKafkaConsumer

CONTROLLER_ID = os.getenv("CONTROLLER_ID", "ctrl-00001")
CITY = os.getenv("CITY", "moscow")

TELEMETRY_TOPIC = os.getenv("TELEMETRY_TOPIC", "telemetry.v1")
COMMAND_TOPIC = os.getenv("COMMAND_TOPIC", "command.v1")
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "host.docker.internal:29092")
KAFKA_PRODUCER_ACKS_RAW = os.getenv("KAFKA_PRODUCER_ACKS", "all")
KAFKA_PRODUCER_ENABLE_IDEMPOTENCE = os.getenv("KAFKA_PRODUCER_ENABLE_IDEMPOTENCE", "true").strip().lower() in ("1", "true", "yes", "on")
KAFKA_PRODUCER_RETRIES = int(os.getenv("KAFKA_PRODUCER_RETRIES", "5"))
KAFKA_PRODUCER_RETRY_BACKOFF_MS = int(os.getenv("KAFKA_PRODUCER_RETRY_BACKOFF_MS", "100"))
KAFKA_PRODUCER_REQUEST_TIMEOUT_MS = int(os.getenv("KAFKA_PRODUCER_REQUEST_TIMEOUT_MS", "30000"))

SEND_INTERVAL = float(os.getenv("SEND_INTERVAL_SEC", "5"))

BASE_WATTS = float(os.getenv("BASE_WATTS", "120.0"))
NOISE_WATTS = float(os.getenv("NOISE_WATTS", "30.0"))

def parse_kafka_acks(raw: str):
    value = raw.strip().lower()
    if value in ("all", "-1"):
        return "all"
    if value in ("0", "1"):
        return int(value)
    raise ValueError(f"Unsupported KAFKA_PRODUCER_ACKS value: {raw}")

KAFKA_PRODUCER_ACKS = parse_kafka_acks(KAFKA_PRODUCER_ACKS_RAW)

if KAFKA_PRODUCER_ACKS != "all":
    raise RuntimeError("Refusing to start: KAFKA_PRODUCER_ACKS must be all/-1 for durability guarantees")
if KAFKA_PRODUCER_RETRIES < 1:
    raise ValueError("KAFKA_PRODUCER_RETRIES must be >= 1")
if KAFKA_PRODUCER_RETRY_BACKOFF_MS < 1:
    raise ValueError("KAFKA_PRODUCER_RETRY_BACKOFF_MS must be >= 1")
if KAFKA_PRODUCER_REQUEST_TIMEOUT_MS < 1000:
    raise ValueError("KAFKA_PRODUCER_REQUEST_TIMEOUT_MS must be >= 1000")

PRODUCER_CONFIG = {
    "bootstrap_servers": KAFKA_BOOTSTRAP,
    "acks": KAFKA_PRODUCER_ACKS,
    "enable_idempotence": KAFKA_PRODUCER_ENABLE_IDEMPOTENCE,
    "request_timeout_ms": KAFKA_PRODUCER_REQUEST_TIMEOUT_MS,
    "retry_backoff_ms": KAFKA_PRODUCER_RETRY_BACKOFF_MS,
}

def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()

def gen_value() -> float:
    v = BASE_WATTS + random.uniform(-NOISE_WATTS, NOISE_WATTS)
    return round(max(v, 0.0), 3)

async def send_with_retries(producer: AIOKafkaProducer, topic: str, key: bytes, value: bytes):
    last_error = None
    for attempt in range(1, KAFKA_PRODUCER_RETRIES + 1):
        try:
            await producer.send_and_wait(topic, key=key, value=value)
            return
        except Exception as exc:
            last_error = exc
            if attempt == KAFKA_PRODUCER_RETRIES:
                break
            await asyncio.sleep(KAFKA_PRODUCER_RETRY_BACKOFF_MS / 1000.0)
    raise last_error

async def telemetry_loop(producer: AIOKafkaProducer):
    while True:
        payload = {
            "ts": now_iso(),
            "controller_id": CONTROLLER_ID,
            "city": CITY,
            "value": gen_value(),
            "metric": "power_watts",
        }

        await send_with_retries(
            producer,
            TELEMETRY_TOPIC,
            key=CONTROLLER_ID.encode("utf-8"),
            value=json.dumps(payload).encode("utf-8"),
        )
        print(f"[{CONTROLLER_ID}] sent -> {TELEMETRY_TOPIC}: {payload}")
        await asyncio.sleep(SEND_INTERVAL)

async def command_loop():
    # Слушаем команды из COMMAND_TOPIC. 
    consumer = AIOKafkaConsumer(
        COMMAND_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP,
        group_id=f"cmd-{CONTROLLER_ID}",
        auto_offset_reset="latest",
        enable_auto_commit=True,
        key_deserializer=lambda k: k.decode("utf-8") if k else None,
        value_deserializer=lambda v: json.loads(v.decode("utf-8")),
    )
    await consumer.start()
    try:
        async for msg in consumer:
            if msg.key != CONTROLLER_ID:
                continue
            print(f"[{CONTROLLER_ID}] COMMAND <- {msg.value}")
    finally:
        await consumer.stop()

async def main():
    print(f"[{CONTROLLER_ID}] start. kafka={KAFKA_BOOTSTRAP}, ccity={CITY}")
    print(
        f"[{CONTROLLER_ID}] producer config: "
        f"acks={KAFKA_PRODUCER_ACKS}, "
        f"enable_idempotence={KAFKA_PRODUCER_ENABLE_IDEMPOTENCE}, "
        f"retries={KAFKA_PRODUCER_RETRIES}, "
        f"retry_backoff_ms={KAFKA_PRODUCER_RETRY_BACKOFF_MS}, "
        f"request_timeout_ms={KAFKA_PRODUCER_REQUEST_TIMEOUT_MS}"
    )

    producer = AIOKafkaProducer(**PRODUCER_CONFIG)
    await producer.start()
    try:
        await asyncio.gather(
            telemetry_loop(producer),
            command_loop(),
        )
    finally:
        await producer.stop()

if __name__ == "__main__":
    asyncio.run(main())
