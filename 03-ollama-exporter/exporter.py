import http.server
import json
import os
import time
import urllib.request
import urllib.error
import threading
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger('ollama-exporter')

OLLAMA_URL = "http://ollama-service:11434"
SCRAPE_INTERVAL = 30  # seconds
BUILD_REVISION = os.environ.get("GIT_SHA", "unknown")

# 全局指标存储
metrics = {
    "ollama_up": 0,
    "ollama_api_response_time_seconds": 0,
    "ollama_models_loaded": 0,
    "ollama_models_list": [],
    "ollama_api_latency_seconds_bucket": {},
    "ollama_scrape_errors_total": 0,
}

def collect_metrics():
    """定期从 Ollama API 采集指标"""
    global metrics
    while True:
        try:
            start = time.time()
            # 1. 健康检查: GET /
            req = urllib.request.Request(f"{OLLAMA_URL}/", method="GET")
            with urllib.request.urlopen(req, timeout=10) as resp:
                body = resp.read().decode()
                metrics["ollama_up"] = 1 if "Ollama is running" in body else 0

            # 2. 获取已加载模型: GET /api/tags
            req2 = urllib.request.Request(f"{OLLAMA_URL}/api/tags", method="GET")
            with urllib.request.urlopen(req2, timeout=15) as resp2:
                data = json.loads(resp2.read().decode())
                model_list = data.get("models", [])
                metrics["ollama_models_loaded"] = len(model_list)
                metrics["ollama_models_list"] = [
                    {"name": m.get("name", "unknown"),
                     "size": m.get("size", 0),
                     "digest": m.get("digest", "")[:16]}
                    for m in model_list
                ]

            latency = time.time() - start
            metrics["ollama_api_response_time_seconds"] = round(latency, 4)

        except urllib.error.URLError as e:
            metrics["ollama_up"] = 0
            metrics["ollama_api_response_time_seconds"] = 0
            metrics["ollama_scrape_errors_total"] += 1
            logger.warning(f"Ollama API 不可达: {e}")
        except Exception as e:
            metrics["ollama_scrape_errors_total"] += 1
            logger.error(f"采集异常: {e}")

        time.sleep(SCRAPE_INTERVAL)

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            output = self._format_prometheus_metrics()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.end_headers()
            self.wfile.write(output.encode())
        elif self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def _format_prometheus_metrics(self):
        lines = []
        lines.append("# HELP ollama_up Ollama 服务是否存活 (1=正常, 0=异常)")
        lines.append("# TYPE ollama_up gauge")
        lines.append(f'ollama_up {metrics["ollama_up"]}')
        lines.append("")
        lines.append("# HELP ollama_api_response_time_seconds Ollama API 响应时间")
        lines.append("# TYPE ollama_api_response_time_seconds gauge")
        lines.append(f'ollama_api_response_time_seconds {metrics["ollama_api_response_time_seconds"]}')
        lines.append("")
        lines.append("# HELP ollama_models_loaded 当前已拉取的模型数量")
        lines.append("# TYPE ollama_models_loaded gauge")
        lines.append(f'ollama_models_loaded {metrics["ollama_models_loaded"]}')
        lines.append("")
        lines.append("# HELP ollama_model_info 模型详情信息")
        lines.append("# TYPE ollama_model_info gauge")
        for m in metrics.get("ollama_models_list", []):
            lines.append(f'ollama_model_info{{model="{m["name"]}",digest="{m["digest"]}"}} {m["size"]}')
        lines.append("")
        lines.append("# HELP sre_lab_build_info 构建版本信息 (1=当前运行版本)")
        lines.append("# TYPE sre_lab_build_info gauge")
        lines.append(f'sre_lab_build_info{{revision="{BUILD_REVISION}"}} 1')
        lines.append("")
        lines.append("# HELP ollama_scrape_errors_total Exporter 采集错误总数")
        lines.append("# TYPE ollama_scrape_errors_total counter")
        lines.append(f'ollama_scrape_errors_total {metrics["ollama_scrape_errors_total"]}')
        lines.append("")
        return "\n".join(lines) + "\n"

    def log_message(self, format, *args):
        logger.info(format % args)

if __name__ == "__main__":
    # 启动后台采集线程
    collector = threading.Thread(target=collect_metrics, daemon=True)
    collector.start()
    logger.info("Ollama Exporter 启动, 监听 :9101/metrics")
    server = http.server.HTTPServer(("0.0.0.0", 9101), MetricsHandler)
    server.serve_forever()
