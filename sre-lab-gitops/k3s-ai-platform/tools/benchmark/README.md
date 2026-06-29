# 🔥 AI 推理平台压测指南

## 压测目标

验证 AI 推理平台在以下维度的性能表现：

| 指标 | 说明 | 目标值 |
|------|------|--------|
| **TTPT** (Time To First Token) | 首 token 延迟 | < 500ms (轻量) / < 2s (重量) |
| **TPOT** (Time Per Output Token) | 每 token 生成速度 | < 50ms/token |
| **Throughput** | 并发吞吐量 | > 10 RPS (QPS) |
| **P90 延迟** | 90% 请求响应时间 | < 5s |
| **P99 延迟** | 99% 请求响应时间 | < 10s |
| **错误率** | 失败请求比例 | < 1% |
| **HPA 触发** | 自动扩容阈值验证 | CPU > 70% 触发 |

---

## 工具选择

### Locust (推荐) - `locustfile.py`

- ✅ 支持流式响应 (SSE/stream)
- ✅ 内置 Web UI 实时监控
- ✅ Python 脚本灵活可编程
- ✅ 自定义指标 (TTPT / TPOT)
- ✅ 分布式并发

### k6 - `k6-script.js`

- ✅ 轻量简单场景
- ✅ 精确的 RPS 控制
- ❌ 流式响应支持有限

---

## 快速开始

### 1. 安装依赖

```bash
# Locust
pip install locust

# k6 (可选)
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6
```

### 2. 启动压测

```bash
# ===== Locust Web UI 模式 (推荐新手) =====
cd 03-benchmark
locust -f locustfile.py --host=http://<YOUR_TRAEFIK_IP>:<PORT>

# 打开浏览器: http://localhost:8089
# 设置用户数 50，孵化率 5，点击 Start Swarming

# ===== Locust 无头模式 (CI/CD 集成) =====
locust -f locustfile.py \
  --headless \
  --host=http://<YOUR_TRAEFIK_IP>:<PORT> \
  --users 50 \
  --spawn-rate 5 \
  --run-time 5m \
  --html=report.html \
  --csv=results

# ===== 阶梯式加压 (模拟真实流量增长) =====
locust -f locustfile.py \
  --headless \
  --host=http://<YOUR_TRAEFIK_IP>:<PORT> \
  --step-users 20 \
  --step-time 60s \
  --run-time 5m

# ===== k6 轻量快速压测 =====
k6 run k6-script.js --env HOST=http://<YOUR_TRAEFIK_IP>:<PORT>
```

### 3. 压测场景说明

| 场景 | 任务权重 | Prompt 长度 | num_predict | 目标验证 |
|------|---------|------------|-------------|---------|
| `light_inference` | 50% | 短 (~15 tokens) | 50 | 基础吞吐量 |
| `medium_inference` | 30% | 中 (~80 tokens) | 200 | 并发处理 |
| `heavy_inference` | 15% | 长 (~300 tokens) | 500 | 极限压力 |
| `list_models` | 5% | - | - | API 健康 |

---

## 压测计划

### Round 1: 基准测试 (单 Pod, 无 HPA)

```bash
# 小流量预热
locust -f locustfile.py --headless --users 5 --spawn-rate 1 --run-time 2m

# 中等流量
locust -f locustfile.py --headless --users 20 --spawn-rate 5 --run-time 3m

# 高流量找瓶颈
locust -f locustfile.py --headless --users 50 --spawn-rate 10 --run-time 5m
```

### Round 2: HPA 触发验证

```bash
# 启动 HPA
kubectl apply -f 02-gitops-production/apps/ai-platform/hpa.yaml

# 持续加压，观察 HPA 自动扩容
# 另开终端监控
watch -n 2 'kubectl get hpa -n ai-platform && kubectl get pods -n ai-platform'

# 阶梯加压
locust -f locustfile.py --headless --users 100 --spawn-rate 10 --run-time 10m

# 验证结果
kubectl describe hpa ollama-hpa -n ai-platform
```

### Round 3: PDB 优雅终止验证

```bash
# 高负载下执行滚动更新/节点驱逐
# 确认 PDB 阻止了不合法驱逐
kubectl drain <node-name> --delete-emptydir-data --ignore-daemonsets

# 检查 PDB 状态
kubectl get pdb -n ai-platform
kubectl describe pdb ollama-pdb -n ai-platform
```

---

## 指标采集与可视化

### Prometheus 采集的压测相关指标

```
# Ollama 请求延迟
ollama_request_duration_seconds

# HPA 指标
kube_horizontalpodautoscaler_status_current_replicas
kube_horizontalpodautoscaler_status_desired_replicas

# 容器资源
container_cpu_usage_seconds_total{namespace="ai-platform"}
container_memory_working_set_bytes{namespace="ai-platform"}

# Traefik 吞吐量
traefik_service_requests_total
```

### Grafana 看板

压测期间重点关注以下看板：
1. **AI 推理平台** - 自定义 Ollama 面板 (ollama-monitor-fix.yaml)
2. **Kubernetes/Compute Resources** - Pod CPU/Memory
3. **Traefik** - 网络吞吐量和延迟

---

## 结果记录模板

```yaml
压测日期: 2026-06-20
模型: qwen2.5:1.5b
并发用户: 50
测试时长: 5m

结果:
  light_inference:
    avg: 850ms
    P50: 600ms
    P90: 1200ms
    P99: 2000ms
    RPS: 12.5
    TTPT_avg: 180ms
    
  medium_inference:
    avg: 3200ms
    P50: 2800ms
    P90: 5000ms
    P99: 8000ms
    RPS: 4.2
    TTPT_avg: 250ms
    TPOT_avg: 25ms

  HPA 行为:
    初始副本: 1
    最大副本: 3
    扩容触发: ✅ (CPU 78%)
    扩容耗时: ~120s
    缩容耗时: ~360s

结论: [填写]