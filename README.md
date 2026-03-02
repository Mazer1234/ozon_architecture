Запуск infrastructure
```bash
docker compose -f .\infrastructure\docker-compose.yaml -f .\infrastructure\docker-compose.dev.yaml up -d
```

```bash
docker compose -f .\infrastructure\docker-compose.yaml -f .\infrastructure\docker-compose.dev.yaml run --rm kafka-init
```