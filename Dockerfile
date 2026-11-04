# 使用国内镜像源，避免 Docker Hub 拉取超时
FROM docker.m.daocloud.io/library/node:24-alpine

WORKDIR /app

COPY server/ ./server/
COPY admin/ ./admin/

ENV NODE_ENV=production \
    PORT=3000 \
    DB_PATH=/data/water.db \
    ADMIN_DIR=/app/admin \
    ASSETS_DIR=/app/server/assets

EXPOSE 3000
VOLUME ["/data"]

CMD ["node", "server/src/index.js"]
