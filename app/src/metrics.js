// Prometheus metrics cho ung dung web (Prometheus scrape tai http://webapp:3000/metrics)
const client = require('prom-client');

const register = new client.Registry();
register.setDefaultLabels({ app: 'tin-tuc' });
client.collectDefaultMetrics({ register }); // CPU, RAM, event loop cua Node.js

const httpRequests = new client.Counter({
  name: 'http_requests_total',
  help: 'Tong so HTTP request',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});

const httpDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Thoi gian xu ly request (giay)',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
  registers: [register],
});

const articleViews = new client.Counter({
  name: 'tintuc_article_views_total',
  help: 'So luot xem bai viet',
  registers: [register],
});

module.exports = { register, httpRequests, httpDuration, articleViews };
