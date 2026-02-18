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

# Схема base и override compose файлов
Эта схема нужна, чтобы разделить:
- **переносимое описание продукта** (Base compose)
- **локальные “хаки” для разработки** (Dev override compose)

Docker Compose при запуске автоматически **склеивает** файлы в один итоговый конфиг (override переопределяет/добавляет настройки к base).

---

## Команды запуска

### Прод/переносимый режим (только Base)
```bash
docker compose -f docker-compose.yml up -d
````

### Dev режим (Base + Override)

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

### Для контроллера с отдельным project name (чтобы у каждого была своя сеть)

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml -p ctrl_00001 up -d --build
```

---

## Зачем нужны Base и Override

### Base compose (`docker-compose.yml`)

**Цель:** описать “продукт” так, чтобы он запускался одинаково в разных окружениях.

**Что даёт:**

* переносимость (CI, сервер, чужая машина)
* минимум “магии” и привязки к локальному хосту
* единая архитектура, близкая к реальному деплою

---

### Dev override compose (`docker-compose.dev.yml`)

**Цель:** добавить только то, что удобно локально и нужно именно для разработки/симуляций.

**Что даёт:**

* удобный доступ с хоста (localhost порты)
* имитация NAT/разных сетей контроллеров
* netem (delay/loss) и любые привилегии, нужные для экспериментов
* дебаг, bind-mount исходников, hot-reload и т.п.

---

## Что кладём в Base, а что в Override

### Base compose: что должно быть внутри

Base содержит **только “суть продукта”**:

* **services**: kafka/mqtt/db/web/bridge/consumers/симулятор (в зависимости от части проекта)
* **внутренние сети** (`networks`) при необходимости
* **volumes** для хранения данных (БД и т.п.)
* **environment** без привязки к хосту:

  * адреса только по DNS сервиса внутри compose (например `kafka:9092`, `db:5432`)
  * бизнес-параметры (topic names, лог-уровни, интервалы симуляции по умолчанию)
* **depends_on** (только если нужно для порядка старта)

Base НЕ должен содержать:

* `ports:` наружу (localhost)
* `extra_hosts: host-gateway`
* `cap_add`, `privileged`
* `network_mode: "service:..."` (shared netns)
* dev-only контейнеры (netem, debug tools)
* всё, что завязано на `host.docker.internal`

---

### Dev override: что должно быть внутри

Override содержит **только dev-специфику**:

* `ports:` пробросы на localhost (Kafka UI, DB, Kafka external listener и т.д.)
* `extra_hosts: host.docker.internal:host-gateway` (если нужно)
* `cap_add: NET_ADMIN`, `privileged` — если нужно для `tc/netem` или других low-level тестов
* **netem контейнеры**
* `network_mode: "service:controller"` (shared netns для применения tc к трафику контроллера)
* bind-mount исходников + hot-reload
* debug команды, профили, “удобства”

---

### Infra (Kafka + DB + UI)

* **Base**: поднимает Kafka/DB/UI в “чистой” сетевой модели (сервисы общаются по `kafka:9092`, `timescaledb:5432`)
* **Dev override**:

  * пробрасывает порты на localhost (8080, 5432, 9092/29092)
  * добавляет внешний listener Kafka (например `29092`) для контроллеров в отдельных docker-project сетях
  * добавляет `host.docker.internal` при необходимости

### Controller template (симулятор)

* **Base**: контроллер как “продуктовый” сервис, который подключается по DNS внутри сети (например `kafka:9092`)
* **Dev override**:

  * переключает bootstrap на `host.docker.internal:29092` (чтобы контроллер в отдельной сети видел Kafka)
  * добавляет `netem` и права `NET_ADMIN`
  * добавляет `extra_hosts`


