#!/usr/bin/env bash
set -Eeuo pipefail

KOSMO_VERSION="1.1.0"
UPSTREAM="https://raw.githubusercontent.com/eGamesAPI/remnawave-reverse-proxy/refs/heads/main/install_remnawave.sh"
BASE_DIR="/usr/local/remnawave_reverse"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$BASE_DIR/nginx"

red(){ printf '\033[1;31m%s\033[0m\n' "$*"; }
green(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
info(){ printf '\033[1;36m%s\033[0m\n' "$*"; }

trap 'red "Ошибка на строке $LINENO. Установка остановлена."' ERR

[[ $EUID -eq 0 ]] || { red "Запусти от root."; exit 1; }
command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl ca-certificates; }

[[ -f "$SCRIPT_DIR/src/nginx/install_node.sh" ]] || { red "Не найден src/nginx/install_node.sh. Запускай installer из полного клона репозитория."; exit 1; }
[[ -f "$SCRIPT_DIR/bin/kosmo-node" ]] || { red "Не найден bin/kosmo-node. Запускай installer из полного клона репозитория."; exit 1; }

info "Kosmo Remnawave Node bootstrap v$KOSMO_VERSION"
info "Основа: актуальный eGamesAPI/remnawave-reverse-proxy + усиленный модуль Node + генератор современных Xray профилей"

mkdir -p "$MODULE_DIR" /usr/local/bin /usr/local/share/kosmo-node

TMP_UPSTREAM="$(mktemp)"
curl -fL --retry 3 --connect-timeout 10 --max-time 60 "$UPSTREAM" -o "$TMP_UPSTREAM"
head -n1 "$TMP_UPSTREAM" | grep -q '^#!/bin/bash' || { red "Upstream installer повреждён."; exit 1; }
UPSTREAM_SHA="$(sha256sum "$TMP_UPSTREAM" | awk '{print $1}')"
UPSTREAM_VER="$(grep -m1 '^SCRIPT_VERSION=' "$TMP_UPSTREAM" | cut -d'"' -f2 || true)"
green "eGames installer загружен: version=${UPSTREAM_VER:-unknown}, sha256=$UPSTREAM_SHA"

install -m 755 "$SCRIPT_DIR/src/nginx/install_node.sh" "$MODULE_DIR/install_node.sh"
install -m 755 "$SCRIPT_DIR/bin/kosmo-node" /usr/local/bin/kosmo-node
install -m 755 "$TMP_UPSTREAM" "$BASE_DIR/remnawave_reverse"
ln -sf "$BASE_DIR/remnawave_reverse" /usr/local/bin/remnawave_reverse
rm -f "$TMP_UPSTREAM"

cat > "$BASE_DIR/kosmo-build.info" <<INFO
KOSMO_VERSION=$KOSMO_VERSION
UPSTREAM_VERSION=${UPSTREAM_VER:-unknown}
UPSTREAM_SHA256=$UPSTREAM_SHA
INSTALLED_AT=$(date -u +%FT%TZ)
PROFILE_GENERATOR=xhttp,raw,both
INFO

green "Bootstrap готов. Запускаю официальный интерфейс eGames с нашим Node-модулем."
yellow "Для отдельной ноды выбирай: Install Remnawave Components -> Install node only -> Nginx."
yellow "После успешной установки Node можно сгенерировать профиль: kosmo-node profile xhttp"
yellow "Альтернативы: kosmo-node profile raw | kosmo-node profile both"
echo
exec "$BASE_DIR/remnawave_reverse"
