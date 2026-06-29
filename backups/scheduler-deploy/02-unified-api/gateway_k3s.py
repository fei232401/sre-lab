"""
AI Model Scheduler — K3S Production Entry Point
"""
import os
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "01-scheduler-core"))

def run_metrics_loop():
    """等 scheduler 初始化完成后持续更新指标"""
    from metrics_wrapper import start_metrics_server, update_from_scheduler
    import unified_gateway

    # 启动 metrics HTTP server
    start_metrics_server(port=9110)
    print("[Metrics] Prometheus metrics server started on :9110")

    # 等 scheduler 实例初始化完成
    for i in range(30):
        time.sleep(1)
        if hasattr(unified_gateway, 'scheduler') and unified_gateway.scheduler is not None:
            print("[Metrics] Scheduler instance found, starting metric collection")
            break
    else:
        print("[Metrics] WARNING: Scheduler instance not found after 30s")
        return

    # 持续更新
    while True:
        try:
            update_from_scheduler(unified_gateway.scheduler)
        except Exception:
            pass
        time.sleep(5)

if __name__ == "__main__":
    threading.Thread(target=run_metrics_loop, daemon=True).start()

    import uvicorn
    uvicorn.run("unified_gateway:app", host="0.0.0.0", port=9000, log_level="info")
