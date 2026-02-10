import asyncio
import json
import os
from typing import Any, Dict, List, Optional

import asyncpg
from aiokafka import AIOkafkaConsumer, AIOKafkaProducer
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
TELEMETRY_TOPIC = os.getenv("TELEMETRY_TOPIC", "telemetry.v1")
COMMAND_TOPIC = os.getenv("COMMAND_TOPIC", "command.v1")
PG_DSN = os.getenv("PG_DSN", "postgresql://telemetry:telemetry@timescaledb:5432/telemetry")

app = FastAPI(title="telemetry-web-app")

pool: Optional[asyncpg.Pool] = None
producer: Optional[AIOKafkaProducer] = None
consumer_task: Optional[asyncio.Task] = None

# Далее пойдут классы
