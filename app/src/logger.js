// Ghi log dang JSON ra stdout -> Docker thu lai -> Promtail day ve Loki.
// Moi dong log la 1 object JSON nen LogQL dung duoc "| json" de loc theo truong.
function write(level, msg, extra = {}) {
  const line = { time: new Date().toISOString(), level, msg, ...extra };
  const out = JSON.stringify(line);
  if (level === 'error') console.error(out);
  else console.log(out);
}

module.exports = {
  info: (msg, extra) => write('info', msg, extra),
  warn: (msg, extra) => write('warn', msg, extra),
  error: (msg, extra) => write('error', msg, extra),
};
