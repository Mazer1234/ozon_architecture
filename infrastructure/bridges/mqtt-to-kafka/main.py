import asyncio
import json
import os
import signal

import paho.mqtt.client as mqtt
from aiokafka import AIOKafkaProducer

MQTT_HOST = os.getenv("MQTT_HOST", "emqx")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "v1/telemetry/+")
MQTT_QOS = int(os.getenv("MQTT_QOS", "1"))

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "telemetry.v1")
KAFKA_PRODUCER_ACKS_RAW = os.getenv("KAFKA_PRODUCER_ACKS", "all")
KAFKA_PRODUCER_ENABLE_IDEMPOTENCE = os.getenv("KAFKA_PRODUCER_ENABLE_IDEMPOTENCE", "true").strip().lower() in (
    "1",
    "true",
    "yes",
    "on",
)
KAFKA_PRODUCER_RETRIES = int(os.getenv("KAFKA_PRODUCER_RETRIES", "5"))
KAFKA_PRODUCER_RETRY_BACKOFF_MS = int(os.getenv("KAFKA_PRODUCER_RETRY_BACKOFF_MS", "100"))
KAFKA_PRODUCER_REQUEST_TIMEOUT_MS = int(os.getenv("KAFKA_PRODUCER_REQUEST_TIMEOUT_MS", "30000"))

# Keep bounded memory in case of downstream pressure.
QUEUE_MAX = int(os.getenv("QUEUE_MAX", "20000"))

stop_event = asyncio.Event()


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


def extract_controller_id(topic: str) -> str:
    parts = topic.split("/")
    return parts[2] if len(parts) >= 3 else "unknown"


async def run():
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[tuple[str, bytes]] = asyncio.Queue(maxsize=QUEUE_MAX)

    producer = AIOKafkaProducer(**PRODUCER_CONFIG)
    await producer.start()
    print(
        "[mqtt-to-kafka] producer config: "
        f"acks={KAFKA_PRODUCER_ACKS}, "
        f"enable_idempotence={KAFKA_PRODUCER_ENABLE_IDEMPOTENCE}, "
        f"retries={KAFKA_PRODUCER_RETRIES}, "
        f"retry_backoff_ms={KAFKA_PRODUCER_RETRY_BACKOFF_MS}, "
        f"request_timeout_ms={KAFKA_PRODUCER_REQUEST_TIMEOUT_MS}"
    )

    async def send_with_retries(topic: str, key: bytes, value: bytes):
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

    def on_connect(client, userdata, flags, reason_code, properties=None):
        print(f"[mqtt-to-kafka] connected mqtt {MQTT_HOST}:{MQTT_PORT}, reason={reason_code}")
        client.subscribe(MQTT_TOPIC, qos=MQTT_QOS)
        print(f"[mqtt-to-kafka] subscribed {MQTT_TOPIC} qos={MQTT_QOS}")

    def on_message(client, userdata, msg):
        try:
            loop.call_soon_threadsafe(queue.put_nowait, (msg.topic, msg.payload))
        except asyncio.QueueFull:
            pass

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="mqtt-to-kafka", clean_session=True)
    client.on_connect = on_connect
    client.on_message = on_message
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    try:
        while not stop_event.is_set():
            topic, payload = await queue.get()
            controller_id = extract_controller_id(topic)

            try:
                data = json.loads(payload.decode("utf-8"))
            except Exception:
                data = {"raw": payload.decode("utf-8", error="ignore")}

            data.setdefault("controller_id", controller_id)

            await send_with_retries(
                KAFKA_TOPIC,
                key=controller_id.encode("utf-8"),
                value=json.dumps(data).encode("utf-8"),
            )
    finally:
        client.loop_stop()
        client.disconnect()
        await producer.stop()


def shutdown(*_):
    stop_event.set()


if __name__ == "__main__":
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)
    asyncio.run(run())
