-- Cau truc CSDL Website Tin tuc (chay tu dong lan dau container MySQL khoi tao)
SET NAMES utf8mb4;
CREATE DATABASE IF NOT EXISTS tintuc CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE tintuc;

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) NOT NULL UNIQUE,
  password_hash VARCHAR(100) NOT NULL,          -- mat khau da bam bcrypt
  role ENUM('admin','editor') NOT NULL DEFAULT 'editor',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS categories (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  slug VARCHAR(120) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS articles (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  slug VARCHAR(200) NOT NULL UNIQUE,
  summary VARCHAR(500),
  content MEDIUMTEXT,
  category_id INT NOT NULL,
  author_id INT NULL,
  status ENUM('published','draft') NOT NULL DEFAULT 'published',
  views INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (category_id) REFERENCES categories(id),
  FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE SET NULL,
  INDEX idx_status_created (status, created_at)
);

INSERT INTO categories (name, slug) VALUES
 ('Thời sự','thoi-su'), ('Công nghệ','cong-nghe'), ('Giáo dục','giao-duc'),
 ('Thể thao','the-thao'), ('Kinh tế','kinh-te');

INSERT INTO articles (title, slug, summary, content, category_id, views) VALUES
('Trường ĐH CNTT&TT khai giảng năm học 2026-2027', 'ictu-khai-giang-2026',
 'Hàng nghìn tân sinh viên chính thức bước vào năm học mới tại Thái Nguyên.',
 'Sáng nay, nhà trường đã tổ chức lễ khai giảng năm học mới.\nNhiều chương trình đào tạo gắn với thực tế doanh nghiệp được giới thiệu.', 3, 120),
('Docker và xu hướng triển khai ứng dụng bằng container', 'docker-xu-huong-container',
 'Container hóa giúp đóng gói ứng dụng nhất quán từ máy lập trình tới máy chủ.',
 'Docker cho phép đóng gói ứng dụng cùng toàn bộ thư viện cần thiết.\nKết hợp Docker Compose, việc triển khai nhiều dịch vụ trở nên đơn giản.', 2, 85),
('Giám sát hệ thống với Prometheus và Grafana', 'giam-sat-prometheus-grafana',
 'Bộ đôi mã nguồn mở phổ biến để thu thập và trực quan hóa số liệu hệ thống.',
 'Prometheus định kỳ thu thập metrics từ các dịch vụ.\nGrafana hiển thị metrics dưới dạng dashboard trực quan.', 2, 64),
('Đội tuyển bóng đá trường giành chức vô địch giải sinh viên', 'bong-da-sinh-vien-vo-dich',
 'Chiến thắng thuyết phục trong trận chung kết khu vực phía Bắc.',
 'Trận chung kết diễn ra sôi nổi với sự cổ vũ của đông đảo sinh viên.', 4, 40),
('Kinh tế số tiếp tục tăng trưởng mạnh', 'kinh-te-so-tang-truong',
 'Chuyển đổi số là động lực quan trọng của nền kinh tế.',
 'Các doanh nghiệp đẩy mạnh ứng dụng công nghệ vào sản xuất kinh doanh.', 5, 22);
