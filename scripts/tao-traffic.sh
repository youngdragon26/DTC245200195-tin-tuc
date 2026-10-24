#!/usr/bin/env bash
# Tao luu luong gia lap (ca request thanh cong lan request loi)
# de co du lieu tren Grafana va de demo cac cau LogQL.
# Cach dung: bash scripts/tao-traffic.sh [IP] [so_vong]
IP="${1:-127.0.0.1}"; N="${2:-30}"
URL="https://${IP}"
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT
TOKEN=$(curl -sk -c "$JAR" -b "$JAR" "$URL/admin/login" | grep -o 'name="_csrf" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"$//')
for i in $(seq 1 "$N"); do
  curl -sk -o /dev/null "$URL/"
  curl -sk -o /dev/null "$URL/danh-muc/cong-nghe"
  curl -sk -o /dev/null "$URL/bai-viet/docker-xu-huong-container"
  curl -sk -o /dev/null "$URL/?q=docker"
  curl -sk -o /dev/null "$URL/trang-khong-ton-tai"                      # 404
  [ $((i % 5)) -eq 0 ] && curl -sk -o /dev/null "$URL/demo/loi"          # 500
  [ $((i % 10)) -eq 0 ] && curl -sk -o /dev/null -b "$JAR" -c "$JAR" \
      --data-urlencode "_csrf=$TOKEN" -d "username=khach&password=sai" "$URL/admin/login"  # dang nhap sai
  sleep 0.5
done
echo "Da gui xong ${N} vong request toi ${URL}"
