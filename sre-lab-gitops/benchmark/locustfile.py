"""
============================================================
AI 推理平台 Locust 压测脚本
============================================================
压测指标:
  - TTPT (Time To First Token): 首 token 延迟
  - TPOT (Time Per Output Token): 每 token 生成时间
  - Throughput: 吞吐量 (requests/sec)
  - 并发响应时间 P50/P90/P99
  - 错误率

用法:
  1. 安装依赖:  pip install locust
  2. 启动压测:  locust -f locustfile.py --host=http://<TRAEFIK_IP>:<PORT>
  3. 打开 Web UI: http://localhost:8089
  4. 无头模式: locust -f locustfile.py --headless --users 100 --spawn-rate 10 --run-time 5m
============================================================
"""

import time
import random
from locust import HttpUser, task, between, events
from locust.runners import STATE_STOPPING, STATE_STOPPED, MasterRunner, LocalRunner


# ============================================================
# 压测配置 (可覆盖)
# ============================================================
# Ollama API 端点将在用户初始化时设置
# 默认模型列表
TEST_MODELS = [
    "qwen2.5:0.5b",
    "qwen2.5:1.5b",
    "qwen2.5:3b",
    "qwen2.5:7b",
]

# 轻量 Prompt 集 - 用于基础吞吐量测试
LIGHT_PROMPTS = [
    "你好，请用一句话介绍自己。",
    "What is Kubernetes?",
    "解释一下云原生的概念。",
    "写一个Python的Hello World函数。",
    "1+1等于几？请直接回答数字。",
]

# 中等 Prompt 集 - 用于延迟测试
MEDIUM_PROMPTS = [
    "请用300字介绍Kubernetes的核心组件。",
    "解释Docker和Podman的区别，列出至少5点。",
    "写一个Python FastAPI的CRUD示例，包含数据库操作。",
    "什么是微服务架构？它的优缺点各是什么？",
    "请详细介绍K3s与K8s的区别和适用场景。",
]

# 重度 Prompt 集 - 用于极限测试
HEAVY_PROMPTS = [
    "请详细解释Kubernetes中StatefulSet和Deployment的区别，包括它们的使用场景、优缺点和配置示例。",
    "从零开始设计一个高并发的AI推理平台架构，包括网络、存储、监控、日志和安全等方面，输出完整的架构设计文档。",
    "详细对比Prometheus和VictoriaMetrics的性能差异，包括存储、查询和资源消耗方面的分析。",
    "请用Python实现一个完整的RAG系统，包括文档加载、向量化、检索和LLM生成四个步骤。",
]


class AIInferenceUser(HttpUser):
    """
    AI 推理平台模拟用户
    模拟真实用户行为：浏览 -> 推理 -> 思考 -> 再次提问
    """

    # 用户等待时间 (模拟人类操作间隔)
    wait_time = between(1, 5)

    # 默认测试模型
    model = "qwen2.5:1.5b"

    def on_start(self):
        """用户初始化：检查 Ollama 服务可用性"""
        try:
            with self.client.get(
                "/api/tags",
                name="health_check",
                catch_response=True,
            ) as resp:
                if resp.status_code == 200:
                    resp.success()
                else:
                    resp.failure(f"Health check failed: {resp.status_code}")
        except Exception as e:
            print(f"[WARN] Health check failed: {e}")

    # ============================================================
    # 场景 1: 轻量推理 (模拟浏览器快速问答)
    # 权重: 50%
    # ============================================================
    @task(50)
    def light_inference(self):
        """轻量推理：短 prompt，快速返回"""
        prompt = random.choice(LIGHT_PROMPTS)

        start_time = time.time()
        ttpt_recorded = False

        with self.client.post(
            "/api/generate",
            json={
                "model": self.model,
                "prompt": prompt,
                "stream": True,
                "options": {
                    "num_predict": 50,
                    "temperature": 0.7,
                },
            },
            name="light_inference",
            catch_response=True,
            stream=True,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"Status: {resp.status_code}")
                return

            # 读取流式响应，计算 TTPT
            first_token_time = None
            total_tokens = 0
            try:
                for line in resp.iter_lines(decode_unicode=True):
                    if not line:
                        continue
                    if first_token_time is None:
                        first_token_time = time.time()
                        ttpt = (first_token_time - start_time) * 1000  # ms
                        # 上报 TTPT 自定义指标
                        events.request.fire(
                            request_type="CUSTOM",
                            name="TTPT_light",
                            response_time=ttpt,
                            response_length=0,
                        )
                        ttpt_recorded = True
                    total_tokens += 1
            except Exception as e:
                resp.failure(f"Stream error: {e}")
                return

            if total_tokens > 0:
                resp.success()
            else:
                resp.failure("No tokens generated")

    # ============================================================
    # 场景 2: 中等推理 (模拟深度对话)
    # 权重: 30%
    # ============================================================
    @task(30)
    def medium_inference(self):
        """中等推理：中等长度 prompt，验证并发处理"""
        prompt = random.choice(MEDIUM_PROMPTS)

        start_time = time.time()

        with self.client.post(
            "/api/generate",
            json={
                "model": self.model,
                "prompt": prompt,
                "stream": True,
                "options": {
                    "num_predict": 200,
                    "temperature": 0.7,
                },
            },
            name="medium_inference",
            catch_response=True,
            stream=True,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"Status: {resp.status_code}")
                return

            first_token_time = None
            total_tokens = 0
            try:
                for line in resp.iter_lines(decode_unicode=True):
                    if not line:
                        continue
                    if first_token_time is None:
                        first_token_time = time.time()
                        ttpt = (first_token_time - start_time) * 1000
                        events.request.fire(
                            request_type="CUSTOM",
                            name="TTPT_medium",
                            response_time=ttpt,
                            response_length=0,
                        )
                    total_tokens += 1
            except Exception as e:
                resp.failure(f"Stream error: {e}")
                return

            total_time = time.time() - start_time
            if total_tokens > 0:
                tpot = ((total_time - (first_token_time - start_time)) / total_tokens) * 1000 if first_token_time else 0
                events.request.fire(
                    request_type="CUSTOM",
                    name="TPOT_medium",
                    response_time=tpot,
                    response_length=total_tokens,
                )
                resp.success()
            else:
                resp.failure("No tokens generated")

    # ============================================================
    # 场景 3: 重度推理 (极限压力测试)
    # 权重: 15%
    # ============================================================
    @task(15)
    def heavy_inference(self):
        """重度推理：长 prompt，模拟复杂场景"""
        prompt = random.choice(HEAVY_PROMPTS)

        start_time = time.time()

        with self.client.post(
            "/api/generate",
            json={
                "model": self.model,
                "prompt": prompt,
                "stream": True,
                "options": {
                    "num_predict": 500,
                    "temperature": 0.7,
                },
            },
            name="heavy_inference",
            catch_response=True,
            stream=True,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"Status: {resp.status_code}")
                return

            first_token_time = None
            total_tokens = 0
            try:
                for line in resp.iter_lines(decode_unicode=True):
                    if not line:
                        continue
                    if first_token_time is None:
                        first_token_time = time.time()
                        ttpt = (first_token_time - start_time) * 1000
                        events.request.fire(
                            request_type="CUSTOM",
                            name="TTPT_heavy",
                            response_time=ttpt,
                            response_length=0,
                        )
                    total_tokens += 1
            except Exception as e:
                resp.failure(f"Stream error: {e}")
                return

            total_time = time.time() - start_time
            if total_tokens > 0:
                tpot = ((total_time - (first_token_time - start_time)) / total_tokens) * 1000 if first_token_time else 0
                events.request.fire(
                    request_type="CUSTOM",
                    name="TPOT_heavy",
                    response_time=tpot,
                    response_length=total_tokens,
                )
                resp.success()
            else:
                resp.failure("No tokens generated")

    # ============================================================
    # 场景 4: 模型列表查询 (模拟管理操作)
    # 权重: 5%
    # ============================================================
    @task(5)
    def list_models(self):
        """查询可用模型列表"""
        with self.client.get(
            "/api/tags",
            name="list_models",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                resp.success()
            else:
                resp.failure(f"Status: {resp.status_code}")


# ============================================================
# 测试事件钩子
# ============================================================
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """压测开始提示"""
    print("=" * 60)
    print("  🚀 AI 推理平台压测启动")
    print("  指标: TTPT | TPOT | Throughput | P50/P90/P99")
    print("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """压测结束，汇总关键指标"""
    print("\n" + "=" * 60)
    print("  📊 压测完成 - 关键指标摘要")
    print("=" * 60)

    stats = environment.stats

    # 汇总各场景指标
    for entry in stats.entries.values():
        if entry.num_requests > 0:
            print(f"\n  [{entry.name}]")
            print(f"    请求数:      {entry.num_requests}")
            print(f"    失败数:      {entry.num_failures}")
            print(f"    平均响应:    {entry.avg_response_time:.1f} ms")
            print(f"    P50:         {entry.get_response_time_percentile(0.5):.1f} ms")
            print(f"    P90:         {entry.get_response_time_percentile(0.9):.1f} ms")
            print(f"    P99:         {entry.get_response_time_percentile(0.99):.1f} ms")
            if entry.num_requests > 1:
                print(f"    RPS:         {entry.total_rps:.2f}")

    # 输出 TTPT 指标
    for entry in stats.entries.values():
        if "TTPT" in entry.name and entry.num_requests > 0:
            print(f"\n  ⚡ [{entry.name}]")
            print(f"    Avg TTPT:    {entry.avg_response_time:.1f} ms")
            print(f"    P50 TTPT:    {entry.get_response_time_percentile(0.5):.1f} ms")
            print(f"    P90 TTPT:    {entry.get_response_time_percentile(0.9):.1f} ms")
            print(f"    P99 TTPT:    {entry.get_response_time_percentile(0.99):.1f} ms")

    print("\n" + "=" * 60)


# ============================================================
# 命令行快捷启动
# ============================================================
if __name__ == "__main__":
    import subprocess
    import sys

    print("""
使用方式:
  # Web UI 模式 (推荐)
  locust -f locustfile.py --host=http://localhost:8080

  # 无头模式 - 快速压测  
  locust -f locustfile.py --headless \\
    --host=http://localhost:8080 \\
    --users 50 \\
    --spawn-rate 5 \\
    --run-time 3m \\
    --html=report.html \\
    --csv=results

  # 阶梯式加压 (需安装 locust-plugins)
  locust -f locustfile.py --host=http://localhost:8080 \\
    --step-users 20 --step-time 60s \\
    --run-time 5m
""")