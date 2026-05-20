# Vertex AI → OpenAI Compatible Proxy

将 Google Vertex AI（Gemini）包装成完整的 OpenAI API 格式。

支持 `AQ.xxx` 格式的 Vertex AI API Key，任何使用 OpenAI API 的工具（Hermes、Cursor、Cline 等）无需修改即可直接接入。

## 支持的功能

- [x] Chat completions (`/v1/chat/completions`)
- [x] 模型列表 (`/v1/models`)
- [x] Streaming 流式输出
- [x] Tool use / Function calling
- [x] System messages
- [x] Vision（图片输入）
- [x] MASTER_KEY 访问控制

## 快速启动

```bash
cp .env.example .env
# 编辑 .env，填入你的 Vertex AI key

docker compose up -d
```

## 直接运行

```bash
export VERTEX_API_KEY=AQ.your_key_here
export MASTER_KEY=sk-any-key-you-want
python3 server.py
```

## 接入配置

任何 OpenAI 兼容工具填入以下配置：

| 参数 | 值 |
|------|----|
| Base URL | `http://your-server:8765/v1` |
| API Key | 你设置的 `MASTER_KEY`（未设置则随便填） |
| Model | `gemini-2.5-flash-lite` |

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `VERTEX_API_KEY` | Vertex AI API Key（AQ.xxx 格式）| 必填 |
| `GEMINI_MODEL` | 使用的模型 | `gemini-2.5-flash-lite` |
| `PORT` | 监听端口 | `8765` |
| `MASTER_KEY` | 访问控制 key（空则不验证）| 空 |
