#!/usr/bin/env bash
# vertex-proxy — 一键启动 Vertex AI → OpenAI 兼容代理（可选公网域名）
# 用法: bash <(curl -fsSL https://skill.vyibc.com/vertex-proxy.sh) --key=AQ.xxx [--public] [--name=myproxy]

set -euo pipefail

CACHE_DIR="$HOME/.vertex-proxy"
ENV_FILE="$CACHE_DIR/.env"
SERVER_FILE="$CACHE_DIR/server.py"
SERVICE_NAME="vertex-proxy"

mkdir -p "$CACHE_DIR"

# ── 解析参数 ──────────────────────────────────────────────
KEY=""
PORT="8765"
MODEL="gemini-2.5-flash-lite"
MASTER_KEY=""
RESET=0
PUBLIC=0
DOMAIN_NAME="vertex-proxy"
DOMAIN_TOKEN=""

for arg in "$@"; do
  case "$arg" in
    --key=*)        KEY="${arg#--key=}"               ;;
    --port=*)       PORT="${arg#--port=}"             ;;
    --model=*)      MODEL="${arg#--model=}"           ;;
    --master-key=*) MASTER_KEY="${arg#--master-key=}" ;;
    --public)       PUBLIC=1                          ;;
    --name=*)       DOMAIN_NAME="${arg#--name=}"      ;;
    --token=*)      DOMAIN_TOKEN="${arg#--token=}"    ;;
    --reset)        RESET=1                           ;;
    -h|--help)
      echo "用法: bash <(curl -fsSL https://skill.vyibc.com/vertex-proxy.sh) [选项]"
      echo ""
      echo "选项:"
      echo "  --key=KEY          Vertex AI API Key（必填，AQ.xxx 格式）"
      echo "  --port=PORT        监听端口（默认 8765）"
      echo "  --model=MODEL      Gemini 模型（默认 gemini-2.5-flash-lite）"
      echo "  --master-key=KEY   访问控制 key（可选）"
      echo "  --public           同时开启公网域名（通过 auto-domain）"
      echo "  --name=NAME        公网子域名前缀（默认 vertex-proxy）"
      echo "  --token=TOKEN      auto-domain token（已有可跳过交互）"
      echo "  --reset            清除配置重新初始化"
      echo ""
      echo "示例:"
      echo "  # 仅本地"
      echo "  bash <(curl -fsSL https://skill.vyibc.com/vertex-proxy.sh) --key=AQ.xxx"
      echo ""
      echo "  # 本地 + 公网域名一步到位"
      echo "  bash <(curl -fsSL https://skill.vyibc.com/vertex-proxy.sh) --key=AQ.xxx --public --name=myproxy"
      exit 0 ;;
  esac
done

# ── 重置 ──────────────────────────────────────────────────
if [[ "$RESET" == "1" ]]; then
  rm -rf "$CACHE_DIR"
  mkdir -p "$CACHE_DIR"
  echo "🗑  已清除缓存和配置"
fi

# ── 读取已有配置 ───────────────────────────────────────────
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" 2>/dev/null || true
KEY="${KEY:-${VERTEX_API_KEY:-}}"
PORT="${PORT:-${PROXY_PORT:-8765}}"
MODEL="${MODEL:-${GEMINI_MODEL:-gemini-2.5-flash-lite}}"
MASTER_KEY="${MASTER_KEY:-${MASTER_KEY:-}}"

# ── 补全缺失参数 ───────────────────────────────────────────
if [[ -z "$KEY" ]]; then
  read -rp "请输入 Vertex AI API Key (AQ.xxx 格式): " KEY
fi

# ── 写入配置 ───────────────────────────────────────────────
cat > "$ENV_FILE" <<ENVEOF
VERTEX_API_KEY=$KEY
PROXY_PORT=$PORT
GEMINI_MODEL=$MODEL
MASTER_KEY=$MASTER_KEY
ENVEOF
chmod 600 "$ENV_FILE"

# ── 写入 server.py ─────────────────────────────────────────
cat > "$SERVER_FILE" <<'PYEOF'
#!/usr/bin/env python3
import json, os, time, urllib.request, urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler

VERTEX_KEY  = os.environ.get("VERTEX_API_KEY", "")
MODEL       = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash-lite")
PORT        = int(os.environ.get("PROXY_PORT", "8765"))
MASTER_KEY  = os.environ.get("MASTER_KEY", "")
VERTEX_BASE = "https://aiplatform.googleapis.com/v1/publishers/google/models"

def convert_request(body):
    messages, contents, sys_parts = body.get("messages", []), [], []
    for msg in messages:
        role, content, tool_calls = msg.get("role","user"), msg.get("content",""), msg.get("tool_calls",[])
        parts = []
        if role == "system":
            text = content if isinstance(content,str) else "".join(c.get("text","") for c in content if isinstance(c,dict))
            sys_parts.append({"text": text}); continue
        if isinstance(content,str) and content: parts.append({"text": content})
        elif isinstance(content,list):
            for c in content:
                if isinstance(c,dict):
                    if c.get("type")=="text": parts.append({"text":c["text"]})
                    elif c.get("type")=="image_url":
                        url=c.get("image_url",{}).get("url","")
                        if url.startswith("data:"):
                            mime,data=url.split(";base64,"); mime=mime.replace("data:","")
                            parts.append({"inlineData":{"mimeType":mime,"data":data}})
        for tc in tool_calls:
            func=tc.get("function",{}); args=func.get("arguments","{}")
            if isinstance(args,str):
                try: args=json.loads(args)
                except: args={}
            parts.append({"functionCall":{"name":func.get("name",""),"args":args}})
        if role=="tool":
            parts.append({"functionResponse":{"name":msg.get("name","tool"),"response":{"output":content if isinstance(content,str) else json.dumps(content)}}})
            contents.append({"role":"user","parts":parts}); continue
        if parts: contents.append({"role":"model" if role=="assistant" else "user","parts":parts})
    req = {"contents": contents}
    if sys_parts: req["systemInstruction"] = {"parts": sys_parts}
    tools = body.get("tools",[])
    if tools:
        decls=[{"name":t["function"].get("name",""),"description":t["function"].get("description",""),"parameters":t["function"].get("parameters",{})} for t in tools if t.get("type")=="function"]
        req["tools"]=[{"functionDeclarations":decls}]
    choice=body.get("tool_choice")
    if choice=="required": req["toolConfig"]={"functionCallingConfig":{"mode":"ANY"}}
    elif choice=="none": req["toolConfig"]={"functionCallingConfig":{"mode":"NONE"}}
    elif isinstance(choice,dict) and choice.get("type")=="function":
        req["toolConfig"]={"functionCallingConfig":{"mode":"ANY","allowedFunctionNames":[choice["function"]["name"]]}}
    cfg={}
    if "max_tokens" in body: cfg["maxOutputTokens"]=body["max_tokens"]
    if "temperature" in body: cfg["temperature"]=body["temperature"]
    if "top_p" in body: cfg["topP"]=body["top_p"]
    if "stop" in body: cfg["stopSequences"]=body["stop"] if isinstance(body["stop"],list) else [body["stop"]]
    if cfg: req["generationConfig"]=cfg
    return req

def convert_response(vertex):
    candidates=vertex.get("candidates",[]); message={"role":"assistant","content":None}; finish="stop"
    if candidates:
        parts=candidates[0].get("content",{}).get("parts",[]); texts=[]; tcalls=[]
        for i,p in enumerate(parts):
            if "text" in p: texts.append(p["text"])
            elif "functionCall" in p:
                fc=p["functionCall"]; tcalls.append({"id":f"call_{i}_{int(time.time())}","type":"function","function":{"name":fc.get("name",""),"arguments":json.dumps(fc.get("args",{}))}})
        if texts: message["content"]="".join(texts)
        if tcalls: message["tool_calls"]=tcalls; finish="tool_calls"
        finish={"STOP":"stop","MAX_TOKENS":"length","SAFETY":"content_filter"}.get(candidates[0].get("finishReason","STOP"),"stop")
    usage=vertex.get("usageMetadata",{})
    return {"id":f"chatcmpl-{int(time.time())}","object":"chat.completion","created":int(time.time()),"model":MODEL,"choices":[{"index":0,"message":message,"finish_reason":finish}],"usage":{"prompt_tokens":usage.get("promptTokenCount",0),"completion_tokens":usage.get("candidatesTokenCount",0),"total_tokens":usage.get("totalTokenCount",0)}}

def convert_chunk(chunk, cid):
    candidates=chunk.get("candidates",[]); delta={}; finish=None
    if candidates:
        parts=candidates[0].get("content",{}).get("parts",[]); texts=[]; tcalls=[]
        for i,p in enumerate(parts):
            if "text" in p: texts.append(p["text"])
            elif "functionCall" in p:
                fc=p["functionCall"]; tcalls.append({"index":i,"id":f"call_{i}","type":"function","function":{"name":fc.get("name",""),"arguments":json.dumps(fc.get("args",""))}})
        if texts: delta["content"]="".join(texts)
        if tcalls: delta["tool_calls"]=tcalls
        fr=candidates[0].get("finishReason")
        if fr and fr!="FINISH_REASON_UNSPECIFIED": finish={"STOP":"stop","MAX_TOKENS":"length"}.get(fr,"stop")
    return f'data: {json.dumps({"id":cid,"object":"chat.completion.chunk","created":int(time.time()),"model":MODEL,"choices":[{"index":0,"delta":delta,"finish_reason":finish}]})}\n\n'

class Handler(BaseHTTPRequestHandler):
    def log_message(self,fmt,*args): print(f"[proxy] {self.command} {self.path}")
    def _auth_ok(self):
        if not MASTER_KEY: return True
        return self.headers.get("Authorization","").replace("Bearer ","").strip()==MASTER_KEY
    def _json(self,status,obj):
        body=json.dumps(obj).encode()
        self.send_response(status); self.send_header("Content-Type","application/json"); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if not self._auth_ok(): self._json(401,{"error":{"message":"Unauthorized"}}); return
        self._json(200,{"object":"list","data":[{"id":MODEL,"object":"model","owned_by":"google","created":1700000000}]})
    def do_POST(self):
        if not self._auth_ok(): self._json(401,{"error":{"message":"Unauthorized"}}); return
        length=int(self.headers.get("Content-Length",0)); body=json.loads(self.rfile.read(length) or b"{}")
        stream=body.get("stream",False); vbody=convert_request(body); payload=json.dumps(vbody).encode()
        endpoint="streamGenerateContent" if stream else "generateContent"
        url=f"{VERTEX_BASE}/{MODEL}:{endpoint}?key={VERTEX_KEY}"+("&alt=sse" if stream else "")
        req=urllib.request.Request(url,data=payload,headers={"Content-Type":"application/json"})
        try: resp=urllib.request.urlopen(req,timeout=120)
        except urllib.error.HTTPError as e:
            err=json.loads(e.read() or b"{}"); self._json(e.code,{"error":{"message":err.get("error",{}).get("message",str(e)),"type":"api_error","code":e.code}}); return
        if stream:
            self.send_response(200); self.send_header("Content-Type","text/event-stream"); self.send_header("Cache-Control","no-cache"); self.send_header("Transfer-Encoding","chunked"); self.end_headers()
            cid=f"chatcmpl-{int(time.time())}"
            for raw in resp:
                line=raw.decode("utf-8").strip()
                if not line.startswith("data:"): continue
                ds=line[5:].strip()
                if not ds or ds=="[DONE]": continue
                try: self.wfile.write(convert_chunk(json.loads(ds),cid).encode()); self.wfile.flush()
                except: pass
            self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()
        else:
            self._json(200,convert_response(json.loads(resp.read())))

if __name__=="__main__":
    if not VERTEX_KEY: print("❌ VERTEX_API_KEY 未设置"); exit(1)
    print(f"[proxy] Vertex AI → OpenAI Proxy | port={PORT} | model={MODEL}")
    HTTPServer(("0.0.0.0",PORT),Handler).serve_forever()
PYEOF

# ── 启动代理服务 ───────────────────────────────────────────
echo ""
echo "🚀 启动 Vertex AI Proxy..."

if command -v systemctl &>/dev/null && [[ -d /etc/systemd/system ]]; then
  sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<SVCEOF
[Unit]
Description=Vertex AI OpenAI Proxy
After=network.target

[Service]
User=$USER
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/python3 $SERVER_FILE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now "$SERVICE_NAME"
  echo "✅ 已注册为系统服务 (systemd，开机自启)"
else
  nohup env VERTEX_API_KEY="$KEY" PROXY_PORT="$PORT" GEMINI_MODEL="$MODEL" MASTER_KEY="$MASTER_KEY" \
    python3 "$SERVER_FILE" >> "$CACHE_DIR/proxy.log" 2>&1 &
  echo "✅ 已后台启动 (PID: $!)"
fi

# ── 输出本地连接信息 ───────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Vertex AI → OpenAI Proxy 已就绪"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  本地 Base URL : http://localhost:$PORT/v1"
echo "  API Key       : ${MASTER_KEY:-随便填}"
echo "  Model         : $MODEL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 开公网域名（--public）─────────────────────────────────
if [[ "$PUBLIC" == "1" ]]; then
  echo ""
  echo "🌐 正在开通公网域名..."
  echo "   (通过 auto-domain 将 localhost:$PORT 暴露到公网)"
  echo ""

  AUTO_DOMAIN_CMD="bash <(curl -fsSL https://skill.vyibc.com/auto-domain.sh) --port=$PORT --name=$DOMAIN_NAME"
  [[ -n "$DOMAIN_TOKEN" ]] && AUTO_DOMAIN_CMD="$AUTO_DOMAIN_CMD --token=$DOMAIN_TOKEN"

  eval "$AUTO_DOMAIN_CMD"
else
  echo ""
  echo "💡 需要公网域名？加 --public 参数："
  echo "   bash <(curl -fsSL https://skill.vyibc.com/vertex-proxy.sh) \\"
  echo "     --key=AQ.xxx --public --name=$DOMAIN_NAME"
fi
