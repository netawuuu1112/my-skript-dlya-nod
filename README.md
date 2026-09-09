# Kosmo Remnawave Node Manager v2.0.1

Один самодостаточный файл `install.sh` для безопасной работы с отдельной Remnawave Node и генерации актуальных Xray Config Profile.

## Главный принцип

Скрипт не патчит сервер панели и не подменяет код Remnawave Panel. Для установки Node он скачивает и запускает актуальный официальный/community installer `eGamesAPI/remnawave-reverse-proxy` без изменений. Все дополнительные функции Kosmo работают локально на сервере Node.

Есть отдельная защита от запуска изменяющих операций на сервере панели: блокируется известный IP панели `147.45.219.190`, а также серверы, где обнаружены типичные контейнеры Remnawave Panel (`remnawave`, `remnawave-backend`, `remnawave-db`, `remnawave-redis`, `remnawave-subscription-page`).

## Запуск

Нужен только один файл:

```bash
chmod +x install.sh
bash ./install.sh
```

Для private GitHub сначала скачай `install.sh` авторизованным способом или клонируй репозиторий, но для самой работы остальные файлы репозитория больше не требуются.

## Главное меню

```text
Kosmo Remnawave Node Manager v2.0.1

 1) Установить / переустановить Node через официальный eGames
 2) Создать Config Profile: XHTTP + REALITY
 3) Создать Config Profile: RAW + REALITY + Vision
 4) Создать Config Profile: XHTTP + RAW
 5) Статус Node
 6) Полная диагностика
 7) Перезапустить только remnanode
 8) Безопасно обновить образ remnanode
 9) Логи remnanode
10) Сгенерировать Reality keys + ShortID
11) Backup /opt/remnanode
12) Показать источники/референсы
 0) Выход
```

## Что делает каждый пункт

### 1. Установить / переустановить Node

Сначала срабатывает защита панели. Затем скачивается актуальный `install_remnawave.sh` из `eGamesAPI/remnawave-reverse-proxy`, проверяется shebang, показываются версия и SHA256 и запускается оригинальный upstream-файл без патчей.

В меню eGames для отдельной ноды нужно выбирать:

`Install Remnawave Components -> Install node only -> Nginx`

### 2. XHTTP + REALITY

Генерирует новый X25519 keypair, ShortID и случайный Path. Создаётся Config Profile с:

- VLESS;
- `network: xhttp`;
- `security: reality`;
- `mode: auto`;
- self-steal target `/dev/shm/nginx.sock`;
- `xver: 1`;
- Flow пустой;
- fingerprint Host: `qq`;
- `minClientVer: 1.8.0` для текущей Happ-схемы проекта.

JSON: `/opt/remnanode/generated-profiles/xhttp-reality.json`

Параметры Host: `/opt/remnanode/generated-profiles/xhttp-host.txt`

### 3. RAW + REALITY + Vision

Генерирует современный прямой RAW/TCP REALITY профиль. Используется:

- VLESS;
- `network: raw`;
- REALITY;
- target/SNI по умолчанию `max.ru:443` / `max.ru`;
- Flow для Host: `xtls-rprx-vision`;
- fingerprint Host: `qq`.

В самом серверном шаблоне `settings.clients` остаётся пустым, как в актуальном шаблоне Remnawave; Flow задаётся в Host/выдаваемом клиентском профиле, а не нестандартным глобальным полем inbound.

JSON: `/opt/remnanode/generated-profiles/raw-reality.json`

### 4. XHTTP + RAW

Создаёт один Config Profile с двумя inbound:

- `443/tcp` — XHTTP + REALITY;
- `8444/tcp` — RAW + REALITY + Vision.

Файл: `/opt/remnanode/generated-profiles/xhttp-raw-reality.json`

### 5. Статус

Показывает контейнеры, версии Remnawave Node/Xray, порты 2222/443/8444/80, self-steal домен и UFW. Ничего не изменяет.

### 6. Диагностика

Показывает IPv4, ОС/ядро, `docker compose config`, image/NODE_PORT, SECRET_KEY только в скрытом виде, версии, порты, routing и последние логи. Ничего не меняет.

### 7. Restart

Перезапускает только контейнер `remnanode`, не панель и не весь Docker Compose stack. После рестарта показывает статус.

### 8. Safe Update Node

Перед изменением делает backup `docker-compose.yml`, проверяет compose, выполняет `docker compose pull remnanode` и пересоздаёт только `remnanode` через `--no-deps --force-recreate`. Nginx и панель не пересоздаются.

### 9. Логи

Показывает последние 150 строк и live-log контейнера `remnanode`.

### 10. Reality keys

Через Xray внутри текущего контейнера Node генерирует X25519 Private/Public Key и 16-hex ShortID.

### 11. Backup

Создаёт архив всей `/opt/remnanode` в `/root/remnanode-backup-DATE-TIME.tar.gz`.

### 12. Sources

Показывает источники, по которым сверялась архитектура и синтаксис.

## Почему v2 безопаснее старой версии

Старая версия Kosmo заменяла Node-модуль eGames собственным `src/nginx/install_node.sh`. В v2 этот подход убран из основного пути: `install.sh` больше не внедряет свой модуль внутрь eGames. Это уменьшает риск несовместимости после обновлений Remnawave/eGames. Установка Node остаётся upstream-native, а наши функции отделены и работают только после установки Node.

Скрипт также не меняет `SECRET_KEY`, не пишет в БД панели, не меняет конфиги панели, не выполняет `docker compose down` и не обновляет весь stack при обычном обновлении Node.

## Актуальные источники, использованные при ревизии

- `eGamesAPI/remnawave-reverse-proxy` — текущий installer Node/Nginx/self-steal;
- `remnawave/templates` — актуальный пример VLESS REALITY с `network: raw` и `target`;
- `XTLS/Xray-docs-next` — актуальная документация REALITY: совместимость с RAW, XHTTP и gRPC, поле `target`, старое `dest` как alias;
- `XTLS/Xray-examples` — VLESS RAW/TCP + REALITY + Vision;
- `XTLS/Xray-core` discussion #4118 — рабочие XHTTP + REALITY конфигурации, `mode: auto`, сложный Path;
- `TrulyInfinite/remnawave` — Remnawave-specific XHTTP + REALITY self-steal через `/dev/shm/nginx.sock` и `xver: 1`;
- `tao-t356/vless-xhttp-reality-self` — дополнительный современный XHTTP/REALITY reference;
- `ike-sh/Xray-OneClick` — дополнительный свежий XHTTP/REALITY reference.

## Важные технические решения

- RAW — актуальное название прямого TCP transport в современных шаблонах Xray/Remnawave.
- REALITY в текущей документации поддерживает RAW, XHTTP и gRPC.
- Для XHTTP Flow оставляется пустым: XHTTP + Vision не используется как базовая схема.
- Для RAW клиентскому Host задаётся `xtls-rprx-vision`.
- Для XHTTP используется `mode: auto` и случайный длинный Path.
- В server-side REALITY используется `target`, а не устаревшее имя `dest`.
- Порт `2222` — Node API Panel -> Node. Порты пользовательских inbound (`443`, `8444`) появляются у `rw-core` после передачи соответствующего Config Profile из панели.
