# Hướng dẫn từ đầu đến cuối – Đề 19 Website Tin tức

## Tổng quan

| Mục | Giá trị |
|---|---|
| Sinh viên | Thân Tuấn Vũ – DTC245200195 – CNTT K23G |
| Máy ảo | VMware, Ubuntu 26.04, IP `192.168.105.130`, user `vu`, tên tắt SSH `tintuc-vm` |
| Thư mục dự án trên máy ảo | `~/DTC245200195-tin-tuc` (repo git) – `~/tintuc-src` (bản giải nén gốc) |
| Repo GitHub | `https://github.com/<tai-khoan-MSSV>/DTC245200195-tin-tuc` |
| IDE | Antigravity trên Windows, kết nối máy ảo qua SSH |
| Công nghệ | Docker Compose, Node.js + Express, MySQL 8.4, phpMyAdmin, Nginx, Prometheus, Grafana, Alertmanager, Loki, Promtail |

Quy trình gồm 9 giai đoạn:

1. Chuẩn bị máy ảo và kết nối Antigravity
2. Kiểm tra và dọn dẹp môi trường
3. Tạo repo GitHub và đưa mã nguồn vào máy ảo
4. Commit 1 – Web + CSDL + Nginx
5. Commit 2 – Prometheus + Grafana + Alertmanager
6. Commit 3 – Loki + Promtail + cảnh báo log
7. Mô phỏng sự cố an toàn thông tin: cảnh báo, truy vết, chặn IP
8. Kiểm tra hardening và bảo mật
9. Viết báo cáo, nộp bài và demo

> Quy ước: khối lệnh ghi **[Windows]** chạy trong PowerShell trên Windows; còn lại chạy trong **terminal của Antigravity** (đang kết nối `SSH: tintuc-vm`, dấu nhắc `vu@vu:~$`).

---

## Giai đoạn 1. Chuẩn bị máy ảo và kết nối Antigravity *(đã xong)*

Trên máy ảo:
```bash
sudo apt update
sudo apt install -y openssh-server git curl openssl unzip
sudo systemctl enable --now ssh
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER          # đăng xuất rồi đăng nhập lại để có hiệu lực
git config --global user.name  "Than Tuan Vu"
git config --global user.email "email-dang-ky-github@..."
```

**[Windows]** SSH key và tên tắt:
```powershell
ssh-keygen -t ed25519                  # đã có key thì trả lời n
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh vu@192.168.105.130 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
notepad $env:USERPROFILE\.ssh\config   # dán 3 dòng dưới, lưu KHÔNG có đuôi .txt
```
```
Host tintuc-vm
    HostName 192.168.105.130
    User vu
```
Antigravity: biểu tượng `><` góc dưới trái → **Connect to Host** → `tintuc-vm` → Linux. Góc dưới trái hiện `SSH: tintuc-vm` là được.

---

## Giai đoạn 2. Kiểm tra và dọn dẹp môi trường

```bash
docker ps -a
df -h /            # cần trống >= 10 GB
free -h            # RAM máy ảo nên >= 4 GB (khuyên 6 GB)
```
Nếu ổ đầy vì image cũ của bài khác: `docker system prune -a` (xác nhận `y`). **Không** dùng lệnh này khi đã có dữ liệu của đề 19 cần giữ.

Sau khi có mã nguồn (giai đoạn 3), chạy script kiểm tra:
```bash
bash ~/DTC245200195-tin-tuc/scripts/check-env.sh
```
Mọi dòng phải `[OK]`. Dòng `[!!]` nào thì làm theo lệnh gợi ý in ngay bên dưới.

---

## Giai đoạn 3. Tạo repo GitHub và đưa mã nguồn vào máy ảo

### 3.1. Trên GitHub
1. Tài khoản GitHub đặt tên theo MSSV (yêu cầu của thầy).
2. **New repository** → tên `DTC245200195-tin-tuc` → Public → **không** tick Add README → Create.
3. **Personal Access Token**: Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate, tick `repo`. Khi `git push` hỏi *Password* thì dán token này.

### 3.2. Clone repo rỗng rồi chép mã nguồn vào
```bash
cd ~
git clone https://github.com/<tai-khoan-MSSV>/DTC245200195-tin-tuc.git
```
Đưa file zip vào máy ảo bằng **một** trong hai cách:
- Kéo file `DTC245200195-tin-tuc.zip` từ File Explorer thả vào cột Explorer của Antigravity (đang mở thư mục `/home/vu`).
- **[Windows]** `scp $env:USERPROFILE\Downloads\DTC245200195-tin-tuc.zip tintuc-vm:~`

Giải nén và chép (chép cả file ẩn `.gitignore`, `.env.example`, `.gitattributes`):
```bash
cd ~
unzip -o DTC245200195-tin-tuc.zip -d tintuc-src
cp -r tintuc-src/DTC245200195-tin-tuc/. DTC245200195-tin-tuc/
cd ~/DTC245200195-tin-tuc
sed -i 's/\r$//' scripts/*.sh db/init/*.sh      # bỏ ký tự xuống dòng Windows nếu có
ls -a
git remote -v                                   # phải thấy link repo của bạn
```
Antigravity: **File → Open Folder** → `/home/vu/DTC245200195-tin-tuc`.

---

## Giai đoạn 4. Commit 1 – Web + CSDL + Nginx

### 4.1. Thành phần
| Service | Vai trò |
|---|---|
| webapp | Website tin tức Node.js/Express: trang chủ, danh mục, bài viết, tìm kiếm, quản trị; log JSON; `/metrics` |
| mysql | MySQL 8.4 trong mạng `backend` internal, không mở cổng ra ngoài |
| phpmyadmin | Quản trị CSDL tại `/phpmyadmin/`, có Basic Auth trước |
| nginx | Reverse proxy, HTTPS tự ký, security headers, CSP, rate limit đăng nhập |

### 4.2. Chạy thử
```bash
cd ~/DTC245200195-tin-tuc
bash scripts/setup.sh 192.168.105.130     # tạo .env, chứng chỉ HTTPS, Basic Auth; in BẢNG TÀI KHOẢN
sed -i 's|^COMPOSE_FILE=.*|COMPOSE_FILE=docker-compose.yml|' .env
bash scripts/check-env.sh
bash scripts/pull-images.sh               # tải image tuần tự, tự thử lại nếu lỗi mạng
docker compose up -d --build
docker compose ps                         # 4 container Up (healthy)
```
Ghi lại bảng tài khoản mà `setup.sh` in ra (website admin, Basic Auth `quantri`, MySQL root, Grafana).

Kiểm tra trên trình duyệt Windows:
- `https://192.168.105.130` → cảnh báo chứng chỉ → *Nâng cao → Tiếp tục* → trang **TIN TỨC 24H**.
- `/admin` → đăng nhập → viết bài, sửa, xóa.
- `/phpmyadmin/` → Basic Auth `quantri` → đăng nhập MySQL `root` → xem bảng `articles`, `users`, `categories`.

Lỗi font tiếng Việt (chữ kiểu `ThÃ´ng`): dòng 2 của `db/init/01-schema.sql` phải là `SET NAMES utf8mb4;`, rồi tạo lại dữ liệu (chỉ làm lúc mới cài): `docker compose down -v && docker compose up -d`.

### 4.3. Commit và push
```bash
git status        # .env, nginx/certs/*.key, nginx/auth/.htpasswd KHÔNG được xuất hiện
git add README.md .gitignore .gitattributes .env.example docker-compose.yml app db \
        nginx/nginx.conf nginx/conf.d/default.conf nginx/certs/.gitkeep nginx/auth/.gitkeep scripts docs
git commit -m "Commit 1: Web tin tuc + MySQL + phpMyAdmin, Nginx reverse proxy HTTPS + security headers"
git push -u origin main
```

---

## Giai đoạn 5. Commit 2 – Prometheus + Grafana + Alertmanager

### 5.1. Chạy
```bash
sed -i 's|^COMPOSE_FILE=.*|COMPOSE_FILE=docker-compose.yml:docker-compose.monitoring.yml|' .env
bash scripts/pull-images.sh
docker compose up -d
docker compose restart nginx
docker compose ps                          # 11 container
bash scripts/tao-traffic.sh 127.0.0.1 30   # tạo lưu lượng để biểu đồ có số liệu
```

### 5.2. Kiểm tra
| Trang | Kết quả cần thấy |
|---|---|
| `https://192.168.105.130/prometheus/targets` (Basic Auth) | 7 job đều **UP**: prometheus, webapp, nginx, mysql, cadvisor, node, alertmanager |
| `https://192.168.105.130/prometheus/alerts` | 5 luật cảnh báo, trạng thái *Inactive* (xanh) |
| `https://192.168.105.130/grafana/` | Dashboards → **Tin tuc** → *Tin tức - Giám sát hệ thống* có số liệu |
| `https://192.168.105.130/alertmanager/` | Mở được, chưa có cảnh báo |

Thử cảnh báo **MySQLDown**:
```bash
docker compose stop mysql      # chờ khoảng 1 phút
```
Alertmanager hiện **MySQLDown** (critical) → chụp ảnh → `docker compose start mysql`.

### 5.3. Commit và push
```bash
git add docker-compose.monitoring.yml monitoring nginx/conf.d/monitoring.locations
git commit -m "Commit 2: Giam sat Prometheus + Grafana + Alertmanager"
git push
```

---

## Giai đoạn 6. Commit 3 – Loki + Promtail + cảnh báo log

### 6.1. Chạy
```bash
sed -i 's|^COMPOSE_FILE=.*|COMPOSE_FILE=docker-compose.yml:docker-compose.monitoring.yml:docker-compose.logging.yml|' .env
bash scripts/pull-images.sh
docker compose up -d
docker compose ps                          # đủ 13 container
bash scripts/tao-traffic.sh 127.0.0.1 30
```

### 6.2. Truy vấn LogQL (Grafana → Explore → chọn **Loki**, khung thời gian *Last 1 hour*)
| # | LogQL | Ý nghĩa |
|---|---|---|
| 1 | `{job="nginx"}` | Toàn bộ log truy cập Nginx |
| 2 | `{job="nginx"} \| json \| status >= 400` | Request lỗi (404, 429, 500…) |
| 3 | `{job="webapp", level=~"error\|warn"} \| json` | Lỗi / cảnh báo của ứng dụng |
| 4 | `sum by (job) (count_over_time({job=~".+"}[5m]))` | Số dòng log mỗi dịch vụ |

(Trong Grafana gõ dấu `|` bình thường; `\|` chỉ là cách viết trong bảng Markdown.)

### 6.3. Luật cảnh báo log (Loki Ruler → Alertmanager)
| Cảnh báo | Điều kiện | Mức |
|---|---|---|
| BruteForceLoginDetected | Một IP đăng nhập sai / bị khóa ≥ 5 lần trong 1 phút | critical |
| RateLimitTriggered | Nginx trả 429 cho một IP > 5 lần trong 1 phút | warning |
| SuspiciousInputDetected | Dữ liệu chứa mẫu SQL Injection / XSS | warning |
| WebappErrorLogsSpike | > 5 dòng log error trong 2 phút | warning |

Kiểm tra Loki đã nạp luật:
```bash
docker compose exec prometheus wget -qO- http://loki:3100/prometheus/api/v1/rules | grep -o '"name":"[A-Za-z]*"'
```

### 6.4. Commit và push
```bash
git add docker-compose.logging.yml logging
git commit -m "Commit 3: Log tap trung Loki + Promtail va canh bao an ninh"
git push
git log --oneline            # đúng 3 commit
```

---

## Giai đoạn 7. Sự cố an toàn thông tin: cảnh báo và truy vết

### 7.1. Tấn công dò mật khẩu
Từ máy ảo:
```bash
bash scripts/simulate-bruteforce.sh https://localhost admin 30
```
Hoặc **[Windows]** để có IP tấn công thật (`192.168.105.1`):
```powershell
scp tintuc-vm:~/DTC245200195-tin-tuc/scripts/simulate-bruteforce.ps1 .
powershell -ExecutionPolicy Bypass -File .\simulate-bruteforce.ps1 -Url https://192.168.105.130 -User admin -N 30
```
Kết quả: vài lần **401** (sai mật khẩu), sau đó **429** (Nginx hoặc ứng dụng chặn vì vượt ngưỡng).

### 7.2. Xem cảnh báo – làm ngay trong 1–2 phút
- `https://192.168.105.130/alertmanager/` → thấy **BruteForceLoginDetected**, **RateLimitTriggered** kèm IP.
- Grafana → **Alerting → Alert rules** → *Clear filters* → mục *Data source-managed* → luật ở trạng thái **Firing**.
- Dashboard *Tin tức - Giám sát hệ thống* → nhóm **An ninh & cảnh báo**.

Không thấy cảnh báo thì chạy chẩn đoán:
```bash
docker compose exec prometheus wget -qO- http://loki:3100/prometheus/api/v1/rules | grep -o '"name":"[A-Za-z]*"'
docker compose exec prometheus wget -qO- http://alertmanager:9093/alertmanager/api/v2/alerts | grep -o '"alertname":"[A-Za-z]*"'
```

### 7.3. Truy vết log (Grafana → Explore → Loki, *Last 24 hours*)
```logql
sum by (client_ip) (count_over_time({job="webapp", event="LOGIN_FAILED"} | json [10m]))
{job="webapp", event="LOGIN_FAILED"} | json | client_ip="192.168.105.1" | line_format "{{.time}} user={{.user}} reason={{.reason}} ua={{.user_agent}}"
{job="nginx", status="429"} | json | remote_addr="192.168.105.1"
{job="webapp", event="LOGIN_SUCCESS"} | json | client_ip="192.168.105.1"
```
Câu 1 cho biết IP tấn công; thay IP thật vào các câu sau (không gõ chữ "IP"). Câu 4 trống nghĩa là kẻ tấn công **không** đăng nhập thành công.

### 7.4. Xử lý: chặn IP tấn công
Mở `nginx/conf.d/default.conf`, trong khối `server { listen 8443 ssl; ... }`, thêm ngay dưới dòng `server_name _;`:
```nginx
    deny 192.168.105.1;
```
Lưu (Ctrl+S), rồi:
```bash
docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload
```
Chạy lại tấn công từ Windows → phải ra **HTTP 403** → chụp ảnh. Sau đó gỡ chặn để không commit nhầm:
```bash
git restore nginx/conf.d/default.conf
docker compose exec nginx nginx -s reload
git status                   # nothing to commit
```
Lưu ý: chặn `192.168.105.1` thì **chính trình duyệt Windows của bạn cũng bị chặn** cho tới khi gỡ.

### 7.5. Thử SQL Injection / XSS
```bash
bash scripts/simulate-sqli.sh https://localhost
```
Mọi dòng phải là `lo du lieu: KHONG`. Alertmanager hiện **SuspiciousInputDetected**. Truy vết:
```logql
{job="webapp", event="SUSPICIOUS_INPUT"} | json | line_format "{{.client_ip}} {{.path}} {{.sample}}"
```

---

## Giai đoạn 8. Kiểm tra hardening và bảo mật

| # | Lệnh | Kết quả đạt |
|---|---|---|
| H1 | `docker compose exec webapp id` và `docker compose exec nginx id` | uid=1000(node), uid=101(nginx) – không phải root |
| H2 | `docker inspect tintuc-webapp --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}}'` | `true [ALL] [no-new-privileges:true]` |
| H3 | `docker network inspect tintuc_backend --format '{{.Internal}}'` và `docker compose ps mysql` | `true`; MySQL không có cổng ra ngoài |
| H4 | `ls -l .env` | `-rw-------`; trên GitHub không có `.env` |
| H5 | `docker compose exec mysql mysql -uroot -p -e "SHOW GRANTS FOR 'tintuc_app'@'%'"` | Chỉ SELECT, INSERT, UPDATE, DELETE trên `tintuc.*` |
| H6 | `curl -skI https://localhost` | Có HSTS, CSP, X-Frame-Options, X-Content-Type-Options |

Kiểm thử chức năng bảo mật:

| # | Kịch bản | Kết quả |
|---|---|---|
| T1 | `curl -sI http://localhost \| head -1` | 301 sang HTTPS |
| T2 | `curl -sk -o /dev/null -w "%{http_code}\n" https://localhost/metrics` | 403 |
| T3 | `curl -sk -o /dev/null -w "%{http_code}\n" -X POST https://localhost/admin/logout` (gửi form không có CSRF token) | 403 |
| T4 | `curl -sk -o /dev/null -w "%{http_code}\n" https://localhost/phpmyadmin/` (không có Basic Auth) | 401 |
| T5 | `bash scripts/simulate-sqli.sh https://localhost` | Không lộ dữ liệu |
| T6 | **[Windows]** `Test-NetConnection 192.168.105.130 -Port 3306` | `TcpTestSucceeded : False` |
| T7 | Đăng nhập sai 5 lần trên trình duyệt | Bị khóa 5 phút (429) |

---

## Giai đoạn 9. Báo cáo, nộp bài và demo

### 9.1. Báo cáo (theo đúng form mẫu của thầy, tối thiểu 10 trang)
| Chương | Nội dung chính | Ảnh minh chứng |
|---|---|---|
| Bìa | Trường, khoa, tên đề tài, họ tên, MSSV, lớp, Thái Nguyên 2026 | – |
| 1. Tổng quan kiến trúc và môi trường | Sơ đồ kiến trúc, 3 mạng Docker, GitHub 3 commit, check-env | Hình 1.1–1.3 |
| 2. Web, CSDL, Reverse Proxy | Chức năng web, CSDL 3 bảng, Docker Compose, Nginx HTTPS + headers | Hình 2.1–2.8 |
| 3. Giám sát Prometheus, Grafana, Loki | Targets, dashboard, MySQLDown, LogQL, sự cố brute-force → cảnh báo → truy vết → chặn IP | Hình 3.1–3.14 |
| 4. Hardening và đánh giá bảo mật | Non-root, read-only, mạng internal, quyền DB, bcrypt, CSRF, SQLi, bảng kiểm thử | Hình 4.1–4.6 |
| Kết luận | Kết quả đạt được, hướng phát triển | – |

Trước khi nộp:
- Word: Ctrl+A → F9 để cập nhật mục lục.
- Không còn khung "[CHÈN HÌNH]"; **không có ảnh lộ mật khẩu** (`cat .env`, bảng tài khoản).
- Báo cáo **không** đẩy lên GitHub (repo giữ đúng 3 commit).

### 9.2. Ngày demo
```bash
cd ~/DTC245200195-tin-tuc
docker compose up -d
docker compose ps            # 13 container
```
Thứ tự demo: (1) xem tin, đăng nhập admin, viết bài, xem dữ liệu trong phpMyAdmin → (2) `curl -I` thấy 301 và security headers → (3) Prometheus targets, dashboard Grafana → (4) chạy brute-force, mở Alertmanager trong 1 phút, truy vết LogQL → (5) SQLi nếu được hỏi → (6) các lệnh hardening.

### 9.3. Những điều không được làm
- Không chạy `docker compose down -v` sau khi đã có dữ liệu (xóa sạch CSDL). Tắt máy: `docker compose stop`.
- Không commit `.env`, `nginx/certs/*.key`, `nginx/auth/.htpasswd`, hay dòng `deny`.
- Không để lộ nội dung `.env` trên màn hình hoặc trong ảnh báo cáo.

### 9.4. Câu hỏi thường gặp khi bảo vệ
| Câu hỏi | Trả lời ngắn |
|---|---|
| Vì sao MySQL không mở cổng? | Nằm trong mạng `backend` internal, chỉ webapp, phpMyAdmin và exporter truy cập được |
| Reverse proxy để làm gì? | Một cổng vào duy nhất, lo HTTPS, header bảo mật, rate limit; các dịch vụ phía sau không lộ ra ngoài |
| Prometheus lấy số liệu thế nào? | Cứ 15 giây gọi `/metrics` của từng target (kiểu *pull*) |
| Log đi đường nào? | stdout container → Promtail (đọc qua Docker API) → Loki → Grafana; Loki Ruler → Alertmanager |
| Vì sao có lúc 429 trước 401? | Nginx giới hạn 5 request/phút cho `/admin/login`, vượt ngưỡng thì chặn trước khi tới app |
| Mật khẩu lưu thế nào? | Người dùng: băm bcrypt trong DB. Hệ thống: `.env` quyền 600, không lên GitHub |
| SQL Injection có tác dụng không? | Không: mọi truy vấn dùng tham số `?`; payload chỉ bị ghi log và cảnh báo |
| Có phải HTML tĩnh không? | Không: Node.js/Express render trang trên server, dữ liệu lấy từ MySQL |

---

## Phụ lục: lỗi thường gặp và cách sửa

| Lỗi | Nguyên nhân | Cách sửa |
|---|---|---|
| `ssh: Connection refused` | Máy ảo chưa bật SSH | `sudo apt install -y openssh-server && sudo systemctl enable --now ssh` |
| Antigravity không thấy host / `Could not resolve hostname` | File `config.txt` thay vì `config` | `Rename-Item $env:USERPROFILE\.ssh\config.txt config` |
| `scp: No such file` khi chạy trong Antigravity | Chạy `scp` ở terminal máy ảo | Chạy `scp` trong PowerShell Windows, hoặc kéo thả file vào Antigravity |
| `'docker' is not recognized` | Đang gõ ở Windows (`C:\...>`) | `ssh tintuc-vm` trước |
| `permission denied ... docker.sock` | Chưa vào nhóm docker | `sudo usermod -aG docker $USER`, đăng xuất rồi vào lại |
| `git push` báo *Password authentication not supported* | GitHub không nhận mật khẩu | Dùng Personal Access Token |
| `not a git repository` | Đứng sai thư mục | `cd ~/DTC245200195-tin-tuc` |
| `TLS handshake timeout` khi pull | Mạng NAT của máy ảo chập chờn | `bash scripts/pull-images.sh` (tải tuần tự, tự thử lại) |
| cAdvisor báo *image not found* | Kho image cAdvisor thay đổi | Trong `docker-compose.monitoring.yml` đổi image thành `gcr.io/cadvisor/cadvisor:latest` |
| Lỗi font tiếng Việt | MySQL đọc file SQL không theo UTF-8 | `SET NAMES utf8mb4;` + `docker compose down -v` + `up -d` |
| Nginx `cannot load certificate` | Chưa chạy setup | `bash scripts/setup.sh 192.168.105.130` |
| Đổi mật khẩu trong `.env` nhưng MySQL không nhận | Mật khẩu DB chỉ tạo lúc khởi tạo lần đầu | `docker compose down -v` rồi `up -d` (mất dữ liệu) |
| Không vào được web sau khi khởi động lại máy ảo | IP máy ảo đổi | `ip a` xem IP mới, sửa `HostName` trong file SSH config và `SERVER_IP` trong `.env`, xóa `nginx/certs/selfsigned.*`, chạy lại `setup.sh` |
| Alertmanager trống | Cảnh báo hết hạn sau vài phút | Chạy tấn công rồi xem ngay |
| Explore *No logs found* | Gõ chữ "IP" thay vì IP thật, hoặc khung thời gian ngắn | Dùng IP thật, chọn *Last 24 hours* |
| Chặn IP nhưng vẫn 401 | Chưa lưu/reload, đặt nhầm khối server, hoặc sai IP | `grep deny nginx/conf.d/default.conf`, reload, xem `client_ip` trong log |
| Gửi form báo *thiếu CSRF token* (403) | Trang đã mở quá lâu / đổi tab | Tải lại trang rồi thử lại |
