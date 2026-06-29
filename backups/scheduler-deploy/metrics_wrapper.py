"""
Prometheus Metrics Wrapper for AI Model Scheduler
在 /metrics 端点暴露 Prometheus 标准格式指标
"""
import time
import psutil
from prometheus_client import (
    Gauge, Counter, Histogram, Info,
    start_http_server, generate_latest, CONTENT_TYPE_LATEST
)

# ============ Scheduler 指标 ============
scheduler_info = Info("scheduler", "AI Model Scheduler info")
scheduler_uptime = Gauge("scheduler_uptime_seconds", "Scheduler uptime in seconds")
scheduler_requests_total = Counter(
    "scheduler_requests_total", "Total requests routed",
    ["backend", "strategy", "status"]
)
scheduler_request_duration = Histogram(
    "scheduler_request_duration_seconds", "Request duration",
    ["backend", "strategy"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)

# Backend 指标
backend_health = Gauge(
    "scheduler_backend_health", "Backend health status (1=healthy, 0=unhealthy)",
    ["backend"]
)
backend_ttft = Gauge(
    "scheduler_backend_ttft_ms", "Backend avg TTFT in ms",
    ["backend"]
)
backend_tps = Gauge(
    "scheduler_backend_tps", "Backend avg TPS (tokens/sec)",
    ["backend"]
)
backend_active_connections = Gauge(
    "scheduler_backend_active_connections", "Active connections per backend",
    ["backend"]
)
backend_circuit_breaker = Gauge(
    "scheduler_backend_circuit_breaker", "Circuit breaker state (0=closed, 1=open, 2=half_open)",
    ["backend"]
)

# 系统指标
process_memory = Gauge("scheduler_process_memory_bytes", "Process memory usage")
process_cpu = Gauge("scheduler_process_cpu_percent", "Process CPU usage")

_start_time = time.time()

def update_from_scheduler(scheduler_instance):
    """从 Scheduler 实例更新指标"""
    scheduler_info.info({
        "version": "2.0.0",
        "mode": "k3s-production"
    })
    scheduler_uptime.set(time.time() - _start_time)

    try:
        metrics = scheduler_instance.get_metrics()
        for name, backend_metrics in metrics.get("backends", {}).items():
            backend_health.labels(backend=name).set(
                1 if backend_metrics.get("healthy") else 0
            )
            backend_ttft.labels(backend=name).set(
                backend_metrics.get("avg_ttft_ms", 0)
            )
            backend_tps.labels(backend=name).set(
                backend_metrics.get("avg_tps", 0)
            )
            backend_active_connections.labels(backend=name).set(
                backend_metrics.get("active_connections", 0)
            )
            cb_state = backend_metrics.get("circuit_breaker", "closed")
            state_map = {"closed": 0, "open": 1, "half_open": 2}
            backend_circuit_breaker.labels(backend=name).set(
                state_map.get(cb_state, 0)
            )
    except Exception:
        pass

    proc = psutil.Process()
    process_memory.set(proc.memory_info().rss)
    process_cpu.set(proc.cpu_percent(interval=0))

def start_metrics_server(port=9100):
    """启动 Prometheus metrics HTTP 服务"""
    start_http_server(port)
