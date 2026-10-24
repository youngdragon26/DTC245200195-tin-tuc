#!/usr/bin/env bash
# MO PHONG gui du lieu tan cong SQL Injection / XSS (chi dung tren he thong cua minh!)
# Website dung truy van tham so hoa + escape HTML nen KHONG bi khai thac,
# nhung moi request deu bi ghi log SUSPICIOUS_INPUT -> canh bao SuspiciousInputDetected.
URL="${1:-https://localhost}"
PAYLOADS=(
  "' OR 1=1 -- "
  "' UNION SELECT username,password_hash FROM users -- "
  "1; DROP TABLE articles"
  "<script>alert('xss')</script>"
  "\" onerror=alert(1) x=\""
)
for p in "${PAYLOADS[@]}"; do
  CODE=$(curl -sk -o /tmp/sqli_resp.html -w '%{http_code}' -A "SQLiSim/1.0" -G --data-urlencode "q=$p" "$URL/")
  LEAK=$(grep -cE '\$2[aby]\$[0-9]{2}\$' /tmp/sqli_resp.html)  # tim chuoi bam bcrypt bi lo
  printf "HTTP %s | lo du lieu: %s | %s\n" "$CODE" "$([ "$LEAK" = 0 ] && echo KHONG || echo CO)" "$p"
done
rm -f /tmp/sqli_resp.html
echo "Xem canh bao: https://<IP>/alertmanager/  (SuspiciousInputDetected)"
