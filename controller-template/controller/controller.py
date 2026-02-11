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

SEND_INTERVAL = float(os.getenv("SEND_INTERVAL_SEC", "5"))

BASE_WATTS = float(os.getenv("BASE_WATTS", "120.0"))
NOISE_WATTS = float(os.getenv("NOISE_WATTS", "30.0"))

def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()

def gen_value() -> float:
    v = BASE_WATTS + random.uniform(-NOISE_WATTS, NOISE_WATTS)
    return round(max(v, 0.0), 3)

async def telemetry_loop(producer: AIOKafkaProducer):
    while True:
        payload = {
            "ts": now_iso(),
            "controller_id": CONTROLLER_ID,
            "city": CITY,
            "value": gen_value(),
            "metric": "power_watts",
        }

        await producer.send_and_wait(
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

    producer = AIOKafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP)
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