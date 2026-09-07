#!/bin/bash
# Kosmo enhanced module: Node-only install via Nginx reverse-proxy/selfsteal.
# Compatible with eGamesAPI/remnawave-reverse-proxy helper functions.

_kosmo_msg(){ echo -e "${COLOR_GREEN:-}\n[KOSMO] $*${COLOR_RESET:-}"; }
_kosmo_warn(){ echo -e "${COLOR_YELLOW:-}[KOSMO] $*${COLOR_RESET:-}"; }
_kosmo_err(){ echo -e "${COLOR_RED:-}[KOSMO] $*${COLOR_RESET:-}"; }

_kosmo_validate_secret_key() {
    local secret="$1"
    python3 - "$secret" <<'PY'
import base64, json, sys
s=sys.argv[1].strip()
try:
    raw=base64.b64decode(s + '='*((4-len(s)%4)%4), validate=False)
    obj=json.loads(raw)
except Exception as e:
    print(f"invalid SECRET_KEY: {e}", file=sys.stderr); raise SystemExit(1)
need=("nodeCertPem","nodeKeyPem","caCertPem","jwtPublicKey")
miss=[k for k in need if not obj.get(k)]
if miss:
    print("SECRET_KEY missing: "+", ".join(miss), file=sys.stderr); raise SystemExit(1)
print("SECRET_KEY structure: OK")
PY
}

_kosmo_dns_preflight() {
    local domain="$1"
    local public_ip dns_ip
    public_ip=$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)
    dns_ip=$(getent ahostsv4 "$domain" 2>/dev/null | awk 'NR==1{print $1}')
    echo "[KOSMO] Server IPv4: ${public_ip:-unknown}"
    echo "[KOSMO] DNS IPv4:    ${dns_ip:-unknown}"
    if [[ -n "$public_ip" && -n "$dns_ip" && "$public_ip" != "$dns_ip" ]]; then
        _kosmo_err "DNS $domain -> $dns_ip, но сервер имеет $public_ip. Исправь A-запись и повтори установку."
        return 1
    fi
    return 0
}

_kosmo_resolve_latest_node_tag() {
    python3 - <<'PY'
import json, re, urllib.request
url='https://hub.docker.com/v2/repositories/remnawave/node/tags?page_size=100&ordering=last_updated'
try:
    with urllib.request.urlopen(url, timeout=8) as r: data=json.load(r)
    tags=[]
    for x in data.get('results',[]):
        n=x.get('name','')
        if re.fullmatch(r'\d+\.\d+\.\d+', n):
            tags.append(tuple(map(int,n.split('.')))+(n,))
    print(max(tags)[3] if tags else 'latest')
except Exception:
    print('latest')
PY
}

install_node_nginx() {
    load_selfsteal_templates_module

    if [ -d /opt/remnanode ] && [ -n "$(ls -A /opt/remnanode 2>/dev/null)" ]; then
        local backup_dir="/opt/remnanode.backup.$(date +%Y%m%d-%H%M%S)"
        _kosmo_warn "Найдена старая /opt/remnanode. Резервная копия: $backup_dir"
        cp -a /opt/remnanode "$backup_dir"
    fi
    mkdir -p /opt/remnanode && cd /opt/remnanode || exit 1

    reading "${LANG[SELFSTEAL]}" SELFSTEAL_DOMAIN
    check_domain "$SELFSTEAL_DOMAIN" true false
    local domain_check_result=$?
    if [ $domain_check_result -eq 2 ]; then
        echo -e "${COLOR_RED}${LANG[ABORT_MESSAGE]}${COLOR_RESET}"
        exit 1
    fi
    _kosmo_dns_preflight "$SELFSTEAL_DOMAIN" || exit 1

    while true; do
        reading "${LANG[PANEL_IP_PROMPT]}" PANEL_IP
        if python3 - "$PANEL_IP" <<'PY' >/dev/null 2>&1
import ipaddress,sys
ipaddress.ip_address(sys.argv[1])
PY
        then break
        else echo -e "${COLOR_RED}${LANG[IP_ERROR]}${COLOR_RESET}"
        fi
    done

    echo -n "$(question "${LANG[CERT_PROMPT]}")"
    CERTIFICATE=""
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            if [ -n "$CERTIFICATE" ]; then break; fi
        else
            CERTIFICATE="$CERTIFICATE$line\n"
        fi
    done
    local secret_one_line
    secret_one_line=$(echo -e "$CERTIFICATE" | tr -d '\r\n')
    _kosmo_validate_secret_key "$secret_one_line" || { _kosmo_err "SECRET_KEY не прошёл проверку."; exit 1; }

    echo -e "${COLOR_YELLOW}${LANG[CERT_CONFIRM]}${COLOR_RESET}"
    read confirm
    echo
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${COLOR_RED}${LANG[ABORT_MESSAGE]}${COLOR_RESET}"
        exit 1
    fi

    SELFSTEAL_BASE_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    unique_domains["$SELFSTEAL_BASE_DOMAIN"]=1

    cat > docker-compose.yml <<EOL
x-common: &common
  ulimits:
    nofile:
      soft: 1048576
      hard: 1048576
  restart: unless-stopped

x-logging: &logging
  logging:
    driver: json-file
    options:
      max-size: 20m
      max-file: 3
services:
  remnawave-nginx:
    image: nginx:stable
    pull_policy: always
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    <<: [*common, *logging]
    network_mode: host
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
EOL
}

installation_node() {
    echo -e "${COLOR_YELLOW}${LANG[INSTALLING_NODE]}${COLOR_RESET}"
    sleep 1

    apt-get update -y >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3 ca-certificates curl openssl iproute2 dnsutils >/dev/null 2>&1 || true

    declare -A unique_domains
    install_node_nginx

    declare -A domains_to_check
    domains_to_check["$SELFSTEAL_DOMAIN"]=1
    handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL" "/opt/remnanode"

    if [ -z "$CERT_METHOD" ]; then
        local base_domain=$(extract_domain "$SELFSTEAL_DOMAIN")
        if [ -d "/etc/letsencrypt/live/$base_domain" ] && is_wildcard_cert "$base_domain"; then
            CERT_METHOD="1"
        else
            CERT_METHOD="2"
        fi
    fi
    if [ "$CERT_METHOD" == "1" ]; then
        local base_domain=$(extract_domain "$SELFSTEAL_DOMAIN")
        NODE_CERT_DOMAIN="$base_domain"
    else
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    local NODE_TAG
    NODE_TAG=$(_kosmo_resolve_latest_node_tag)
    _kosmo_msg "Выбран Remnawave Node tag: $NODE_TAG (latest stable semver, fallback=latest)"

    cat >> /opt/remnanode/docker-compose.yml <<EOL
      - /dev/shm:/dev/shm:rw
      - /var/www/html:/var/www/html:ro
    command: sh -c 'rm -f /dev/shm/nginx.sock && exec nginx -g "daemon off;"'
  remnanode:
    image: remnawave/node:${NODE_TAG}
    pull_policy: always
    container_name: remnanode
    hostname: remnanode
    <<: [*common, *logging]
    network_mode: host
    cap_add:
      - NET_ADMIN
    environment:
      - NODE_PORT=2222
      - SECRET_KEY=$(echo -e "$CERTIFICATE" | tr -d '\r\n')
    volumes:
      - /dev/shm:/dev/shm:rw
EOL

    cat > /opt/remnanode/nginx.conf <<EOL
server_names_hash_bucket_size 64;
map \$http_upgrade \$connection_upgrade { default upgrade; "" close; }
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
ssl_session_tickets off;
server {
    server_name $SELFSTEAL_DOMAIN;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;
    ssl_certificate "/etc/nginx/ssl/$NODE_CERT_DOMAIN/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$NODE_CERT_DOMAIN/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$NODE_CERT_DOMAIN/fullchain.pem";
    root /var/www/html;
    index index.html;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
}
server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    ssl_reject_handshake on;
    return 444;
}
EOL

    ufw allow 22/tcp comment 'SSH' >/dev/null 2>&1 || true
    ufw allow 80/tcp comment 'HTTP/ACME' >/dev/null 2>&1 || true
    ufw allow 443/tcp comment 'VLESS/HTTPS' >/dev/null 2>&1 || true
    ufw allow from "$PANEL_IP" to any port 2222 proto tcp comment 'Remnawave Panel -> Node' >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true

    cd /opt/remnanode || exit 1
    docker compose config >/dev/null || { _kosmo_err "docker-compose.yml invalid"; exit 1; }

    _kosmo_msg "Принудительно скачиваю свежие Docker-образы (устраняет проблему старого cached Node 2.8.0)."
    docker compose pull
    docker compose up -d --remove-orphans

    randomhtml
    sleep 8

    echo
    _kosmo_msg "Проверка Node API"
    ss -lntp | grep ':2222' || _kosmo_warn "2222 пока не слушается"

    echo
    _kosmo_msg "Версии"
    docker logs remnanode 2>&1 | grep -aE 'SECRET_KEY OK|Remnawave Node v|XRay Core:' | tail -10 || true

    echo
    _kosmo_msg "Контейнеры"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

    echo
    _kosmo_warn "ВАЖНО: порт 443 у rw-core появляется только после успешного Panel -> Node подключения и передачи Xray-конфига. Его отсутствие сразу после установки не считаем ошибкой Node."
    _kosmo_warn "Если Node остаётся Offline: kosmo-node doctor"
    _kosmo_warn "Для Reality ключей: kosmo-node keys"

    printf "${COLOR_YELLOW}${LANG[NODE_CHECK]}${COLOR_RESET}\n" "$SELFSTEAL_DOMAIN"
    local max_attempts=5 attempt=1 delay=10
    while [ $attempt -le $max_attempts ]; do
        printf "${COLOR_YELLOW}${LANG[NODE_ATTEMPT]}${COLOR_RESET}\n" "$attempt" "$max_attempts"
        if curl -ksS --fail --max-time 10 "https://$SELFSTEAL_DOMAIN" | grep -qiE '<html|<!doctype'; then
            echo -e "${COLOR_GREEN}${LANG[NODE_LAUNCHED]}${COLOR_RESET}"
            break
        fi
        [ $attempt -eq $max_attempts ] && _kosmo_warn "SelfSteal HTTPS пока не отвечает. Node API может при этом быть исправен; см. kosmo-node doctor."
        sleep $delay
        ((attempt++))
    done
}
