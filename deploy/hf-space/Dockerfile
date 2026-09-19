# Hugging Face Space 用的镜像：直接从公开仓库拉服务端代码，避免两份代码不同步。
# 说明：
#  - HF Space 要求应用监听 7860（这里用 PORT=7860 覆盖，代码无需改动）
#  - 数据库 / 令牌等敏感值走 Space 的 Secrets，不写进镜像
FROM node:20-alpine

RUN apk add --no-cache git tini

WORKDIR /app

ARG REPO=https://github.com/LAUSer121/luoyunzong-app.git
RUN git clone --depth 1 "$REPO" /tmp/repo \
 && cp -r /tmp/repo/server/. /app/ \
 && rm -rf /tmp/repo

RUN npm install --omit=dev --no-fund --no-audit

ENV NODE_ENV=production
ENV PORT=7860
EXPOSE 7860

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "index.mjs"]
