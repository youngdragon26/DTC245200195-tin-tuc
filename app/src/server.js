const path = require('path');
const crypto = require('crypto');
const express = require('express');
const cookieSession = require('cookie-session');
const bcrypt = require('bcryptjs');
const { pool, waitForDb, ensureAdmin } = require('./db');
const metrics = require('./metrics');
const log = require('./logger');

const app = express();
const PORT = Number(process.env.PORT || 3000);

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, '..', 'views'));
app.disable('x-powered-by'); // khong lo phien ban Express
app.set('trust proxy', 1); // app dung sau Nginx reverse proxy

app.use(express.urlencoded({ extended: false, limit: '200kb' }));
app.use('/static', express.static(path.join(__dirname, '..', 'public'), { maxAge: '1d' }));

if (!process.env.SESSION_SECRET || process.env.SESSION_SECRET.length < 32) {
  log.error('SESSION_SECRET phai dai it nhat 32 ky tu');
  process.exit(1);
}
app.use(
  cookieSession({
    name: 'tt_sess',
    secret: process.env.SESSION_SECRET,
    httpOnly: true,
    sameSite: 'strict',
    secure: process.env.COOKIE_SECURE !== 'false', // chi gui cookie qua HTTPS
    maxAge: 2 * 60 * 60 * 1000,
  })
);

// ---- Middleware: do metrics + ghi access log JSON ----
app.use((req, res, next) => {
  const end = metrics.httpDuration.startTimer();
  const start = Date.now();
  res.on('finish', () => {
    const route = req.route ? req.baseUrl + req.route.path : 'khong_xac_dinh';
    const labels = { method: req.method, route, status: String(res.statusCode) };
    metrics.httpRequests.inc(labels);
    end(labels);
    if (req.path === '/metrics' || req.path === '/healthz') return;
    const level = res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info';
    log[level]('http_request', {
      method: req.method,
      path: req.originalUrl,
      status: res.statusCode,
      duration_ms: Date.now() - start,
      client_ip: req.ip,
    });
  });
  next();
});

app.use((req, res, next) => {
  res.locals.user = req.session && req.session.user;
  next();
});

// ---- Phat hien du lieu dang ngo (mau SQL Injection / XSS) ----
// Ung dung da dung truy van tham so hoa nen KHONG bi khai thac; o day chi ghi log
// su kien SUSPICIOUS_INPUT de Loki canh bao va truy vet ke tan cong.
const SUSPICIOUS =
  /(\bunion\b[\s\S]*\bselect\b|\bor\b\s+['"]?\d+['"]?\s*=\s*['"]?\d+|'\s*or\s+'|'\s*--|;\s*(drop|delete|update|insert)\b|\bsleep\s*\(|<\s*script|javascript:|on(error|load)\s*=)/i;
app.use((req, res, next) => {
  const values = Object.values(req.query || {}).map(String);
  if (req.path === '/admin/login' && req.body) values.push(String(req.body.username || ''));
  const hit = values.find((v) => SUSPICIOUS.test(v));
  if (hit) {
    log.warn('suspicious_input', {
      event: 'SUSPICIOUS_INPUT',
      client_ip: req.ip,
      path: req.path,
      sample: hit.slice(0, 120),
      user_agent: req.get('user-agent') || '',
    });
  }
  next();
});

// ---- Chong CSRF: moi form POST phai kem token bi mat cua phien ----
app.use((req, res, next) => {
  if (!req.session.csrf) req.session.csrf = crypto.randomBytes(24).toString('hex');
  res.locals.csrf = req.session.csrf;
  if (req.method !== 'POST') return next();
  const sent = req.body && typeof req.body._csrf === 'string' ? req.body._csrf : '';
  const ok =
    sent.length === req.session.csrf.length &&
    crypto.timingSafeEqual(Buffer.from(sent), Buffer.from(req.session.csrf));
  if (ok) return next();
  log.warn('csrf_rejected', { event: 'CSRF_REJECTED', client_ip: req.ip, path: req.originalUrl });
  return res.status(403).render('error', {
    title: 'Yêu cầu bị từ chối',
    categories: [],
    message: 'Phiên làm việc không hợp lệ (thiếu CSRF token). Hãy tải lại trang rồi thử lại.',
  });
});

// ---- Tien ich ----
function slugify(text) {
  return String(text)
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 180);
}

async function getCategories() {
  const [rows] = await pool.query('SELECT id, name, slug FROM categories ORDER BY name');
  return rows;
}

async function getPopular(limit = 5) {
  const [rows] = await pool.query(
    `SELECT title, slug, views FROM articles WHERE status = 'published' ORDER BY views DESC LIMIT ?`,
    [limit]
  );
  return rows;
}

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function requireLogin(req, res, next) {
  if (req.session && req.session.user) return next();
  return res.redirect('/admin/login');
}

// ================== TRANG CONG KHAI ==================
app.get(
  '/',
  wrap(async (req, res) => {
    const q = (req.query.q || '').trim().slice(0, 100);
    const categories = await getCategories();
    let sql = `SELECT a.id, a.title, a.slug, a.summary, a.views, a.created_at, c.name AS category
               FROM articles a JOIN categories c ON c.id = a.category_id
               WHERE a.status = 'published'`;
    const params = [];
    if (q) {
      sql += ' AND (a.title LIKE ? OR a.summary LIKE ?)';
      params.push(`%${q}%`, `%${q}%`);
    }
    sql += ' ORDER BY a.created_at DESC LIMIT 20';
    const [articles] = await pool.query(sql, params); // truy van tham so hoa -> chong SQL injection
    res.render('index', {
      title: 'Trang chủ',
      categories,
      articles,
      q,
      popular: await getPopular(),
      heading: q ? `Kết quả tìm kiếm: "${q}" (${articles.length} bài)` : 'Tin mới nhất',
    });
  })
);

app.get(
  '/danh-muc/:slug',
  wrap(async (req, res) => {
    const categories = await getCategories();
    const cat = categories.find((c) => c.slug === req.params.slug);
    if (!cat) return res.status(404).render('error', { title: 'Không tìm thấy', categories, message: 'Danh mục không tồn tại.' });
    const [articles] = await pool.query(
      `SELECT a.id, a.title, a.slug, a.summary, a.views, a.created_at, c.name AS category
       FROM articles a JOIN categories c ON c.id = a.category_id
       WHERE a.status = 'published' AND a.category_id = ? ORDER BY a.created_at DESC`,
      [cat.id]
    );
    res.render('index', {
      title: cat.name,
      categories,
      articles,
      q: '',
      popular: await getPopular(),
      heading: `Danh mục: ${cat.name} (${articles.length} bài)`,
    });
  })
);

app.get(
  '/bai-viet/:slug',
  wrap(async (req, res) => {
    const categories = await getCategories();
    const [rows] = await pool.query(
      `SELECT a.*, c.name AS category, c.slug AS category_slug, u.username AS author
       FROM articles a JOIN categories c ON c.id = a.category_id LEFT JOIN users u ON u.id = a.author_id
       WHERE a.slug = ? AND a.status = 'published'`,
      [req.params.slug]
    );
    if (!rows.length) return res.status(404).render('error', { title: 'Không tìm thấy', categories, message: 'Bài viết không tồn tại.' });
    await pool.query('UPDATE articles SET views = views + 1 WHERE id = ?', [rows[0].id]);
    metrics.articleViews.inc();
    const [related] = await pool.query(
      `SELECT title, slug, summary, created_at FROM articles
       WHERE status = 'published' AND category_id = ? AND id <> ? ORDER BY created_at DESC LIMIT 4`,
      [rows[0].category_id, rows[0].id]
    );
    res.render('article', { title: rows[0].title, categories, a: rows[0], related, popular: await getPopular() });
  })
);

app.get(
  '/gioi-thieu',
  wrap(async (req, res) => {
    const [[stats]] = await pool.query(
      `SELECT COUNT(*) AS articles, COALESCE(SUM(views),0) AS views FROM articles WHERE status = 'published'`
    );
    res.render('about', { title: 'Giới thiệu', categories: await getCategories(), stats });
  })
);

// ================== QUAN TRI (ADMIN) ==================
const failedLogins = new Map(); // chong do mat khau don gian theo IP

app.get('/admin/login', (req, res) => res.render('admin/login', { title: 'Đăng nhập quản trị', error: null }));

app.post(
  '/admin/login',
  wrap(async (req, res) => {
    const ip = req.ip;
    const f = failedLogins.get(ip) || { count: 0, until: 0 };
    if (f.until > Date.now()) {
      log.warn('login_blocked', { event: 'LOGIN_BLOCKED', client_ip: ip });
      return res.status(429).render('admin/login', { title: 'Đăng nhập quản trị', error: 'Sai quá nhiều lần, thử lại sau 5 phút.' });
    }
    const { username = '', password = '' } = req.body;
    const [rows] = await pool.query('SELECT id, username, password_hash, role FROM users WHERE username = ?', [username]);
    const ok = rows.length && (await bcrypt.compare(password, rows[0].password_hash));
    if (!ok) {
      const reason = rows.length ? 'wrong_password' : 'unknown_user';
      f.count += 1;
      if (f.count >= 5) {
        f.until = Date.now() + 5 * 60 * 1000;
        f.count = 0;
      }
      failedLogins.set(ip, f);
      log.warn('login_failed', {
        event: 'LOGIN_FAILED',
        client_ip: ip,
        user: String(username).slice(0, 50),
        reason,
        user_agent: req.get('user-agent') || '',
      });
      return res.status(401).render('admin/login', { title: 'Đăng nhập quản trị', error: 'Sai tên đăng nhập hoặc mật khẩu.' });
    }
    failedLogins.delete(ip);
    req.session.user = { id: rows[0].id, username: rows[0].username, role: rows[0].role };
    log.info('login_success', { event: 'LOGIN_SUCCESS', client_ip: ip, user: username });
    res.redirect('/admin');
  })
);

app.post('/admin/logout', (req, res) => {
  req.session = null;
  res.redirect('/');
});

app.get(
  '/admin',
  requireLogin,
  wrap(async (req, res) => {
    const [articles] = await pool.query(
      `SELECT a.id, a.title, a.slug, a.status, a.views, a.created_at, c.name AS category
       FROM articles a JOIN categories c ON c.id = a.category_id ORDER BY a.created_at DESC`
    );
    const categories = await getCategories();
    const [catStats] = await pool.query(
      `SELECT c.id, c.name, c.slug, COUNT(a.id) AS total
       FROM categories c LEFT JOIN articles a ON a.category_id = c.id
       GROUP BY c.id, c.name, c.slug ORDER BY c.name`
    );
    const [[stats]] = await pool.query(
      `SELECT COUNT(*) AS total,
              COALESCE(SUM(status = 'published'), 0) AS published,
              COALESCE(SUM(status = 'draft'), 0) AS drafts,
              COALESCE(SUM(views), 0) AS views
       FROM articles`
    );
    res.render('admin/dashboard', {
      title: 'Quản trị',
      articles,
      categories,
      catStats,
      stats,
      notice: req.query.tb || '',
    });
  })
);

app.get(
  '/admin/bai-viet/moi',
  requireLogin,
  wrap(async (req, res) => {
    res.render('admin/form', { title: 'Viết bài mới', categories: await getCategories(), a: {}, action: '/admin/bai-viet' });
  })
);

app.post(
  '/admin/bai-viet',
  requireLogin,
  wrap(async (req, res) => {
    const { title, summary, content, category_id, status } = req.body;
    const slug = `${slugify(title)}-${Date.now().toString(36)}`;
    await pool.query(
      'INSERT INTO articles (title, slug, summary, content, category_id, author_id, status) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [title, slug, summary, content, category_id, req.session.user.id, status === 'draft' ? 'draft' : 'published']
    );
    log.info('article_created', { slug, by: req.session.user.username });
    res.redirect('/admin');
  })
);

app.get(
  '/admin/bai-viet/:id/sua',
  requireLogin,
  wrap(async (req, res) => {
    const [rows] = await pool.query('SELECT * FROM articles WHERE id = ?', [req.params.id]);
    if (!rows.length) return res.redirect('/admin');
    res.render('admin/form', { title: 'Sửa bài viết', categories: await getCategories(), a: rows[0], action: `/admin/bai-viet/${rows[0].id}` });
  })
);

app.post(
  '/admin/bai-viet/:id',
  requireLogin,
  wrap(async (req, res) => {
    const { title, summary, content, category_id, status } = req.body;
    await pool.query('UPDATE articles SET title=?, summary=?, content=?, category_id=?, status=? WHERE id=?', [
      title,
      summary,
      content,
      category_id,
      status === 'draft' ? 'draft' : 'published',
      req.params.id,
    ]);
    log.info('article_updated', { id: req.params.id, by: req.session.user.username });
    res.redirect('/admin');
  })
);

app.post(
  '/admin/bai-viet/:id/xoa',
  requireLogin,
  wrap(async (req, res) => {
    await pool.query('DELETE FROM articles WHERE id = ?', [req.params.id]);
    log.warn('article_deleted', { id: req.params.id, by: req.session.user.username });
    res.redirect('/admin');
  })
);

app.post(
  '/admin/danh-muc',
  requireLogin,
  wrap(async (req, res) => {
    const name = (req.body.name || '').trim();
    if (name) {
      await pool.query('INSERT IGNORE INTO categories (name, slug) VALUES (?, ?)', [name, slugify(name)]);
      log.info('category_created', { name, by: req.session.user.username });
    }
    res.redirect('/admin#danh-muc');
  })
);

app.post(
  '/admin/danh-muc/:id/sua',
  requireLogin,
  wrap(async (req, res) => {
    const name = (req.body.name || '').trim().slice(0, 100);
    if (name) {
      await pool.query('UPDATE IGNORE categories SET name = ?, slug = ? WHERE id = ?', [name, slugify(name), req.params.id]);
      log.info('category_updated', { id: req.params.id, name, by: req.session.user.username });
    }
    res.redirect('/admin#danh-muc');
  })
);

app.post(
  '/admin/danh-muc/:id/xoa',
  requireLogin,
  wrap(async (req, res) => {
    const [[row]] = await pool.query('SELECT COUNT(*) AS n FROM articles WHERE category_id = ?', [req.params.id]);
    if (row.n > 0) {
      return res.redirect('/admin?tb=' + encodeURIComponent('Không thể xóa danh mục còn bài viết.') + '#danh-muc');
    }
    await pool.query('DELETE FROM categories WHERE id = ?', [req.params.id]);
    log.warn('category_deleted', { id: req.params.id, by: req.session.user.username });
    res.redirect('/admin#danh-muc');
  })
);

// ================== HE THONG ==================
app.get('/healthz', (req, res) => res.json({ status: 'ok' }));

app.get(
  '/metrics',
  wrap(async (req, res) => {
    res.set('Content-Type', metrics.register.contentType);
    res.end(await metrics.register.metrics());
  })
);

// Route co tinh gay loi de demo giam sat & LogQL (loc log loi 5xx)
app.get('/demo/loi', () => {
  throw new Error('Loi gia lap de demo giam sat');
});

// 404
app.use(
  wrap(async (req, res) => {
    res.status(404).render('error', { title: 'Không tìm thấy', categories: await getCategories().catch(() => []), message: 'Trang không tồn tại.' });
  })
);

// 500 - khong lo stack trace ra ngoai
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  log.error('unhandled_exception', { path: req.originalUrl, error: err.message });
  res.status(500).render('error', { title: 'Lỗi hệ thống', categories: [], message: 'Đã xảy ra lỗi, vui lòng thử lại sau.' });
});

(async () => {
  await waitForDb();
  await ensureAdmin();
  app.listen(PORT, () => log.info('Webapp dang chay', { port: PORT }));
})().catch((err) => {
  log.error('Khoi dong that bai', { error: err.message });
  process.exit(1);
});
