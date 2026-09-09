#!/usr/bin/env bash
set -Eeuo pipefail

KOSMO_VERSION="2.0.0"
NODE_DIR="/opt/remnanode"
PROFILE_DIR="$NODE_DIR/generated-profiles"
UPSTREAM_URL="https://raw.githubusercontent.com/eGamesAPI/remnawave-reverse-proxy/refs/heads/main/install_remnawave.sh"
PANEL_IP_PROTECTED="147.45.219.190"

C_RESET='\033[0m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_CYAN='\033[1;36m'; C_WHITE='\033[1;37m'
msg(){ echo -e "${C_CYAN}$*${C_RESET}"; }
ok(){ echo -e "${C_GREEN}$*${C_RESET}"; }
warn(){ echo -e "${C_YELLOW}$*${C_RESET}"; }
err(){ echo -e "${C_RED}$*${C_RESET}"; }
hr(){ printf '%*s\n' "${COLUMNS:-76}" '' | tr ' ' '-'; }

trap 'err "Ошибка на строке $LINENO. Операция остановлена."' ERR

need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { err "Запусти от root."; exit 1; }; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || return 1; }

ensure_base_packages(){
  local pkgs=()
  need_cmd curl || pkgs+=(curl)
  need_cmd python3 || pkgs+=(python3)
  need_cmd openssl || pkgs+=(openssl)
  need_cmd ss || pkgs+=(iproute2)
  if ((${#pkgs[@]})); then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates "${pkgs[@]}"
  fi
}

public_ipv4(){ curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true; }

panel_guard(){
  local ip
  ip="$(public_ipv4)"
  if [[ "$ip" == "$PANEL_IP_PROTECTED" ]]; then
    err "ЗАЩИТА: этот IP совпадает с сервером панели ($PANEL_IP_PROTECTED). Скрипт отказался выполнять изменяющую операцию."
    return 1
  fi
  if need_cmd docker; then
    local names
    names="$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)"
    if grep -Eq '(^|\n)(remnawave|remnawave-backend|remnawave-db|remnawave-redis|remnawave-subscription-page)($|\n)' <<<"$names"; then
      err "ЗАЩИТА: обнаружены контейнеры панели Remnawave. Изменяющая операция запрещена."
      return 1
    fi
  fi
}

need_node(){
  [[ -f "$NODE_DIR/docker-compose.yml" ]] || { err "Не найден $NODE_DIR/docker-compose.yml. Сначала установи Node через пункт 1."; return 1; }
  need_cmd docker || { err "Docker не найден."; return 1; }
  docker inspect remnanode >/dev/null 2>&1 || { err "Контейнер remnanode не найден."; return 1; }
}

node_domain(){
  local d=''
  if [[ -f "$NODE_DIR/nginx.conf" ]]; then
    d="$(sed -nE 's/^[[:space:]]*server_name[[:space:]]+([^;_]+);.*/\1/p' "$NODE_DIR/nginx.conf" | head -n1 | xargs || true)"
  fi
  if [[ -z "$d" && -f "$NODE_DIR/Caddyfile" ]]; then
    d="$(grep -Eo 'https://[^ {]+' "$NODE_DIR/Caddyfile" | head -n1 | sed 's#https://##' || true)"
  fi
  printf '%s' "$d"
}

xray_bin(){
  need_node >/dev/null
  local p
  for p in /usr/local/bin/xray /usr/bin/xray /opt/xray/xray; do
    if docker exec remnanode test -x "$p" >/dev/null 2>&1; then printf '%s' "$p"; return 0; fi
  done
  err "Xray binary внутри remnanode не найден."; return 1
}

reality_values(){
  local xb out priv pub sid
  xb="$(xray_bin)"
  out="$(docker exec remnanode "$xb" x25519 2>&1)"
  priv="$(awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}' <<<"$out")"
  pub="$(awk -F': *' 'tolower($1) ~ /(public|password)/ {print $2; exit}' <<<"$out")"
  [[ -n "$priv" && -n "$pub" ]] || { printf '%s\n' "$out" >&2; err "Не удалось разобрать вывод x25519." >&2; return 1; }
  sid="$(openssl rand -hex 8)"
  printf '%s\n%s\n%s\n' "$priv" "$pub" "$sid"
}

validate_json(){
  python3 -m json.tool "$1" >/dev/null
}

save_host_txt(){
  local file="$1"; shift
  printf '%s\n' "$@" > "$file"
}

profile_xhttp(){
  panel_guard; need_node; ensure_base_packages
  local tag="${1:-XHTTP-REALITY}" port="${2:-443}" sni="${3:-}" path="${4:-}" domain vals priv pub sid out host
  domain="$(node_domain)"; [[ -n "$domain" ]] || { err "Не удалось определить self-steal домен из nginx.conf/Caddyfile."; return 1; }
  sni="${sni:-$domain}"
  path="${path:-/$(openssl rand -hex 12)}"; [[ "$path" == /* ]] || path="/$path"
  vals="$(reality_values)"; priv="$(sed -n '1p' <<<"$vals")"; pub="$(sed -n '2p' <<<"$vals")"; sid="$(sed -n '3p' <<<"$vals")"
  mkdir -p "$PROFILE_DIR"; out="$PROFILE_DIR/xhttp-reality.json"; host="$PROFILE_DIR/xhttp-host.txt"
  python3 - "$out" "$tag" "$port" "$domain" "$sni" "$path" "$priv" "$sid" <<'PY'
import json,sys
f,tag,port,domain,sni,path,priv,sid=sys.argv[1:]
obj={
 "log":{"loglevel":"warning"},
 "dns":{"servers":["1.1.1.1","8.8.8.8"],"queryStrategy":"UseIPv4"},
 "inbounds":[{
   "tag":tag,"listen":"0.0.0.0","port":int(port),"protocol":"vless",
   "settings":{"clients":[],"decryption":"none"},
   "sniffing":{"enabled":True,"routeOnly":True,"destOverride":["http","tls","quic"]},
   "streamSettings":{
     "network":"xhttp","security":"reality",
     "xhttpSettings":{"host":domain,"mode":"auto","path":path},
     "realitySettings":{"target":"/dev/shm/nginx.sock","show":False,"xver":1,"shortIds":[sid],"privateKey":priv,"serverNames":[sni],"maxTimeDiff":0,"minClientVer":"1.8.0","maxClientVer":""}
   }
 }],
 "outbounds":[{"tag":"DIRECT","protocol":"freedom","settings":{"domainStrategy":"UseIPv4"}},{"tag":"BLOCK","protocol":"blackhole"}],
 "routing":{"rules":[],"domainStrategy":"IPIfNonMatch"}
}
open(f,'w').write(json.dumps(obj,ensure_ascii=False,indent=2)+"\n")
PY
  validate_json "$out"
  save_host_txt "$host" \
    "Address: $domain" "Port: $port" "Protocol: VLESS" "Network: xhttp" "Security: reality" \
    "SNI: $sni" "Fingerprint: qq" "Path: $path" "Mode: auto" "Flow: <empty>" \
    "PublicKey/Password: $pub" "ShortID: $sid"
  if need_cmd ufw; then ufw allow "$port"/tcp comment 'Kosmo XHTTP Reality' >/dev/null 2>&1 || true; ufw reload >/dev/null 2>&1 || true; fi
  ok "XHTTP профиль создан: $out"
  cat "$host"
}

profile_raw(){
  panel_guard; need_node; ensure_base_packages
  local tag="${1:-RAW-REALITY}" port="${2:-443}" sni="${3:-max.ru}" domain vals priv pub sid out host
  domain="$(node_domain)"; [[ -n "$domain" ]] || { err "Не удалось определить домен Node."; return 1; }
  vals="$(reality_values)"; priv="$(sed -n '1p' <<<"$vals")"; pub="$(sed -n '2p' <<<"$vals")"; sid="$(sed -n '3p' <<<"$vals")"
  mkdir -p "$PROFILE_DIR"; out="$PROFILE_DIR/raw-reality.json"; host="$PROFILE_DIR/raw-host.txt"
  python3 - "$out" "$tag" "$port" "$sni" "$priv" "$sid" <<'PY'
import json,sys
f,tag,port,sni,priv,sid=sys.argv[1:]
obj={
 "log":{"loglevel":"warning"},
 "dns":{"servers":["1.1.1.1","8.8.8.8"],"queryStrategy":"UseIPv4"},
 "inbounds":[{
   "tag":tag,"listen":"0.0.0.0","port":int(port),"protocol":"vless",
   "settings":{"clients":[],"decryption":"none"},
   "sniffing":{"enabled":True,"routeOnly":True,"destOverride":["http","tls","quic"]},
   "streamSettings":{
     "network":"raw","security":"reality",
     "realitySettings":{"target":sni+":443","show":False,"xver":0,"shortIds":[sid],"privateKey":priv,"serverNames":[sni],"maxTimeDiff":0,"minClientVer":"1.8.0","maxClientVer":""}
   }
 }],
 "outbounds":[{"tag":"DIRECT","protocol":"freedom","settings":{"domainStrategy":"UseIPv4"}},{"tag":"BLOCK","protocol":"blackhole"}],
 "routing":{"rules":[],"domainStrategy":"IPIfNonMatch"}
}
open(f,'w').write(json.dumps(obj,ensure_ascii=False,indent=2)+"\n")
PY
  validate_json "$out"
  save_host_txt "$host" \
    "Address: $domain" "Port: $port" "Protocol: VLESS" "Network: raw" "Security: reality" \
    "SNI: $sni" "Fingerprint: qq" "Flow: xtls-rprx-vision" "PublicKey/Password: $pub" "ShortID: $sid"
  if need_cmd ufw; then ufw allow "$port"/tcp comment 'Kosmo RAW Reality' >/dev/null 2>&1 || true; ufw reload >/dev/null 2>&1 || true; fi
  ok "RAW профиль создан: $out"
  cat "$host"
}

profile_both(){
  panel_guard; need_node
  profile_xhttp "KOSMO-XHTTP" 443
  profile_raw "KOSMO-RAW" 8444 max.ru
  local out="$PROFILE_DIR/xhttp-raw-reality.json"
  python3 - "$PROFILE_DIR/xhttp-reality.json" "$PROFILE_DIR/raw-reality.json" "$out" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); r=json.load(open(sys.argv[2])); x['inbounds'].extend(r['inbounds']); open(sys.argv[3],'w').write(json.dumps(x,ensure_ascii=False,indent=2)+"\n")
PY
  validate_json "$out"
  ok "Комбинированный профиль создан: $out"
  warn "Используй именно xhttp-raw-reality.json в Remnawave, а два отдельных файла оставлены как справочные."
}

install_official_node(){
  panel_guard; ensure_base_packages
  local tmp ver sha
  tmp="$(mktemp)"
  curl -fL --retry 3 --connect-timeout 10 --max-time 60 "$UPSTREAM_URL" -o "$tmp"
  head -n1 "$tmp" | grep -q '^#!/bin/bash' || { rm -f "$tmp"; err "Получен некорректный upstream installer."; return 1; }
  ver="$(grep -m1 '^SCRIPT_VERSION=' "$tmp" | cut -d'"' -f2 || true)"
  sha="$(sha256sum "$tmp" | awk '{print $1}')"
  ok "Официальный eGames installer: ${ver:-unknown}"
  msg "SHA256: $sha"
  warn "Откроется ОФИЦИАЛЬНОЕ меню eGames. Для ноды выбирай только: Install Remnawave Components -> Install node only -> Nginx."
  warn "Наш скрипт не патчит и не подменяет код eGames и не меняет сервер панели."
  read -rp "Нажми Enter для продолжения..." _
  bash "$tmp"
  rm -f "$tmp"
}

status_node(){
  need_node
  hr; msg "КОНТЕЙНЕРЫ"; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
  hr; msg "ВЕРСИИ"; docker logs remnanode 2>&1 | grep -aE 'SECRET_KEY OK|Remnawave Node v|XRay Core:' | tail -20 || true
  hr; msg "ПОРТЫ"; ss -lntp | grep -E '(:2222|:443|:8444|:80)' || true
  hr; msg "ДОМЕН"; echo "$(node_domain)"
  hr; msg "UFW"; if need_cmd ufw; then ufw status; else echo "ufw не установлен"; fi
}

doctor_node(){
  need_node
  hr; msg "HOST"; echo "Public IPv4: $(public_ipv4)"; . /etc/os-release; echo "OS: ${PRETTY_NAME:-unknown}"; uname -a
  hr; msg "COMPOSE"; (cd "$NODE_DIR" && docker compose config >/dev/null && ok "docker compose config: OK" || err "docker compose config: ERROR")
  grep -nE 'image:|NODE_PORT=' "$NODE_DIR/docker-compose.yml" || true
  hr; msg "NODE ENV"; docker inspect remnanode --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E 'NODE_PORT=|SECRET_KEY=' | sed -E 's#(SECRET_KEY=).*#\1***HIDDEN***#' || true
  hr; msg "VERSIONS / SECRET"; docker logs remnanode 2>&1 | grep -aE 'SECRET_KEY|Remnawave Node v|XRay Core:' | tail -30 || true
  hr; msg "PORTS"; ss -lntp | grep -E '(:2222|:443|:8444|:80)' || true
  hr; msg "ROUTING"; ip route; ip rule
  hr; msg "RECENT LOGS"; docker logs --tail=80 remnanode 2>&1 || true
  warn "Норма: 2222=rw-node. 443/8444=rw-core появляются только после передачи соответствующего Xray Config Profile из панели."
}

restart_node(){ panel_guard; need_node; (cd "$NODE_DIR" && docker compose restart remnanode); sleep 8; status_node; }

update_node(){
  panel_guard; need_node
  local b="$NODE_DIR/docker-compose.yml.backup-$(date +%F-%H%M%S)"
  cp -a "$NODE_DIR/docker-compose.yml" "$b"
  ok "Backup compose: $b"
  (cd "$NODE_DIR" && docker compose config >/dev/null && docker compose pull remnanode && docker compose up -d --no-deps --force-recreate remnanode)
  sleep 10; status_node
}

backup_node(){
  need_node
  local f="/root/remnanode-backup-$(date +%F-%H%M%S).tar.gz"
  tar -C /opt -czf "$f" remnanode
  ok "Backup создан: $f"
}

logs_node(){ need_node; docker logs --tail=150 -f remnanode; }
keys_only(){ need_node; local vals; vals="$(reality_values)"; echo "PrivateKey: $(sed -n '1p' <<<"$vals")"; echo "PublicKey/Password: $(sed -n '2p' <<<"$vals")"; echo "ShortID: $(sed -n '3p' <<<"$vals")"; }

show_sources(){
  cat <<'EOF'
Основа и сверка синтаксиса:
- eGamesAPI/remnawave-reverse-proxy — официальный/community installer Node + self-steal
- remnawave/templates — актуальный VLESS RAW/TCP REALITY шаблон Remnawave
- XTLS/Xray-docs-next — REALITY, RAW, XHTTP, target/dest
- XTLS/Xray-examples — VLESS TCP/RAW REALITY + Vision
- XTLS/Xray-core discussions #4118 — XHTTP + REALITY примеры
- TrulyInfinite/remnawave — Remnawave XHTTP + REALITY self-steal через /dev/shm/nginx.sock
EOF
}

menu(){
  while true; do
    clear || true
    echo -e "${C_WHITE}Kosmo Remnawave Node Manager v$KOSMO_VERSION${C_RESET}"
    echo "Один файл. Сервер панели защищён от изменяющих операций."
    hr
    echo " 1) Установить / переустановить Node через официальный eGames"
    echo " 2) Создать Config Profile: XHTTP + REALITY"
    echo " 3) Создать Config Profile: RAW + REALITY + Vision"
    echo " 4) Создать Config Profile: XHTTP + RAW"
    echo " 5) Статус Node"
    echo " 6) Полная диагностика"
    echo " 7) Перезапустить только remnanode"
    echo " 8) Безопасно обновить образ remnanode"
    echo " 9) Логи remnanode"
    echo "10) Сгенерировать Reality keys + ShortID"
    echo "11) Backup /opt/remnanode"
    echo "12) Показать источники/референсы"
    echo " 0) Выход"
    hr
    read -rp "Выбери пункт: " ch
    case "$ch" in
      1) install_official_node ;;
      2) profile_xhttp ;;
      3) profile_raw ;;
      4) profile_both ;;
      5) status_node ;;
      6) doctor_node ;;
      7) restart_node ;;
      8) update_node ;;
      9) logs_node ;;
      10) keys_only ;;
      11) backup_node ;;
      12) show_sources ;;
      0) exit 0 ;;
      *) warn "Неверный пункт." ;;
    esac
    echo; read -rp "Enter — вернуться в меню..." _ || true
  done
}

need_root
ensure_base_packages
menu
