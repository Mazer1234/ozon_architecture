import asyncio
import json
import os
import signal

import paho.mqtt.client as mqtt
from aiokafka import AIOKafkaConsumer

MQTT_HOST = os.getenv("MQTT_HOST", "emqx")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_CMD_TOPIC_PREFIX = os.getenv("MQTT_CMD_TOPIC_PREFIX", "v1/command")
MQTT_QOS = int(os.getenv("MQTT_QOS", "1"))

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "kafka:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "command.v1")
GROUP_ID = os.getenv("GROUP_ID", "kafka-to-mqtt")

stop_event = asyncio.Event()

def shutdown(*_):
    stop_event.set()

async def run():
    # MQTT publisher
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="kafka-to-mqtt", clean_session=True)
    client.reconnect_delay_set(min_delay=1, max_delay=30)
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    consumer = AIOKafkaConsumer(
        KAFKA_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP,
        group_id=GROUP_ID,
        auto_offset_reset="latest",
        enable_auto_commit=True,
        key_deserializer=lambda b: b.decode("utf-8") if b else None,
        value_deserializer=lambda b: json.loads(b.decode("utf-8")),
    )
    await consumer.start()

    try:
        async for msg in consumer:
            if stop_event.is_set():
                break
                
            controller_id = msg.key or msg.value.get("controller_id")
            if not controller_id:
                continue

            mqtt_topic = f"{MQTT_CMD_TOPIC_PREFIX}/{controller_id}"
            payload = json.dumps(msg.value).encode("utf-8")

            info = client.publish(mqtt_topic, payload, qos=MQTT_QOS, retain=False)
            if info.rc != mqtt.MQTT_ERR_SUCCESS:
                print(f"{kafka-to-mqtt} publish rc={info.rc} topic={mqtt_topic}")
            else:
                print(f"[kafka-to-mqtt] -> {mqtt_topic}: {msg.value}")

    finally:
        await consumer.stop()
        client.loop_stop()
        client.disconnect()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)
    asyncio.run(run())