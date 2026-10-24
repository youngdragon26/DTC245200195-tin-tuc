#!/usr/bin/env bash
# =====================================================================
# Chuan bi moi truong lan dau:
#   1) Tao file .env voi mat khau MANH ngau nhien
#   2) Tao chung chi HTTPS tu ky cho Nginx
#   3) Tao file .htpasswd (Basic Auth bao ve phpMyAdmin, Prometheus, Alertmanager)
# Cach dung:  bash scripts/setup.sh <IP_may_ao>
#   vi du:    bash scripts/setup.sh 192.168.105.130
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

# Bo ky tu xuong dong kieu Windows (CRLF) neu file bi sua/giai nen tren Windows
sed -i 's/\r$//' scripts/*.sh db/init/*.sh .env.example 2>/dev/null || true

IP="${1:-$(hostname -I | awk '{print $1}')}"
rand() { local s; s="$(openssl rand -base64 64 | tr -dc 'A-Za-z0-9')"; echo "${s:0:${1:-24}}"; }

# ---------- 1) File .env ----------
if [ -f .env ]; then
  echo ">> Da co file .env, giu nguyen (xoa .env neu muon tao lai TRUOC khi chay lan dau)."
else
  cp .env.example .env
  sed -i "s|^SERVER_IP=.*|SERVER_IP=${IP}|" .env
  for key in MYSQL_ROOT_PASSWORD APP_DB_PASSWORD EXPORTER_DB_PASSWORD ADMIN_PASSWORD GRAFANA_ADMIN_PASSWORD; do
    sed -i "s|^${key}=.*|${key}=$(rand 24)|" .env
  done
  sed -i "s|^SESSION_SECRET=.*|SESSION_SECRET=$(openssl rand -hex 32)|" .env
  chmod 600 .env                      # chi chu so huu doc duoc file mat khau
  echo ">> Da tao .env voi mat khau ngau nhien."
fi

# ---------- 2) Chung chi HTTPS tu ky ----------
if [ ! -f nginx/certs/selfsigned.crt ]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout nginx/certs/selfsigned.key -out nginx/certs/selfsigned.crt \
    -subj "/C=VN/ST=Thai Nguyen/O=ICTU/CN=${IP}" \
    -addext "subjectAltName=IP:${IP},DNS:localhost" 2>/dev/null
  echo ">> Da tao chung chi tu ky cho IP ${IP}"
fi
# Nginx chay voi uid 101 nen phai doc duoc file key
if [ -O nginx/certs/selfsigned.key ]; then chmod 644 nginx/certs/selfsigned.key; fi

# ---------- 3) Basic Auth cho trang quan tri ----------
if [ ! -f nginx/auth/.htpasswd ]; then
  BA_PASS="$(rand 16)"
  printf "quantri:%s\n" "$(openssl passwd -apr1 "${BA_PASS}")" > nginx/auth/.htpasswd
  chmod 644 nginx/auth/.htpasswd
  echo "# Basic Auth (phpMyAdmin/Prometheus/Alertmanager): quantri / ${BA_PASS}" >> .env
fi

# ---------- In bang tai khoan ----------
get() { grep -E "^$1=" .env | head -1 | cut -d= -f2-; }
BA_LINE="$(grep -E '^# Basic Auth' .env | sed 's/.*: //')"
cat <<TXT

==================== BANG TAI KHOAN (dung ghi lai, KHONG chup anh) ====================
 Website quan tri   https://${IP}/admin             $(get ADMIN_USERNAME) / $(get ADMIN_PASSWORD)
 Basic Auth         phpMyAdmin, Prometheus, Alertmanager   ${BA_LINE}
 phpMyAdmin (MySQL) https://${IP}/phpmyadmin/       root / $(get MYSQL_ROOT_PASSWORD)
 Grafana            https://${IP}/grafana/          $(get GRAFANA_ADMIN_USER) / $(get GRAFANA_ADMIN_PASSWORD)
 Prometheus         https://${IP}/prometheus/
 Alertmanager       https://${IP}/alertmanager/
==========================================================================================
Xem lai bat cu luc nao:  cat .env
Buoc tiep:  bash scripts/check-env.sh   roi   docker compose up -d --build
TXT
