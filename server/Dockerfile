FROM node:20-alpine

WORKDIR /app

# 先装依赖，利用缓存
COPY package.json ./
RUN npm install --omit=dev --no-fund --no-audit

COPY . .

ENV NODE_ENV=production
EXPOSE 8080

# 资源目录（local 驱动用）
VOLUME ["/app/uploads"]

CMD ["node", "index.mjs"]
