# 🧠 AI Model Scheduler — 异构推理智能调度层

> **统一入口 · 智能路由 · 异构调度** — 让 Bare Metal / K3S Cluster / Cloud GPU 形成统一有机推理系统

[![Python](https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100%2B-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

---

## 📖 项目简介

**AI Model Scheduler** 是 AI Infra 体系的第三块拼图。它位于 **[AI Infra Gateway](../ai-infra-gateway/)** （Windows裸金属推理网关）和 **[SRE-LAB](../sre-lab/)** （K3S云原生推理平台）之上，提供统一的推理调度层。

```
                        ┌──────────────────────────────────┐
                        │   AI Model Scheduler             │  ← 本项目
                        │   统一入口 · 智能路由 · 调度决策    │
                        └──────┬───────────────┬───────────┘
                               │               │
              ┌────────────────▼──┐   ┌────────▼────────────────┐
              │  AI Infra Gateway │   │      SRE-LAB            │
              │  (Bare Metal)     │   │    (K3S Cluster)        │
              │  RTX 4060 Laptop  │   │  Ollama + HPA + GitOps  │
              └───────────────────┘   └─────────────────────────┘
                         │                         │
                         └─────────┬───────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │     Cloud GPU (vLLM)         │
                    │     AutoDL RTX 4090           │
                    └──────────────────────────────┘
```

---

## 🏗️ 架构总览

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
                    │  Ollama Local A   │  │  Ollama Local B        │
                    │  :11434           │  │  :11435                │
                    │  qwen2.5:0.5b     │  │  qwen2.5:1.5b          │
                    │  RTX 4060 Laptop  │  │  RTX 4060 Laptop       │
                    └───────────────────┘  └────────────────────────┘
                                     │
                    ┌────────────────▼──────────────────────────────┐
                    │  Mock vLLM Backend :11436                      │
                    │  模拟云GPU低延迟特征 (TTFT 50ms, 高吞吐)         │
                    └───────────────────────────────────────────────┘
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

## 🚀 快速开始

### 前置条件

- Windows 11 + RTX 4060 Laptop GPU（或任何有 GPU 的机器）
- Python 3.11+
- Ollama 已安装并已有模型（qwen2.5:0.5b / qwen2.5:1.5b）

### 1. 启动推理后端

```powershell
# 终端1：启动 Ollama A（端口11434，已经默认）
ollama serve

# 终端2：启动 Ollama B（端口11435，加载1.5B模型）
$env:OLLAMA_HOST="127.0.0.1:11435"
& "C:\Users\admin\AppData\Local\Programs\Ollama\ollama.exe" serve

# 终端3：启动 Mock vLLM 后端（端口11436，模拟云GPU低延迟）
cd 01-scheduler-core
python mock_backend.py
```

### 2. 启动 Scheduler

```powershell
cd 02-unified-api
python unified_gateway.py
# → Scheduler 运行在 http://localhost:9000
# → API 文档 http://localhost:9000/docs
```

### 3. 调度器仪表盘

```powershell
cd 04-observability
python dashboard.py
# → 仪表盘 http://localhost:9010
```

### 4. 快速测试

```powershell
# 测试推理（Scheduler 自动选择后端）
curl -X POST http://localhost:9000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer test-key" `
  -d '{"model":"qwen2.5:0.5b","messages":[{"role":"user","content":"你好"}]}'

# 指定路由策略
curl -X POST http://localhost:9000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer test-key" `
  -H "X-Routing-Strategy: latency" `
  -d '{"model":"qwen2.5:0.5b","messages":[{"role":"user","content":"你好"}]}'
```

### 5. 运行压测

```powershell
cd 03-scheduler-benchmark
python scheduler_stress_test.py
python cross_backend_compare.py
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

---

## 📊 与现有项目的集成

### 对接 AI Infra Gateway

Scheduler 将 AI Infra Gateway 的 Ollama :11434 作为后端 A 注册。Gateway 自带的 JWT 鉴权和令牌桶限流在 Scheduler 层重新实现（统一入口），Gateway 层可简化为纯推理转发。

### 对接 SRE-LAB

Scheduler 通过 Prometheus Service Discovery 发现 K3S 集群中的 Ollama StatefulSet，自动注册为新后端。HPA 扩缩容后 Scheduler 自动感知新 Pod 加入。

---

## 📝 许可证

MIT