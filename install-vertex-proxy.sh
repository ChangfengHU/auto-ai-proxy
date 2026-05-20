#!/usr/bin/env bash
# 安装 vertex-proxy skill，让 AI Agent 知道如何操作这个代理服务

set -euo pipefail

# 检测 Agent 框架
if [[ -d "$HOME/.agents/skills" ]]; then
  SKILL_DIR="$HOME/.agents/skills/vertex-proxy"
elif [[ -d "$HOME/.hermes" ]]; then
  SKILL_DIR="$HOME/.hermes/skills/devops/vertex-proxy"
else
  SKILL_DIR="$HOME/.agents/skills/vertex-proxy"
fi

mkdir -p "$SKILL_DIR"

cat > "$SKILL_DIR/PROMPT.md" <<'EOF'
# vertex-proxy

一个将 Vertex AI (Gemini) 转换为 OpenAI 兼容格式的本地代理服务。
支持 AQ.xxx 格式的 Vertex AI API Key，任何使用 OpenAI API 的工具可直接接入。

## 安装启动

```bash
bash <(curl -fsSL https://skill.vyibc.com/vertex-proxy.sh) --key=AQ.xxx [--port=8765]
```

参数说明：
- `--key=AQ.xxx`     Vertex AI API Key（必填）
- `--port=8765`      监听端口（默认 8765）
- `--model=xxx`      Gemini 模型（默认 gemini-2.5-flash-lite）
- `--master-key=xxx` 访问控制 key（可选）
- `--reset`          清除配置重新初始化

## 接入配置

| 参数     | 值                           |
|----------|------------------------------|
| Base URL | http://localhost:8765/v1     |
| API Key  | 填写 --master-key 设置的值   |
| Model    | gemini-2.5-flash-lite        |

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

## Hermes 配置

```yaml
model:
  provider: deepseek
  default: gemini-2.5-flash-lite
  base_url: http://127.0.0.1:8765/v1
```

## 支持的功能

- Chat completions（/v1/chat/completions）
- Streaming 流式输出
- Tool use / Function calling
- System messages
- Vision 图片输入
- 模型列表（/v1/models）
EOF

echo ""
echo "✅ vertex-proxy skill 已安装到 $SKILL_DIR"
echo ""
echo "现在可以对 Agent 说："
echo "  「帮我启动 vertex proxy，key 是 AQ.xxx」"
echo "  「vertex proxy 状态怎么样」"
echo "  「帮我把 Hermes 切换到 vertex proxy」"
echo ""
