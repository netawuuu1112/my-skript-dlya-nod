# Kosmo Remnawave Node Installer

Усиленный bootstrap поверх актуального `eGamesAPI/remnawave-reverse-proxy` для установки отдельной Remnawave Node.

## Что исправлено

- всегда скачивается актуальный upstream eGames installer;
- для Node используется свежий стабильный semver-тег `remnawave/node` с Docker Hub (fallback `latest`);
- `docker compose pull` выполняется **до** запуска, поэтому старый cached image вроде Node 2.8.0 не остаётся;
- `pull_policy: always` для Node и Nginx;
- `docker compose config` до запуска;
- проверка структуры `SECRET_KEY` до записи;
- проверка DNS домена на IP текущего сервера;
- безопасный backup старой `/opt/remnanode`;
- firewall: 443 публично, 2222 только от IP панели, 80 для ACME;
- уменьшена ротация Docker-логов (20MB x 3);
- `nginx:stable` вместо зафиксированного старого Nginx;
- диагностические проверки после установки;
- отсутствие `443/rw-core` сразу после install не считается ошибкой: он появится после Panel -> Node и передачи Xray-конфига;
- добавлена утилита `kosmo-node`.

## Установка

```bash
bash <(curl -Ls https://raw.githubusercontent.com/netawuuu1112/my-skript-dlya-nod/main/install.sh)
```

Далее в меню eGames: **Install Remnawave Components -> Install node only -> Nginx**.

## Команды

```bash
kosmo-node status
kosmo-node doctor
kosmo-node restart
kosmo-node update
kosmo-node keys
kosmo-node logs
```

## Рабочая схема проекта

- Node API: `2222/tcp`
- Xray VLESS/Reality: `443/tcp`
- актуальный Node на момент подготовки: `3.4.1`
- bundled Xray в Node 3.4.1: `26.7.28`

Для пользовательских Host-профилей проекта рабочий fingerprint: `qq`.
