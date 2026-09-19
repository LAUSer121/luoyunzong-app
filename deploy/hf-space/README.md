---
title: Luoyunzong API
emoji: ⛰️
colorFrom: indigo
colorTo: gray
sdk: docker
app_port: 7860
pinned: false
---

# 落云宗 · 云同步服务端（Hugging Face Space）

把服务端的 Node 进程放到常开的容器里，这样**你自己的电脑关机，手机/其它设备也能同步**。

- 数据库：Aiven MySQL（连接信息见 Space 的 Secrets）
- 图片 / 视频：缤纷云 S4 对象存储（配置存在数据库 `app_settings`，App 里可改）
- 存档接口：`/api/archive`，资源接口：`/api/assets`
- 鉴权：`Authorization: Bearer <API_TOKEN>`（`/api/health` 公开）

> Space 必须是 **Public**（免费档不支持私有 Space）。
> 所有接口都要令牌，健康检查只回存储类型与上传上限，不暴露任何隐私。
