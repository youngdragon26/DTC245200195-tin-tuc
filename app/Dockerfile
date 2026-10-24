# ---- Image ung dung web Tin tuc ----
FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

# Cai thu vien truoc de tan dung cache layer
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force

COPY src ./src
COPY views ./views
COPY public ./public

# HARDENING: chay bang user "node" (non-root), khong phai root
USER node

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/healthz || exit 1

CMD ["node", "src/server.js"]
