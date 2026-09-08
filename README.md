# Kosmo Remnawave Node Installer

Усиленный bootstrap для отдельной Remnawave Node. Основан на актуальном `eGamesAPI/remnawave-reverse-proxy` и дополнен генератором современных Xray-профилей для Remnawave.

## Что делает

- скачивает актуальный upstream eGames installer;
- ставит отдельную Remnawave Node через Nginx/self-steal;
- выбирает свежий стабильный semver-тег `remnawave/node` с Docker Hub, fallback `latest`;
- всегда выполняет `docker compose pull` перед запуском;
- использует `pull_policy: always`;
- проверяет `SECRET_KEY` до записи;
- проверяет DNS домена ноды против публичного IPv4;
- делает backup существующей `/opt/remnanode`;
- открывает 443/tcp и 80/tcp, а 2222/tcp разрешает только IP панели;
- ставит `kosmo-node` для диагностики, обновления, генерации Reality-ключей и Config Profile;
- не считает отсутствие `443/rw-core` сразу после установки ошибкой: rw-core появляется после успешной передачи Xray-конфига из Remnawave Panel.

## Поддерживаемые профили

### XHTTP + REALITY — рекомендуемый современный вариант

Генератор использует self-steal через `/dev/shm/nginx.sock`, `xver: 1`, случайный Path, `mode: auto`, отдельную X25519-пару и ShortID. Для Host выводится fingerprint `qq`, который уже проверен в нашем проекте с Happ.

```bash
kosmo-node profile xhttp
```

Расширенный вариант:

```bash
kosmo-node profile xhttp CZ-XHTTP-001 443 chehiya-kosmo-vpn.mooo.com /my-path
```

Если Path не указан, он генерируется автоматически.

### RAW + REALITY + Vision

Современное имя прямого TCP-транспорта Xray. Генерируется VLESS + RAW + REALITY + `xtls-rprx-vision`.

```bash
kosmo-node profile raw
```

По умолчанию используется `max.ru` как SNI/dest для совместимости с нашей рабочей схемой.

### XHTTP + RAW одновременно

Создаёт один Config Profile с двумя inbound:

- 443/tcp — XHTTP + REALITY;
- 8444/tcp — RAW + REALITY + Vision.

```bash
kosmo-node profile both
```

Подходит для одной ноды с основным XHTTP и резервным RAW.

## Установка из private GitHub

Репозиторий приватный, поэтому обычный unauthenticated raw URL не работает. Сначала клонируй репозиторий с PAT, у которого есть `Contents: Read` для `my-skript-dlya-nod`, затем запускай локальный installer:

```bash
git clone https://github.com/netawuuu1112/my-skript-dlya-nod.git
cd my-skript-dlya-nod
chmod +x install.sh
bash ./install.sh
```

Далее в интерфейсе eGames:

`Install Remnawave Components -> Install node only -> Nginx`

После успешной установки Node для Чехии:

```bash
kosmo-node profile xhttp CZ-XHTTP-001 443 chehiya-kosmo-vpn.mooo.com
```

Команда сама создаст случайный Path, Reality keypair и ShortID, откроет порт и напечатает параметры Host для Remnawave. JSON сохраняется в:

```text
/opt/remnanode/generated-profiles/xhttp-reality.json
```

## Команды

```bash
kosmo-node status
kosmo-node doctor
kosmo-node restart
kosmo-node update
kosmo-node keys
kosmo-node logs
kosmo-node profile xhttp
kosmo-node profile raw
kosmo-node profile both
```

## Рабочая схема проекта

- Node API: `2222/tcp`
- пользовательские inbound: обычно `443/tcp`, резервный RAW в dual-profile — `8444/tcp`
- Node устанавливается из свежего стабильного `remnawave/node`;
- Xray берётся из образа Node;
- fingerprint Host для проекта: `qq`;
- для XHTTP flow оставляется пустым;
- для RAW используется `xtls-rprx-vision`;
- `minClientVer`: `1.8.0` для совместимости с нашей текущей Happ-схемой.

## Откуда взяты решения

Мы не копируем чужие one-click скрипты целиком. Используются проверенные архитектурные идеи и актуальный синтаксис из нескольких источников:

- `eGamesAPI/remnawave-reverse-proxy` — базовая установка Node/Nginx/self-steal;
- `TrulyInfinite/remnawave` — Remnawave-specific XHTTP + REALITY self-steal через unix socket;
- `tao-t356/vless-xhttp-reality-self` — современный XHTTP + REALITY self-steal deployment как дополнительный референс;
- `ike-sh/Xray-OneClick` — актуальная реализация отдельного режима XHTTP + REALITY;
- `superchaospc/xray-xhttp-relay` — дополнительный современный XHTTP deployment reference;
- `XTLS/Xray-core` discussions #4118 и #4232 — upstream-примеры XHTTP/REALITY и комбинированных схем.

Главный принцип проекта: Remnawave продолжает управлять пользователями и runtime Xray. Установщик не ставит отдельный второй Xray поверх Remnanode и не ломает модель Panel -> Node.

## Важное

Сгенерированный Config Profile автоматически не записывается в панель. Это специально: сервер панели не изменяется установщиком. JSON выводится и сохраняется локально на Node, после чего его можно вставить в Remnawave Config Profile вручную.
