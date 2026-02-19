import asyncio
import json
import os
import signal
from typing import Optional

import paho.mqtt.client as mqtt
from aiokafka import AIOKafkaProducer

MQTT_HOST = os.getenv("MQTT_HOST", "emqx")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "v1/telemetry/+")
MQTT_QOS = int(os.getenv("MQTT_QOS", "1"))

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "telemetry.v1")

# ограничиваем память, чтобы не росла очередь
QUEUE_MAX = int(os.getenv("QUEUE_MAX", "20000"))

stop_event = asyncio.Event()

def extract_controller_id(topic: str) -> str:
    # ожидаем v1/telemetry/<ctrl-id>
    parts = topic.split("/")
    return parts[2] if len(parts) >= 3 else "unknown"

async def run():
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[tuple[str, bytes]] = asyncio.Queue(maxsize=QUEUE_MAX)

    producer = AIOKafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP)
    await producer.start()

    def on_connect(client, userdata, flags, reason_code, properties=None):
        print(f"[mqtt-to-kafka] connected mqtt {MQTT_HOST}:{MQTT_PORT}, reason={reason_code}")
        client.subscribe(MQTT_TOPIC, qos=MQTT_QOS)
        print(f"[mqtt-to-kafka] subscribed {MQTT_TOPIC} qos={MQTT_QOS}")

    def on_message(client, userdata, msg):
        try:
            loop.call_soon_threadsafe(queue.put_nowait, (msg.topic, msg.payload))
        except asyncio.QueueFull:
            # при перезагрузке дропаем (потом добавим алерт)
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

            await producer.send_and_wait(
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