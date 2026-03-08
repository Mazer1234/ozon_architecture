# `controller-template`

## Назначение

Этот `docker-compose.yaml` — **шаблон одного контроллера**.
Его идея: каждый контроллер запускается отдельным `docker compose -p <project>` → у каждого своя сеть, имитация “разных NAT/локаций”.

Внутри шаблона:

* `branding_mock` — источник “данных от элементов брендинга”
* `controller` — псевдо-контроллер (в нашем шаге заглушка/placeholder)
* `netem` — имитация задержек/потерь на сети контроллера через `tc netem`

Контроллер **не публикует порты наружу**, тем самым имитируется NAT: контроллер только инициирует исходящие соединения к Kafka.

---

## Контейнеры

### 1) `branding_mock`

**Роль:** генератор “событий”/сигналов от элементов брендинга.

**Что делает в текущем шаблоне:**

* раз в 5 секунд отправляет UDP пакет `branding_ping` на `controller:9000`

**Зависимости:**

* `depends_on: controller` — чтобы “контроллер” стартовал первым.

**Переменные окружения:**
В текущей версии нет обязательных переменных.

---

### 2) `controller`

**Роль:** псевдо-контроллер (Wirenboard-like).
В дальнейшем он будет:

* принимать локальные события (например от `branding_mock`),
* отправлять телеметрию в Kafka в `TELEMETRY_TOPIC`,
* слушать команды из Kafka в `COMMAND_TOPIC` и выполнять их.

Сейчас в compose стоит “заглушка” контейнер (для фиксации архитектуры), но env уже заложены.

**Порты:**

* наружу **не публикуются** (имитация NAT)
* внутри сети может слушать `9000/udp` для `branding_mock` (если вы добавите реальный сервис)

**Важное про доступ к Kafka**

* контроллер подключается к Kafka через:

  * `KAFKA_BOOTSTRAP_SERVERS=host.docker.internal:29092`

**Почему `extra_hosts`:**

* `extra_hosts: host.docker.internal:host-gateway`
  нужно, чтобы `host.docker.internal` корректно резолвился в контейнере (особенно на Linux).

**Переменные окружения (основные):**

* `CONTROLLER_ID`
  Уникальный id контроллера (например `ctrl-00001`). Используется для:

  * ключа сообщений,
  * фильтрации команд,
  * логирования и идентификации в БД.

* `CITY`
  Город/локация (например `moscow`). Можно использовать для:

  * маршрутизации (topic per city),
  * аналитики,
  * имитации распределённой географии.

* `TELEMETRY_TOPIC`
  Kafka топик, куда контроллер публикует телеметрию.
  Пример: `telemetry.v1`

* `COMMAND_TOPIC`
  Kafka топик, откуда контроллер читает команды.
  Пример: `command.v1`

* `KAFKA_BOOTSTRAP_SERVERS`
  Адрес Kafka bootstrap. По умолчанию: `host.docker.internal:29092`
  Это важно, потому что контроллер в другой docker-сети и не видит `kafka:9092`.

* `SEND_INTERVAL_SEC`
  Интервал отправки телеметрии (в будущем). Сейчас — просто параметр для симулятора.

---

### 3) `netem`

**Роль:** симуляция плохой сети (delay/jitter/loss) на интерфейсе контроллера.

**Ключевая настройка:**

* `network_mode: "service:controller"`
  Это означает, что `netem` разделяет network namespace с `controller`, поэтому `tc netem` применяется к трафику контроллера.

**Права:**

* `cap_add: NET_ADMIN` — нужно для `tc qdisc`.

**Переменные окружения:**

* `NETEM_DELAY_MS`
  Средняя задержка в миллисекундах (например `100`).

* `NETEM_JITTER_MS`
  Джиттер к задержке в миллисекундах (например `20`).
  Если 0 — джиттер не применяется.

* `NETEM_LOSS_PCT`
  Потери пакетов в процентах (например `1` или `2.5`).

---

## Пример `.env` для одного контроллера

```env
CONTROLLER_ID=ctrl-00001
CITY=moscow

KAFKA_BOOTSTRAP_SERVERS=host.docker.internal:29092
TELEMETRY_TOPIC=telemetry.v1
COMMAND_TOPIC=command.v1

SEND_INTERVAL_SEC=5

NETEM_DELAY_MS=50
NETEM_JITTER_MS=10
NETEM_LOSS_PCT=1
```

---

## Пример запуска одного контроллера отдельным проектом

```bash
docker compose -p ctrl_00001 --env-file .env up -d
```

> За счёт `-p ctrl_00001` создаётся отдельная docker-сеть и изоляция как у “реально отдельного устройства”.

## Скрипты массового управления контроллерами

В проекте есть готовые скрипты для Powershell:

- `controller-template/scripts/start-controllers.ps1` — поднимает `N` контейнеров-контроллеров, каждому генерирует свой `.env`.
- `controller-template/scripts/stop-controllers.ps1` — останавливает все контейнеры-контроллеры (или по префиксу проекта).
- `controller-template/scripts/list-controllers.ps1` — показывает список всех запущенных контейнеров-контроллеров.

Полный список флагов (PowerShell):

- `start-controllers.ps1`:
  - `-Count` — число контроллеров
  - `-StartIndex` — начальный индекс нумерации (по умолчанию: `1`)
  - `-ProjectPrefix` — префикс docker-проекта (по умолчанию: `ctrl`)
  - `-ControllerIdPrefix` — префикс `controller_id` (по умолчанию: `ctrl`)
  - `-City` — город или `random` (по умолчанию: `random`)
  - `-Cities` — список городов random (по умолчанию: `moscow, spb, kazan, ekb, novgorod, perm, rostov, sochi`)
  - `-TelemetryTopic` — топик телеметрии Kafka (по умолчанию: `telemetry.v1`)
  - `-CommandTopic` — топик команд Kafka (по умолчанию: `command.v1`)
  - `-KafkaBootstrapServers` — bootstrap-адрес Kafka (по умолчанию: `host.docker.internal:29092`)
  - `-KafkaProducerAcks` — режим подтверждений producer (по умолчанию: `all`)
  - `-KafkaProducerEnableIdempotence` — включение идемпотентности producer (по умолчанию: `true`)
  - `-KafkaProducerRetries` — число повторных отправок (по умолчанию: `5`)
  - `-KafkaProducerRetryBackoffMs` — пауза между ретраями (по умолчанию: `100`)
  - `-KafkaProducerRequestTimeoutMs` — таймаут запроса producer (по умолчанию: `30000`)
  - `-SendIntervalSec` — интервал в секундах (по умолчанию: `5`)
  - `-SendIntervalMin` — интервал в минутах (по умолчанию: не задан)
  - `-BaseWatts` — базовая мощность нагрузки (по умолчанию: `120`)
  - `-NoiseWatts` — амплитуда шумовой мощности (по умолчанию: `30`)
  - `-NetemDelayMs` — сетевой delay netem (по умолчанию: `0`)
  - `-NetemJitterMs` — сетевой jitter netem (по умолчанию: `0`)
  - `-NetemLossPct` — процент сетевых потерь (по умолчанию: `0`)
  - `-Build` — пересборка образов перед запуском (по умолчанию: выключен)
- `list-controllers.ps1`:
  - `-ProjectPrefix` — фильтр префикса проекта (по умолчанию: без фильтра)
- `stop-controllers.ps1`:
  - `-ProjectPrefix` — фильтр префикса проекта (по умолчанию: без фильтра)
  - `-RemoveVolumes` — удаление томов проекта (по умолчанию: выключен)
- Все `*.ps1`:
  - `-Verbose` — подробный вывод команд
  - `-Debug` — отладочный режим PowerShell
  - `-ErrorAction` — политика обработки ошибок

Примеры:

```powershell
powershell -File .\controller-template\scripts\start-controllers.ps1 -Count 5
powershell -File .\controller-template\scripts\start-controllers.ps1 -Count 5 -City random -Cities moscow,spb,kazan
powershell -File .\controller-template\scripts\start-controllers.ps1 -Count 3 -SendIntervalMin 1 -KafkaProducerAcks all -KafkaProducerEnableIdempotence true
powershell -File .\controller-template\scripts\list-controllers.ps1
powershell -File .\controller-template\scripts\stop-controllers.ps1
```

Также доступны shell-скрипты для Linux/macOS:

- `controller-template/scripts/start-controllers.sh`
- `controller-template/scripts/list-controllers.sh`
- `controller-template/scripts/stop-controllers.sh`

Полный список флагов (shell):

- `start-controllers.sh`:
  - `--count` — число контроллеров
  - `--start-index` — начальный индекс нумерации (по умолчанию: `1`)
  - `--project-prefix` — префикс docker-проекта (по умолчанию: `ctrl`)
  - `--controller-id-prefix` — префикс `controller_id` (по умолчанию: `ctrl`)
  - `--city` — город или `random` (по умолчанию: `random`)
  - `--cities` — список городов random (по умолчанию: `moscow spb kazan ekb novgorod perm rostov sochi`)
  - `--telemetry-topic` — топик телеметрии Kafka (по умолчанию: `telemetry.v1`)
  - `--command-topic` — топик команд Kafka (по умолчанию: `command.v1`)
  - `--kafka-bootstrap` — bootstrap-адрес Kafka (по умолчанию: `host.docker.internal:29092`)
  - `--kafka-producer-acks` — режим подтверждений producer (по умолчанию: `all`)
  - `--kafka-idempotence` — включение идемпотентности producer (по умолчанию: `true`)
  - `--kafka-retries` — число повторных отправок (по умолчанию: `5`)
  - `--kafka-retry-backoff-ms` — пауза между ретраями (по умолчанию: `100`)
  - `--kafka-request-timeout-ms` — таймаут запроса producer (по умолчанию: `30000`)
  - `--send-interval-sec` — интервал в секундах (по умолчанию: `5`)
  - `--send-interval-min` — интервал в минутах (по умолчанию: не задан)
  - `--base-watts` — базовая мощность нагрузки (по умолчанию: `120`)
  - `--noise-watts` — амплитуда шумовой мощности (по умолчанию: `30`)
  - `--netem-delay-ms` — сетевой delay netem (по умолчанию: `0`)
  - `--netem-jitter-ms` — сетевой jitter netem (по умолчанию: `0`)
  - `--netem-loss-pct` — процент сетевых потерь (по умолчанию: `0`)
  - `--build` — пересборка образов перед запуском (по умолчанию: выключен)
  - `-h` — показать справку
  - `--help` — показать справку
- `list-controllers.sh`:
  - `--project-prefix` — фильтр префикса проекта (по умолчанию: без фильтра)
  - `-h` — показать справку
  - `--help` — показать справку
- `stop-controllers.sh`:
  - `--project-prefix` — фильтр префикса проекта (по умолчанию: без фильтра)
  - `--remove-volumes` — удаление томов проекта (по умолчанию: выключен)
  - `-h` — показать справку
  - `--help` — показать справку

Примеры:

```bash
sh ./controller-template/scripts/start-controllers.sh --count 5
sh ./controller-template/scripts/start-controllers.sh --count 5 --city random --cities "moscow spb kazan"
sh ./controller-template/scripts/start-controllers.sh --count 3 --send-interval-min 1 --kafka-producer-acks all --kafka-idempotence true
sh ./controller-template/scripts/list-controllers.sh
sh ./controller-template/scripts/stop-controllers.sh
```

С фильтром по префиксу проекта:

```bash
sh ./controller-template/scripts/list-controllers.sh --project-prefix ctrl
sh ./controller-template/scripts/stop-controllers.sh --project-prefix ctrl
```
