#!/bin/bash
# HARDENING - Han che quyen DB (nguyen tac least privilege):
#  - User cua ung dung chi co quyen SELECT/INSERT/UPDATE/DELETE tren DB tintuc
#    (khong DROP, khong ALTER, khong truy cap DB khac).
#  - User cua mysqld-exporter chi co quyen doc thong tin giam sat.
# Script chay tu dong 1 lan khi MySQL khoi tao lan dau, mat khau lay tu file .env
set -e
mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE USER IF NOT EXISTS '${APP_DB_USER}'@'%' IDENTIFIED BY '${APP_DB_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON tintuc.* TO '${APP_DB_USER}'@'%';

CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY '${EXPORTER_DB_PASSWORD}' WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

FLUSH PRIVILEGES;
SQL
echo ">> Da tao user ung dung va user exporter voi quyen han che"
