#!/usr/bin/env bash
set -Eeuo pipefail

KOSMO_VERSION="1.0.0"
UPSTREAM="https://raw.githubusercontent.com/eGamesAPI/remnawave-reverse-proxy/refs/heads/main/install_remnawave.sh"
BASE_DIR="/usr/local/remnawave_reverse"
MODULE_DIR="$BASE_DIR/nginx"
SELF_URL="https://raw.githubusercontent.com/netawuuu1112/my-skript-dlya-nod/main/install.sh"
MODULE_URL="https://raw.githubusercontent.com/netawuuu1112/my-skript-dlya-nod/main/src/nginx/install_node.sh"
HELPER_URL="https://raw.githubusercontent.com/netawuuu1112/my-skript-dlya-nod/main/bin/kosmo-node"

red(){ printf '\033[1;31m%s\033[0m\n' "$*"; }
green(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
info(){ printf '\033[1;36m%s\033[0m\n' "$*"; }

trap 'red "Ошибка на строке $LINENO. Установка остановлена."' ERR

[[ $EUID -eq 0 ]] || { red "Запусти от root."; exit 1; }
command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl ca-certificates; }

info "Kosmo Remnawave Node bootstrap v$KOSMO_VERSION"
info "Основа: актуальный eGamesAPI/remnawave-reverse-proxy + усиленный модуль установки Node"

mkdir -p "$MODULE_DIR" /usr/local/bin

TMP_UPSTREAM="$(mktemp)"
curl -fL --retry 3 --connect-timeout 10 --max-time 60 "$UPSTREAM" -o "$TMP_UPSTREAM"
head -n1 "$TMP_UPSTREAM" | grep -q '^#!/bin/bash' || { red "Upstream installer повреждён."; exit 1; }
UPSTREAM_SHA="$(sha256sum "$TMP_UPSTREAM" | awk '{print $1}')"
UPSTREAM_VER="$(grep -m1 '^SCRIPT_VERSION=' "$TMP_UPSTREAM" | cut -d'"' -f2 || true)"
green "eGames installer загружен: version=${UPSTREAM_VER:-unknown}, sha256=$UPSTREAM_SHA"

curl -fL --retry 3 --connect-timeout 10 --max-time 60 "$MODULE_URL" -o "$MODULE_DIR/install_node.sh"
head -n1 "$MODULE_DIR/install_node.sh" | grep -q '^#!/bin/bash' || { red "Node module повреждён."; exit 1; }
chmod 755 "$MODULE_DIR/install_node.sh"

curl -fL --retry 3 --connect-timeout 10 --max-time 60 "$HELPER_URL" -o /usr/local/bin/kosmo-node
chmod 755 /usr/local/bin/kosmo-node

install -m 755 "$TMP_UPSTREAM" "$BASE_DIR/remnawave_reverse"
ln -sf "$BASE_DIR/remnawave_reverse" /usr/local/bin/remnawave_reverse
rm -f "$TMP_UPSTREAM"

cat > "$BASE_DIR/kosmo-build.info" <<INFO
KOSMO_VERSION=$KOSMO_VERSION
UPSTREAM_VERSION=${UPSTREAM_VER:-unknown}
UPSTREAM_SHA256=$UPSTREAM_SHA
INSTALLED_AT=$(date -u +%FT%TZ)
INFO

green "Bootstrap готов. Запускаю официальный интерфейс eGames с нашим Node-модулем."
yellow "Для отдельной ноды выбирай: Install Remnawave Components -> Install node only -> Nginx."
echo
exec "$BASE_DIR/remnawave_reverse"
