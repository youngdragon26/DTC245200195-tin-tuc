#!/usr/bin/env bash
# Kiem tra moi truong truoc khi chay. Moi dong [!!] kem lenh goi y de sua.
cd "$(dirname "$0")/.."
ok()  { printf "  [OK] %s\n" "$1"; }
bad() { printf "  [!!] %s\n       -> %s\n" "$1" "$2"; FAIL=1; }
FAIL=0
echo "== Kiem tra moi truong Website Tin tuc =="

command -v docker >/dev/null && ok "Docker: $(docker --version | cut -d, -f1)" \
  || bad "Chua cai Docker" "curl -fsSL https://get.docker.com | sudo sh"
docker compose version >/dev/null 2>&1 && ok "Docker Compose: $(docker compose version --short)" \
  || bad "Chua co Docker Compose plugin" "sudo apt install -y docker-compose-plugin"
docker info >/dev/null 2>&1 && ok "Dung docker khong can sudo" \
  || bad "User chua co quyen docker" "sudo usermod -aG docker \$USER  (roi dang xuat, dang nhap lai)"

MEM=$(awk '/MemTotal/{printf "%d", $2/1024/1024+0.5}' /proc/meminfo)
[ "${MEM:-0}" -ge 4 ] && ok "RAM: ${MEM} GB" || bad "RAM chi ${MEM} GB (nen >= 4 GB)" "Tat may ao, VM > Settings > Memory: 4096-6144 MB"
DISK=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
[ "${DISK:-0}" -ge 10 ] && ok "O dia con trong: ${DISK} GB" || bad "O dia chi con ${DISK} GB (can >= 10 GB)" "docker system prune -a   hoac tang dung luong o ao"

for f in .env nginx/certs/selfsigned.crt nginx/certs/selfsigned.key nginx/auth/.htpasswd; do
  [ -f "$f" ] && ok "Co file $f" || bad "Thieu file $f" "bash scripts/setup.sh <IP_may_ao>"
done
if [ -f .env ]; then
  [ "$(stat -c %a .env)" = "600" ] && ok ".env chi chu so huu doc duoc (600)" || bad ".env dang de quyen $(stat -c %a .env)" "chmod 600 .env"
  grep -q "^COMPOSE_FILE=" .env && ok "COMPOSE_FILE = $(grep ^COMPOSE_FILE= .env | cut -d= -f2)" || bad "Thieu COMPOSE_FILE trong .env" "Xem .env.example"
  IPENV=$(grep ^SERVER_IP= .env | cut -d= -f2)
  hostname -I | grep -qw "$IPENV" && ok "SERVER_IP=$IPENV khop IP may ao" \
    || bad "SERVER_IP=$IPENV khong khop IP hien tai ($(hostname -I | awk '{print $1}'))" "sua SERVER_IP trong .env, xoa nginx/certs/selfsigned.* roi chay lai setup.sh"
fi
if grep -lq $'\r' scripts/*.sh db/init/*.sh 2>/dev/null; then
  bad "Co file .sh bi xuong dong kieu Windows (CRLF)" "sed -i 's/\\r\$//' scripts/*.sh db/init/*.sh"
else ok "Cac file .sh dung dinh dang Linux (LF)"; fi

for port in 80 443; do
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"; then
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q tintuc-nginx && ok "Cong $port dang do tintuc-nginx dung" \
      || bad "Cong $port dang bi chuong trinh khac chiem" "sudo ss -ltnp | grep :$port  (tat chuong trinh do, vd: sudo systemctl stop apache2)"
  else ok "Cong $port dang trong"; fi
done
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && ok "Dang o trong repo git ($(git remote get-url origin 2>/dev/null || echo 'chua co remote'))" \
  || bad "Thu muc nay chua phai repo git" "git init -b main && git remote add origin <link-repo>"

echo
[ $FAIL -eq 0 ] && echo "Tat ca deu [OK]. Chay: docker compose up -d --build" || echo "Hay sua cac dong [!!] o tren roi chay lai script nay."
