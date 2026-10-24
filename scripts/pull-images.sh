#!/usr/bin/env bash
# Tai image TUAN TU va tu thu lai khi loi mang (vd: "TLS handshake timeout" do mang NAT).
# Chi tai cac dich vu thuoc COMPOSE_FILE hien tai trong .env
cd "$(dirname "$0")/.."
for s in $(docker compose config --services); do
  [ "$s" = "webapp" ] && continue          # webapp duoc build tu ma nguon, khong can pull
  n=0
  until docker compose pull "$s"; do
    n=$((n+1)); [ $n -ge 10 ] && { echo "!! Khong tai duoc $s sau 10 lan"; exit 1; }
    echo ">> Loi mang, thu lai $s ($n/10)..."; sleep 3
  done
done
echo ">> Da tai xong image. Chay: docker compose up -d --build"
