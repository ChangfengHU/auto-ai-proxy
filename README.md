# vertex-openai-proxy

将 Google Vertex AI（Gemini）包装成完整的 OpenAI API 格式。

支持 `AQ.xxx` 格式的 Vertex AI API Key，任何使用 OpenAI API 的工具（Hermes、Cursor、Cline、Windsurf 等）无需任何修改，直接接入 Vertex AI 的算力和配额。

## 支持的功能

- Chat completions（`/v1/chat/completions`）
- Streaming 流式输出
- Tool use / Function calling
- System messages
- Vision 图片输入
- 模型列表（`/v1/models`）
- 开机自启（systemd）
- 可选公网域名（集成 auto-domain）

---

## 一键部署

### 仅本地（推荐先试）

```bash
bash <(curl -fsSL https://skill.vyibc.com/vertex-proxy.sh) --key=AQ.xxx
```

### 本地 + 公网域名（一步到位）

```bash
bash <(curl -fsSL https://skill.vyibc.com/vertex-proxy.sh) \
  --key=AQ.xxx \
  --public \
  --name=myproxy
```

启动后自动输出：
- 本地地址：`http://localhost:8765/v1`
- 公网地址：`https://myproxy.vyibc.com`（加 `--public` 时）

### 完整参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--key=AQ.xxx` | Vertex AI API Key（必填）| — |
| `--port=8765` | 监听端口 | `8765` |
| `--model=xxx` | Gemini 模型 | `gemini-2.5-flash-lite` |
| `--master-key=xxx` | 访问控制 key | 无（不验证）|
| `--public` | 开通公网域名 | 否 |
| `--name=myproxy` | 公网子域名前缀 | `vertex-proxy` |
| `--token=xxx` | auto-domain token | 首次运行时交互输入 |
| `--reset` | 清除配置重新初始化 | — |

---

## 安装 AI Agent Skill

让 Hermes / OpenClaw 等 AI 工具知道如何操作这个代理：

```bash
bash <(curl -fsSL https://skill.vyibc.com/install-vertex-proxy.sh)
```

安装后可以对 Agent 说：
- 「帮我启动 vertex proxy，key 是 AQ.xxx」
- 「给 vertex proxy 开一个公网域名」
- 「把 Hermes 切换到 vertex proxy」
- 「vertex proxy 状态怎么样」

---

## 接入配置

任何支持 OpenAI API 的工具填入：

| 参数 | 值 |
|------|----|
| Base URL | `http://localhost:8765/v1` 或公网地址 |
| API Key | `--master-key` 设置的值（未设置则随便填）|
| Model | `gemini-2.5-flash-lite` |

### Hermes 配置示例

```yaml
model:
  provider: deepseek
  default: gemini-2.5-flash-lite
  base_url: http://127.0.0.1:8765/v1
```

---

## 服务管理

```bash
# 查看状态
sudo systemctl status vertex-proxy

# 重启
sudo systemctl restart vertex-proxy

# 查看日志
sudo journalctl -u vertex-proxy -f

# 停止
sudo systemctl stop vertex-proxy
```

---

## 环境变量

| 变量 | 说明 |
|------|------|
| `VERTEX_API_KEY` | Vertex AI API Key（AQ.xxx 格式）|
| `GEMINI_MODEL` | 使用的模型 |
| `PROXY_PORT` | 监听端口 |
| `MASTER_KEY` | 访问控制 key |

配置文件保存在 `~/.vertex-proxy/.env`
