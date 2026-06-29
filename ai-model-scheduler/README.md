# 🧠 AI Model Scheduler — 异构推理智能调度层

> **统一入口 · 智能路由 · 异构调度** — 让 K3S Cluster / Bare Metal / Cloud GPU 形成统一有机推理系统

[![Python](https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100%2B-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![K3S](https://img.shields.io/badge/K3S-v1.31-blue)](https://k3s.io/)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

---

## 📖 项目简介

**AI Model Scheduler** 是 AI Infra 体系的第三块拼图。它位于 **[AI Infra Gateway](../ai-infra-gateway/)**（Windows裸金属推理网关）和 **[SRE-LAB](../sre-lab/)**（K3S云原生推理平台）之上，提供统一的推理调度层。

早期版本是在单机上用 Mock vLLM 模拟云 GPU 做路由验证。后来逐步扩展到多节点生产架构——ECS K3S Master + 本地 VM Worker + AutoDL 云端 GPU，通过 Tailscale 组网打通。

```
                         ┌──────────────────────────────────┐
                         │   AI Model Scheduler             │  ← 本项目
                         │   统一入口 · 智能路由 · 调度决策    │
                         └──────┬───────────────┬───────────┘
                                │               │
               ┌────────────────▼──┐   ┌────────▼────────────────┐
               │  K3S Cluster      │   │   AutoDL Cloud GPU      │
               │  Ollama Stateful  │   │   vLLM RTX 4090         │
               │  (100.88.70.19)   │   │   (SSH 隧道 :6006)      │
               │  qwen2.5:0.5b     │   │   Qwen2.5-7B-Instruct   │
               └───────────────────┘   └─────────────────────────┘
                          │                         │
                          └─────────┬───────────────┘
                                    │
                     ┌──────────────▼──────────────┐
                     │     Local Dev (Optional)     │
                     │     Ollama :11434 (4060)     │
                     └──────────────────────────────┘
```

---

## 🏗️ 架构总览

当前生产部署采用**双引擎异构架构**：

- **Ollama 推理引擎**：运行在 ECS K3S 集群上，通过 K3S Service 暴露（端口 31434），模型包括 qwen2.5:0.5b、nomic-embed-text
- **vLLM GPU 推理引擎**：运行在 AutoDL RTX 4090（24GB）上，模型 Qwen2.5-7B-Instruct，通过 SSH 隧道映射到本地 6006 端口
- **两个节点通过 Tailscale 组网**：ECS（阿里云）+ VM（本地 WSL2）跨网络直连

```
                               ┌───────────────────────────┐
                               │       Client (HTTP)       │
                               └─────────────┬─────────────┘
                                             │
                               ┌─────────────▼─────────────┐
                               │   Unified API :9000       │
                               │   Auth · RateLimit        │
                               │   SSE Streaming           │
                               └─────────────┬─────────────┘
                                             │
                               ┌─────────────▼─────────────┐
                               │   Scheduler Core           │
                               │   ┌─────────────────────┐ │
                               │   │ Routing Engine      │ │
                               │   │  · Model-Aware      │ │
                               │   │  · Latency-Priority │ │
                               │   │  · Cost-Aware       │ │
                               │   │  · Affinity         │ │
                               │   ├─────────────────────┤ │
                               │   │ Load Balancer       │ │
                               │   │  · Weighted RR      │ │
                               │   │  · Least Conn       │ │
                               │   │  · Adaptive Score   │ │
                               │   ├─────────────────────┤ │
                               │   │ Backend Registry    │ │
                               │   │  · Health Check     │ │
                               │   │  · Circuit Breaker  │ │
                               │   │  · Score Tracking   │ │
                               │   └─────────────────────┘ │
                               └──────┬──────────┬─────────┘
                                      │          │
                     ┌────────────────▼──┐  ┌────▼──────────────────┐
                     │  Ollama K3S       │  │  vLLM AutoDL GPU      │
                     │  :31434           │  │  :6006 (SSH 隧道)     │
                     │  qwen2.5:0.5b     │  │  Qwen2.5-7B-Instruct  │
                     │  nomic-embed-text │  │  RTX 4090 24GB        │
                     │  engine=ollama   │  │  engine=openai        │
                     │  weight=1.5      │  │  weight=3.0           │
                     └───────────────────┘  └────────────────────────┘
```

### 路由策略

| 策略 | 触发条件 | 行为 |
|------|---------|------|
| **模型感知** | 请求指定 model 字段 | 只路由到注册了该模型的后端 |
| **延迟优先** | 策略标志=latency | 选择历史 TTFT 最低的健康后端 |
| **吞吐优先** | 策略标志=throughput | 选择历史 Throughput 最高的后端 |
| **成本感知** | 策略标志=cost | 选择 cost_per_token 最低的后端 |
| **亲和性** | 请求携带 session_id | 同一会话固定路由到同一后端 |

---

## 🗺️ 架构演进：从单机到多节点

### 早期版本（单机原型）

一开始只是在本地笔记本上同时启动两个 Ollama 实例（:11434 和 :11435）加一个 Mock vLLM（:11436），验证路由策略和负载均衡算法的正确性。那个阶段的配置文件里只有 `127.0.0.1` 的地址。

### 当前版本（多节点生产架构）

经过反复调试和架构升级，最终形成了这样的部署拓扑：

```
┌─────────────────────────────────────────────────────────────┐
│                     Tailscale 组网                            │
│                                                             │
│  100.88.70.19 (ECS 阿里云)          本地 VM (WSL2)           │
│  ┌─────────────────────┐     ┌─────────────────────────┐   │
│  │ K3S Master 2C4G     │     │ K3S Worker 2C4G         │   │
│  │  ├─ Prometheus+Graf │     │  └─ (备用计算节点)       │   │
│  │  ├─ Ollama Stateful │     │                          │   │
│  │  ├─ ArgoCD          │     │  SSH Tunnel → AutoDL     │   │
│  │  └─ Sealed Secrets  │     │  :6006 ← vLLM API        │   │
│  └─────────────────────┘     └─────────────────────────┘   │
│                                                             │
│  AutoDL RTX 4090 (云端)                                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ vLLM 0.23.0 · Qwen2.5-7B-Instruct                    │   │
│  │ ssh -L 6006:localhost:8000 root@autodl.gpu           │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 目录结构

```
aimodel-scheduler/
├── README.md                              # 本文件
│
├── 01-scheduler-core/                     # 核心调度引擎
│   ├── scheduler.py                       #   调度器主入口（含 HTTP Session 池管理）
│   ├── router.py                          #   路由策略引擎（5种策略）
│   ├── backend_registry.py                #   后端注册与健康检查
│   ├── load_balancer.py                   #   自适应加权负载均衡
│   ├── mock_backend.py                    #   Mock vLLM 后端（模拟低延迟）
│   └── config/
│       └── scheduler_config.yaml          #   后端列表 + 策略配置
│
├── 02-unified-api/                        # 统一 API 层
│   ├── unified_gateway.py                 #   统一入口（兼容 OpenAI API）
│   └── middleware/
│       ├── __init__.py
│       ├── auth.py                        #   统一鉴权
│       └── rate_limit.py                  #   全局限流 + 每后端限流
│
├── 03-scheduler-benchmark/                # 调度器压测
│   ├── scheduler_stress_test.py           #   调度器自身压测
│   └── cross_backend_compare.py           #   多后端对比压测
│
├── 04-observability/                      # 可观测性
│   ├── dashboard.py                       #   调度仪表盘（实时后端状态）
│   └── alerting_rules.yml                 #   调度异常告警规则
│
└── docs/
    ├── SCHEDULER_ARCHITECTURE.md           # 架构设计文档
    ├── ROUTING_STRATEGIES.md              # 路由策略详解
    └── INTEGRATION_GUIDE.md               # 与 AI Infra Gateway / SRE-LAB 集成指南
```

---

## 🚀 部署方式

### 方式一：本地开发模式（单机测试）

```powershell
# 终端1：启动 Ollama（默认端口11434）
ollama serve

# 终端2：启动 Scheduler
cd 02-unified-api
python unified_gateway.py
# → Scheduler 运行在 http://localhost:9000
# → API 文档 http://localhost:9000/docs
```

### 方式二：K3S 生产部署

#### 前置条件

- K3S 多节点集群（ECS Master + VM Worker）
- Tailscale 组网（两个节点跨网络直连）
- Docker 镜像已构建并推送到仓库

#### SSH 隧道连接 AutoDL vLLM

```bash
# 在 VM（WSL2）上建立 SSH 隧道
# 将 AutoDL 实例的 vLLM API（:8000）映射到本地 :6006
ssh -L 6006:localhost:8000 root@<autodl-instance-ip> -p <ssh-port> -N

# 验证隧道是否正常
curl http://localhost:6006/health
# → {"status": "healthy"}
```

> **踩坑记录**：SSH 隧道在长时间空闲后会自动断开，导致 Scheduler 检测到后端不可达后触发断路器。排查后发现是 SSH 的 `ServerAliveInterval` 参数没设。解决方式是在 ssh 命令加上 `-o ServerAliveInterval=60 -o ServerAliveCountMax=3`，每 60 秒发一次心跳保活。

#### 构建镜像并部署

```bash
# 1. 构建 Docker 镜像
cd 04-scheduler/scheduler-deploy
docker build -t ai-model-scheduler:latest .

# 2. 部署到 K3S
kubectl apply -f k8s-deploy.yaml

# 3. 验证部署
kubectl get pods -n scheduler
kubectl get svc -n scheduler
# → ai-model-scheduler ClusterIP :9000

# 4. 查看日志
kubectl logs -n scheduler -l app=ai-model-scheduler
```

### 生产环境后端配置

```yaml
backends:
  - id: "ollama-k3s"
    name: "Ollama K3S Cluster"
    url: "http://100.88.70.19:31434"   # K3S Service NodePort
    engine: "ollama"
    weight: 1.5
    max_concurrency: 8

  - id: "vllm-autodl-gpu"
    name: "vLLM AutoDL RTX4090"
    url: "http://localhost:6006"         # SSH 隧道本地端口
    engine: "openai"
    weight: 3.0                          # GPU 优先
    max_concurrency: 64                  # vLLM continuous batching
```

---

## 📊 压测数据（Ollama vs vLLM）

在双引擎生产环境下进行的对比压测结果：

| Metric | Ollama (CPU) | vLLM (GPU RTX 4090) |
|--------|-------------|---------------------|
| **模型** | qwen2.5:0.5b (0.5B) | Qwen2.5-7B-Instruct (7B) |
| **总延迟** | 7.398s | 0.236s **(31x 更快)** |
| **TTFT** | ~352ms | 279ms |
| **TPS** | 9.4 tok/s | 34.5 tok/s **(3.7x 更高)** |
| **引擎** | Ollama (CPU only) | vLLM 0.23.0 |
| **硬件** | ECS 2C4G | RTX 4090 24GB |

> **结论**：即便 vLLM 跑的模型比 Ollama 大 14 倍（7B vs 0.5B），GPU 推理的总延迟仍然只有 CPU 的 1/31。多次尝试不同配置后得到这个稳定的数据——CPU 推理在小模型上勉强可用，但遇到大模型时差距是数量级的。

### 调度器路由压测

并发梯度压测结果（5 种路由策略全部验证通过）：

```
===== 并发级别: 8 =====
成功: 20/20 (100%)
P50延迟: 342ms | P99延迟: 891ms
吞吐量: 23.4 RPS
后端分布:
  ollama-k3s:          12 (60%)
  vllm-autodl-gpu:     8  (40%)
```

---

## 📈 可观测性

### Scheduler Metrics

Scheduler 在 **:9110** 端口暴露 Prometheus 标准格式指标：

```python
# metrics_wrapper.py 定义的指标
scheduler_requests_total        # 请求总数（按 backend/strategy/status 分桶）
scheduler_request_duration      # 请求延迟直方图
scheduler_backend_health        # 后端健康状态
scheduler_backend_ttft_ms       # 后端平均 TTFT
scheduler_backend_tps           # 后端平均 TPS
scheduler_backend_active_connections  # 后端活跃连接数
scheduler_backend_circuit_breaker     # 断路器状态
scheduler_uptime_seconds        # Scheduler 运行时间
```

### Grafana Dashboard

`03-grafana/dashboard-v2.json` 提供完整的 Grafana Dashboard，包含：

- 集群节点数（基于 node-exporter）
- Scheduler 运行时间
- Ollama 服务状态（UP/DOWN）
- Ollama 已加载模型数
- 后端 TTFT / TPS 趋势图

在 K3S 集群中，Prometheus 自动发现 Scheduler 的 `:9110` 端点，通过 `ServiceMonitor` 配置实现指标采集：

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: scheduler-monitor
  namespace: scheduler
spec:
  endpoints:
  - interval: 15s
    path: /metrics
    port: metrics
  selector:
    matchLabels:
      app: ai-model-scheduler
```

### 仪表盘（轻量版）

无需 Grafana 也能查看实时状态：

```powershell
cd 04-observability
python dashboard.py
# → 仪表盘 http://localhost:9010（auto-refresh 5s）
```

### 告警规则

```yaml
# 关键告警规则（04-observability/alerting_rules.yml）
# - BackendUnhealthy: 任一后端不健康
# - AllBackendsDown: 所有后端不可用
# - CircuitBreakerOpen: 断路器打开
# - HighTTFT: TTFT > 3000ms
# - HighErrorRate: 错误率 > 10%
```

---

## 🔧 技术栈

| 组件 | 技术选型 | 说明 |
|------|---------|------|
| API 框架 | FastAPI | 异步高性能，与现有 Gateway 同栈 |
| HTTP 客户端 | aiohttp | 共享连接池，非阻塞转发 |
| 配置管理 | YAML | 人类可读，与 K8s ConfigMap 兼容 |
| 调度算法 | 加权轮询/最小连接/自适应评分 | 纯 Python 实现 |
| 健康检查 | HTTP GET `/health` | 定时轮询 + 被动检测 |
| 熔断器 | Circuit Breaker (3-failure → OPEN) | 复用 Gateway 设计模式 |
| 鉴权 | Bearer Token (API Key) | 统一鉴权层 |
| 限流 | Token Bucket | 全局限流 + 每后端限流 |
| 可观测性 | Prometheus metrics + matplotlib | 兼容现有体系 |
| 容器编排 | Docker + K3S | 生产部署 |
| 组网 | Tailscale | 跨网络节点直连 |

---

## 🔐 生产环境安全

- 鉴权：Bearer Token（配置在 `scheduler_config.yaml` 的 `api_keys` 列表）
- Sealed Secrets：敏感配置加密存储
- ClusterIP：服务默认不对外暴露（通过 Ingress 或 kubectl port-forward 访问）
- 限流：全局 + 每后端两层令牌桶保护

---

## 🔗 与现有项目的集成

### 对接 AI Infra Gateway

Scheduler 将 AI Infra Gateway 的 Ollama :11434 作为后端注册。Gateway 自带的 JWT 鉴权和令牌桶限流在 Scheduler 层重新实现（统一入口），Gateway 层可简化为纯推理转发。

### 对接 SRE-LAB

Scheduler 通过 K3S Service 发现集群中的 Ollama StatefulSet，自动注册为新后端。HPA 扩缩容后 Scheduler 自动感知新 Pod 加入。

---

## 📝 许可证

MIT