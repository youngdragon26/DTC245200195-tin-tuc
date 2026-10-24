const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
const log = require('./logger');

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'mysql',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
  charset: 'utf8mb4',
});

// Cho MySQL san sang (container DB co the khoi dong cham hon app)
async function waitForDb(retries = 30) {
  for (let i = 1; i <= retries; i++) {
    try {
      await pool.query('SELECT 1');
      log.info('Ket noi database thanh cong', { host: process.env.DB_HOST });
      return;
    } catch (err) {
      log.warn('Chua ket noi duoc database, thu lai...', { attempt: i, error: err.code });
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
  throw new Error('Khong the ket noi database');
}

// Tao tai khoan admin lan dau tu bien moi truong (mat khau duoc bam bcrypt)
async function ensureAdmin() {
  const [rows] = await pool.query('SELECT COUNT(*) AS n FROM users');
  if (rows[0].n > 0) return;
  const username = process.env.ADMIN_USERNAME || 'admin';
  const password = process.env.ADMIN_PASSWORD;
  if (!password) {
    log.warn('Chua dat ADMIN_PASSWORD, bo qua tao tai khoan admin');
    return;
  }
  const hash = await bcrypt.hash(password, 12);
  await pool.query('INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)', [
    username,
    hash,
    'admin',
  ]);
  log.info('Da tao tai khoan admin', { username });
}

module.exports = { pool, waitForDb, ensureAdmin };
