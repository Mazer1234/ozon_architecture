# `infra`

## Назначение

Этот `docker-compose.yaml` поднимает **центральную инфраструктуру**, к которой подключаются все “контроллеры” (в отдельных docker-проектах/сетях):

* Kafka — транспорт телеметрии и команд.
* Kafka UI — просмотр топиков/сообщений/групп.
* TimescaleDB — time-series хранилище для дальнейшей записи телеметрии (в этом шаге — только база, без writer-сервиса).

## Контейнеры

### 1) `zookeeper`

**Роль:** служебный компонент для single-broker Kafka (в образах Confluent cp-kafka).

**Порты:**

* `2181:2181` — доступ с хоста (для отладки), внутри сети доступен как `zookeeper:2181`.

**Переменные окружения:**

* `ZOOKEEPER_CLIENT_PORT=2181` — порт клиента.
* `ZOOKEEPER_TICK_TIME=2000` — тик таймер (ms), техническая настройка.

---

### 2) `kafka`

**Роль:** брокер сообщений. Принимает:

* **телеметрию** от контроллеров (upstream),
* **команды** к контроллерам (downstream).

**Почему 2 listener’а и 2 порта**
В инфраструктурном compose есть два разных “типа клиентов”:

1. **внутренние сервисы инфраструктуры** (которые будут жить в этом же compose/сети)
   → они подключаются к `kafka:9092`

2. **контроллеры**, которые запускаются *как отдельные docker-compose проекты* (другие сети)
   → они не видят `kafka:9092`, но могут подключиться к Kafka через хост по `host.docker.internal:29092`

**Порты:**

* `9092:9092` — “внутренний” listener (удобно и для отладки с хоста).
* `29092:29092` — “внешний” listener для контроллеров из других docker-сетей через `host.docker.internal`.

**Важно:**
В `kafka` добавлен `extra_hosts: host.docker.internal:host-gateway`, чтобы DNS-имя `host.docker.internal` работало и в Linux Docker.

**Переменные окружения (ключевые):**

* `KAFKA_BROKER_ID=1` — id брокера (single node).
* `KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181` — подключение к zookeeper.

**Listener-конфиг:**

* `KAFKA_LISTENER_SECURITY_PROTOCOL_MAP="PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT"`
* `KAFKA_LISTENERS="PLAINTEXT://0.0.0.0:9092,PLAINTEXT_HOST://0.0.0.0:29092"`
* `KAFKA_ADVERTISED_LISTENERS="PLAINTEXT://kafka:9092,PLAINTEXT_HOST://host.docker.internal:29092"`
* `KAFKA_INTER_BROKER_LISTENER_NAME="PLAINTEXT"`

**Технические параметры для single-node:**

* `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1`
* `KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1`
* `KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1`
* `KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0`

---

### 3) `kafka-ui`

**Роль:** UI для администрирования и просмотра Kafka:

* топики, партиции,
* consumer groups,
* просмотр сообщений (для тестов).

**Порты:**

* `8080:8080` — UI доступен на `http://localhost:8080`

**Переменные окружения:**

* `KAFKA_CLUSTERS_0_NAME=local` — название кластера в UI.
* `KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS=kafka:9092` — bootstrap адрес Kafka внутри сети инфраструктуры.

---

### 4) `timescaledb`

**Роль:** База данных для временных рядов (PostgreSQL + Timescale).
На этом шаге база просто поднимается, далее к ней будет подключаться backend/writer.

**Порты:**

* `5432:5432` — доступ на хосте `localhost:5432`

**Volume:**

* `timescale_data:/var/lib/postgresql/data` — постоянное хранение данных.

**Переменные окружения:**

* `POSTGRES_DB=telemetry` — база.
* `POSTGRES_USER=telemetry` — пользователь.
* `POSTGRES_PASSWORD=telemetry` — пароль.

---

## Резюме сетевого доступа

* Сервисы **внутри infra compose** подключаются к Kafka по:
  `kafka:9092`

* Контроллеры, запущенные как **отдельные docker-compose проекты**, подключаются к Kafka по:
  `host.docker.internal:29092`

---

## Пример запуска

```bash
docker compose up -d
```


