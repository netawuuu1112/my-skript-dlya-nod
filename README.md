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
- после установки автоматически запускает мастер выбора транспорта;
- не считает отсутствие `443/rw-core` сразу после установки ошибкой: rw-core появляется после успешной передачи Xray-конфига из Remnawave Panel.

## Автоматический мастер после установки

После успешного развёртывания Node появится меню:

```text
1) XHTTP + REALITY        [рекомендуется]
2) RAW + REALITY + Vision [резерв/совместимость]
3) XHTTP + RAW            [два inbound на одной Node]
4) Пропустить
```

Если просто нажать Enter, выбирается XHTTP + REALITY.

Мастер автоматически генерирует X25519 keypair, ShortID, случайный XHTTP Path, открывает нужные порты, сохраняет готовый Config Profile и выводит точные параметры Host для Remnawave.

## Поддерживаемые профили

### XHTTP + REALITY — рекомендуемый современный вариант

Используется self-steal через `/dev/shm/nginx.sock`, `xver: 1`, `mode: auto`, случайный Path, отдельная X25519-пара и ShortID. Для Host выводится fingerprint `qq`, который уже проверен в проекте с Happ. Flow оставляется пустым.

Ручной запуск:

```bash
kosmo-node profile xhttp
```

Для Чехии:

```bash
kosmo-node profile xhttp CZ-XHTTP-001 443 chehiya-kosmo-vpn.mooo.com
```

Если Path не указан, он генерируется автоматически.

### RAW + REALITY + Vision

Прямой RAW/TCP-транспорт Xray с VLESS + REALITY + `xtls-rprx-vision`.

```bash
kosmo-node profile raw
```

По умолчанию используется `max.ru` как SNI/target для совместимости с нашей рабочей схемой.

### XHTTP + RAW одновременно

Создаёт один Config Profile с двумя inbound:

- 443/tcp — XHTTP + REALITY;
- 8444/tcp — RAW + REALITY + Vision.

```bash
kosmo-node profile both
```

## Установка из private GitHub

Репозиторий приватный. Клонируй его с GitHub PAT, которому разрешён `Contents: Read` для `my-skript-dlya-nod`, затем запускай локальный installer:

```bash
git clone https://github.com/netawuuu1112/my-skript-dlya-nod.git
cd my-skript-dlya-nod
chmod +x install.sh
bash ./install.sh
```

Далее в интерфейсе eGames:

`Install Remnawave Components -> Install node only -> Nginx`

После установки отдельную команду для генерации профиля вводить уже не обязательно — мастер запустится автоматически.

Готовые JSON сохраняются в:

```text
/opt/remnanode/generated-profiles/
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
- `minClientVer`: `1.8.0` для совместимости с текущей Happ-схемой.

## Источники архитектуры

Мы не копируем чужие one-click скрипты целиком. Используются проверенные архитектурные идеи и актуальный синтаксис из нескольких источников:

- `eGamesAPI/remnawave-reverse-proxy` — базовая установка Node/Nginx/self-steal;
- `TrulyInfinite/remnawave` — Remnawave-specific XHTTP + REALITY self-steal через unix socket;
- `tao-t356/vless-xhttp-reality-self` — современный XHTTP + REALITY self-steal deployment как дополнительный референс;
- `ike-sh/Xray-OneClick` — современный отдельный режим XHTTP + REALITY;
- официальная документация `XTLS/Xray-docs-next` — актуальные поля `target`, RAW/XHTTP/REALITY и совместимость транспортов.
