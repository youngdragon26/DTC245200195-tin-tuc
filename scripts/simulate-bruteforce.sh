#!/usr/bin/env bash
# MO PHONG tan cong do mat khau trang quan tri (chi dung tren he thong cua minh!)
# Cach dung: bash scripts/simulate-bruteforce.sh [URL] [username] [so_lan]
#   vi du:   bash scripts/simulate-bruteforce.sh https://localhost admin 30
# Ket qua mong doi: vai lan 401 (sai mat khau) -> 429 (Nginx chan vi vuot nguong)
URL="${1:-https://localhost}"; USERNAME="${2:-admin}"; N="${3:-30}"
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT
TOKEN=$(curl -sk -c "$JAR" -b "$JAR" "$URL/admin/login" | grep -o 'name="_csrf" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"$//')
[ -z "$TOKEN" ] && { echo "Khong lay duoc trang dang nhap tai $URL/admin/login"; exit 1; }
echo "Tan cong do mat khau: $N lan vao $URL/admin/login (user=$USERNAME)"
declare -A COUNT
for i in $(seq 1 "$N"); do
  CODE=$(curl -sk -o /dev/null -w '%{http_code}' -c "$JAR" -b "$JAR" -A "BruteForceSim/1.0" \
    --data-urlencode "username=$USERNAME" --data-urlencode "password=matkhau_sai_$i" \
    --data-urlencode "_csrf=$TOKEN" "$URL/admin/login")
  COUNT[$CODE]=$(( ${COUNT[$CODE]:-0} + 1 ))
  printf "Lan %2d -> HTTP %s\n" "$i" "$CODE"
  sleep 0.2
done
echo "---- Tong ket ----"
for c in "${!COUNT[@]}"; do echo "HTTP $c : ${COUNT[$c]} lan"; done
echo "Mo ngay (trong vong 5 phut): https://<IP>/alertmanager/  va  Grafana > Explore > Loki"
