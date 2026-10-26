# Đề 19 – Website Tin tức / Cổng thông tin

**Môn:** Triển khai và Quản trị Hệ thống Phần mềm – ICTU 2026
**Sinh viên:** Thân Tuấn Vũ – MSSV: DTC245200195 – Lớp CNTT K23G

Website tin tức (trang chủ, danh mục, chi tiết bài viết, tìm kiếm, trang quản trị đăng/sửa/xóa bài) được triển khai hoàn toàn bằng **Docker Compose**, kèm giám sát, log tập trung, cảnh báo an ninh và hardening.

| Thành phần | Công nghệ | Vai trò |
|---|---|---|
| Ứng dụng web | Node.js 22 + Express + EJS | Website tin tức + trang quản trị, log JSON, `/metrics` |
| Cơ sở dữ liệu | MySQL 8.4 | Bài viết, danh mục, người dùng (mạng nội bộ, không mở cổng) |
| Quản lý DB | phpMyAdmin 5.2 | Truy cập qua Nginx, có thêm lớp Basic Auth |
| Reverse proxy | Nginx 1.27 (unprivileged) | HTTPS tự ký, security headers, CSP, rate limit |
| Giám sát | Prometheus + Grafana + cAdvisor + node/nginx/mysqld exporter | Metrics container, web server, database |
| Cảnh báo | Alertmanager | Nhận cảnh báo từ Prometheus (metrics) và Loki Ruler (log) |
| Log tập trung | Loki + Promtail | Gom log mọi container, truy vấn LogQL, luật cảnh báo an ninh |

## Sơ đồ kiến trúc

```
                     Trình duyệt (Windows)
                              │  HTTPS :443 (HTTP :80 → chuyển sang HTTPS)
                     ┌────────▼────────┐
                     │      Nginx      │  ← chỉ duy nhất Nginx mở cổng ra ngoài
                     └─┬───┬───┬───┬──┬┘
        mạng frontend  │   │   │   │  │
           ┌───────────▼┐ ┌▼───▼──┐│ ┌▼────────────┐
           │   webapp   │ │phpMy- ││ │ Prometheus  │──► Alertmanager ◄──┐
           └─────┬──────┘ │Admin  ││ └──────▲──────┘                    │
   mạng backend  │        └──┬────┘│ ┌──────┴──────┐                    │
   (internal) ┌──▼───────────▼┐ ┌──▼─┤   Grafana   │                    │
              │     MySQL     │ │    └──────┬──────┘                    │
              └───────▲───────┘ │  mạng monitoring (internal)           │
                      │         │  ┌──────────────────────────────┐     │
              mysqld-exporter   │  │ cAdvisor, node-exporter,     │     │
                                │  │ nginx-exporter               │     │
                                │  └──────────────────────────────┘     │
                           ┌────▼─┐    ┌──────────┐                     │
                           │ Loki │◄───┤ Promtail │◄── log mọi container│
                           └──┬───┘    └──────────┘                     │
                              └── Loki Ruler (luật LogQL) ───────────────┘
```

## Cách chạy

```bash
# 1. Lấy mã nguồn
git clone https://github.com/youngdragon26/DTC245200195-tin-tuc.git
cd DTC245200195-tin-tuc

# 2. Tạo .env (mật khẩu mạnh ngẫu nhiên), chứng chỉ HTTPS tự ký, Basic Auth
bash scripts/setup.sh 192.168.105.130 

# 3. Kiểm tra môi trường (mọi dòng phải [OK])
bash scripts/check-env.sh

# 4. Tải image (tự thử lại khi mạng chập chờn) và khởi động
bash scripts/pull-images.sh
docker compose up -d --build
docker compose ps                         # 13 container
```

## Địa chỉ truy cập

| Dịch vụ | URL | Tài khoản |
|---|---|---|
| Website | `https://<IP>/` | – |
| Trang quản trị | `https://<IP>/admin` | `ADMIN_USERNAME` / `ADMIN_PASSWORD` trong `.env` |
| phpMyAdmin | `https://<IP>/phpmyadmin/` | Basic Auth `quantri`, sau đó `root` / `MYSQL_ROOT_PASSWORD` |
| Grafana | `https://<IP>/grafana/` | `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` |
| Prometheus | `https://<IP>/prometheus/` | Basic Auth `quantri` |
| Alertmanager | `https://<IP>/alertmanager/` | Basic Auth `quantri` |

`setup.sh` in bảng tài khoản; xem lại bằng `cat .env`. Trình duyệt sẽ cảnh báo chứng chỉ **tự ký**: chọn *Nâng cao → Tiếp tục*.

## Cảnh báo

| Cảnh báo | Nguồn | Điều kiện | Mức |
|---|---|---|---|
| ServiceDown | Prometheus | Một target không phản hồi 1 phút | critical |
| MySQLDown | Prometheus | `mysql_up == 0` trong 30 giây | critical |
| WebappHighErrorRate | Prometheus | Lỗi 5xx > 0,1 request/giây trong 1 phút | warning |
| ContainerHighMemory | Prometheus | Container dùng > 700 MB RAM trong 2 phút | warning |
| HostLowDisk | Prometheus | Ổ đĩa máy ảo còn < 10% | warning |
| BruteForceLoginDetected | Loki Ruler | Một IP đăng nhập sai/bị khóa ≥ 5 lần trong 5 phút | critical |
| RateLimitTriggered | Loki Ruler | Nginx trả 429 cho một IP > 5 lần trong 5 phút | warning |
| SuspiciousInputDetected | Loki Ruler | Dữ liệu chứa mẫu SQL Injection / XSS | warning |
| WebappErrorLogsSpike | Loki Ruler | > 5 dòng log error trong 2 phút | warning |

## Truy vấn LogQL (Grafana → Explore → Loki)

```logql
{job="nginx"}                                                      # toàn bộ log Nginx
{job="nginx"} | json | status >= 500                               # request lỗi 5xx
{job="webapp", level=~"error|warn"} | json                         # lỗi / cảnh báo của ứng dụng
sum by (client_ip) (count_over_time({job="webapp", event="LOGIN_FAILED"} | json [10m]))   # IP đăng nhập sai nhiều nhất
{job="webapp", event="SUSPICIOUS_INPUT"} | json                    # dữ liệu tấn công SQLi/XSS
sum by (job) (count_over_time({job=~".+"}[5m]))                    # số dòng log mỗi dịch vụ
```

## Mô phỏng sự cố an ninh

```bash
bash scripts/simulate-bruteforce.sh https://localhost admin 30   # dò mật khẩu: 401 → 429
bash scripts/simulate-sqli.sh https://localhost                  # SQLi/XSS: không lộ dữ liệu, có cảnh báo
```
Từ Windows (để có IP tấn công thật): `powershell -ExecutionPolicy Bypass -File .\simulate-bruteforce.ps1 -Url https://<IP>`

## Hardening

| Biện pháp | Áp dụng |
|---|---|
| Container chạy **non-root** | webapp (uid 1000), nginx (uid 101), Prometheus/Alertmanager/exporter (nobody), Grafana (472), Loki (10001) |
| **Read-only filesystem**, `cap_drop: ALL`, `no-new-privileges` | webapp, nginx; mọi container có `no-new-privileges` |
| **Network isolation** | `backend` và `monitoring` là mạng internal; chỉ Nginx mở 80/443; MySQL không publish cổng |
| **Mật khẩu mạnh** | Sinh ngẫu nhiên 24 ký tự; `.env` quyền 600, không commit; mật khẩu admin băm **bcrypt** |
| **Hạn chế quyền DB** | `tintuc_app` chỉ SELECT/INSERT/UPDATE/DELETE trên DB `tintuc`; `exporter` chỉ đọc, tối đa 3 kết nối |
| **Security headers** | HSTS, CSP, X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy, Permissions-Policy; `server_tokens off` |
| Bảo vệ trang quản trị | Basic Auth cho phpMyAdmin/Prometheus/Alertmanager; chặn `/metrics`; rate limit đăng nhập (429); khóa IP 5 phút sau 5 lần sai |
| An toàn ứng dụng | Truy vấn SQL tham số hóa, escape HTML (chống XSS), CSRF token, cookie `HttpOnly`/`Secure`/`SameSite=Strict` |

## Cấu trúc thư mục

```
├── app/                          # Mã nguồn web (Node.js) + Dockerfile
├── db/init/                      # Tạo bảng, dữ liệu mẫu, user giới hạn quyền
├── nginx/                        # nginx.conf, conf.d/, certs/ và auth/ (tự sinh, không commit)
├── monitoring/                   # Prometheus (+ luật cảnh báo), Alertmanager, Grafana
├── logging/                      # Loki (+ luật cảnh báo an ninh), Promtail
├── scripts/                      # setup, check-env, pull-images, tao-traffic, simulate-*
├── docs/HUONG_DAN_TUNG_BUOC.md   # Hướng dẫn chi tiết từ đầu đến cuối
├── docker-compose.yml            # Bước 1–3: webapp, mysql, phpmyadmin, nginx
├── docker-compose.monitoring.yml # Bước 4: Prometheus, Alertmanager, Grafana, exporters
├── docker-compose.logging.yml    # Bước 5: Loki, Promtail
└── .env.example                  # Mẫu biến môi trường (COMPOSE_FILE gộp 3 file compose)
```

## Lệnh hữu ích

```bash
docker compose logs -f webapp     # xem log ứng dụng
docker compose stop               # tắt hệ thống, GIỮ dữ liệu
docker compose up -d              # bật lại
docker compose down -v            # XÓA toàn bộ dữ liệu (chỉ dùng khi muốn cài lại từ đầu)
```
