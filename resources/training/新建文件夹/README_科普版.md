# 🧠 AI Model Scheduler — 小白零基础完全科普

> 本文档的目标：**让完全不懂技术的人也能看懂本项目在做什么，每个术语什么意思，甚至能自己动手复现。**

---

## 📌 一句话说清楚：这个项目是干啥的？

假设你有好几台"AI 机器人"（叫**推理后端**），分布在不同的地方：

- 一台在你的笔记本电脑上（慢但免费）
- 一台在你家里的服务器上（中等速度）
- 一台在云端的超级计算机上（快但花钱）

**AI Model Scheduler** 就像一个**智能总机话务员**。你只需要打一个电话（发一个 HTTP 请求），话务员会自动判断：

- 谁现在有空？（健康检查 + 负载均衡）
- 谁最适合干这个活？（路由策略）
- 谁最便宜？谁最快？（成本感知/延迟优先）

你不用管背后有几台机器、每台机器在哪、是什么型号——**统一入口，智能调度**。

---

# 🧱 第一部分：基础概念扫盲（从零开始）

## 1. 什么是 AI 模型推理？

- **训练**：拿海量数据"教"AI 学会说话/画图/写代码（像读书考大学）
- **推理（Inference）**：训练好的 AI 实际回答你的问题（像毕业了开始工作）
- 本项目只做**推理阶段**的事情

## 2. 什么是 GPU？（显卡）

- GPU = Graphics Processing Unit（图形处理器），俗称**显卡**
- 普通显卡：玩游戏用（比如 RTX 4060、RTX 4090）
- AI 显卡：做计算用，因为 AI 需要大量并行计算，GPU 最擅长
- 关键指标：**显存**（VRAM）越大，能跑的模型越大
  
| 显卡型号 | 显存 | 能跑什么模型 | 速度 |
|---------|------|-------------|------|
| RTX 4060 Laptop（笔记本） | 8GB | 小模型（0.5B~7B） | 中等 |
| RTX 4090（台式机/云端） | 24GB | 大模型（7B~70B） | 非常快 |
| RTX 4090（云端 AutoDL） | 24GB | 本项目 vLLM 引擎 | 实测比 CPU 快 31 倍 |

> B = Billion（十亿参数），参数越多越聪明，但也越吃显存

## 3. 什么是 Ollama？

- **Ollama** 是一个"一键运行 AI 模型"的工具
- 你只需要在命令行输入 `ollama run qwen2.5`，它就会自动下载并启动 AI 模型
- 它会在你的电脑上开一个**端口**（默认 11434），其他程序可以通过这个端口调用 AI
- 类比：Ollama 就像你的私人 AI 服务器，安装即用

## 4. 什么是 vLLM？

- vLLM = Virtual Large Language Model
- 和 Ollama 类似，也是运行 AI 模型的工具
- **优势**：吞吐量极高（每秒能处理的请求更多），适合**生产环境**
- 通常部署在**云服务器**上，配合高端 GPU（如 RTX 4090、A100）
- 本项目用 vLLM 在 AutoDL RTX 4090 上跑 Qwen2.5-7B 模型

## 5. 什么是端口（Port）？

- 端口就像一台电脑上的"门牌号"
- IP 地址是"这栋楼在哪"，端口是"哪个房间"
- 比如 `localhost:11434` 就是：本地电脑（localhost）+ 房间号 11434
- 不同程序用不同端口，不会冲突：

| 程序 | 端口号 | 用途 |
|------|--------|------|
| Ollama（第一个实例） | 31434 | K3S 集群中的推理后端 |
| vLLM（通过 SSH 隧道） | 6006 | 云端 GPU 推理后端 |
| **Scheduler 主入口** | **9000** | **统一入口** |
| 仪表盘 | 9010 | 可视化监控 |
| Prometheus Metrics | 9110 | 给 Prometheus 采集指标 |

## 6. 什么是 HTTP 和 REST API？

- HTTP = 电脑之间"说话"的协议（超文本传输协议）
- REST API = 一种约定好的"说话方式"
- 常见的"动词"（方法）：

| 方法 | 意思 | 类比 |
|------|------|------|
| GET | 获取数据 | "查一下" |
| POST | 提交数据 | "帮我做件事" |
| PUT | 更新数据 | "改一下" |
| DELETE | 删除数据 | "删掉" |

- 本项目主要用 `POST`：你把问题发过去，AI 把回答返回给你

## 7. 什么是 JSON？

- JSON 是一种**数据格式**，长得像这样：

```json
{
  "model": "qwen2.5:0.5b",
  "messages": [
    {"role": "user", "content": "你好"}
  ]
}
```

- 前端和后端、后端和后端之间传递数据都用 JSON
- 人类可读，电脑也能解析

## 8. 什么是 SSE 流式传输？

- SSE = Server-Sent Events（服务器推送事件）
- 传统请求：你问 → AI 想半天 → 一次性把整个答案给你 → 你干等
- 流式传输：你问 → AI 边想边回答 → 一个字一个字往外蹦 → 你看到打字效果
- 用户体验更好，感觉 AI 在"实时思考"
- 浏览器原生支持，不需要额外库

---

# 🏗️ 第二部分：项目架构科普

## 9. 什么是"三层架构"？

本项目是 AI Infra 体系的**第三层**：

```
应用层     AI Model Scheduler（智能调度层）    ← 本项目
           ↓                    ↓
中间层     K3S 集群               AutoDL 云端 GPU
           (Ollama 推理)          (vLLM 推理)
           ↓                    ↓
硬件层     ECS 服务器             RTX 4090 显卡
           2C4G 阿里云           24GB 显存
```

**每一层的职责：**

| 层级 | 名称 | 负责什么 | 类比 |
|------|------|---------|------|
| 底层 | 硬件/后端 | 实际运行 AI 模型的机器 | 餐厅的厨房 |
| 中间层 | 推理后端 | 管理模型、接受请求、返回结果 | 厨师 |
| 顶层 | 调度层（本项目） | 决定请求发给谁、怎么做负载均衡 | 餐厅经理/总台 |

## 10. 什么是 K3S 集群？

- K3S = 轻量版 Kubernetes（k8s），Kubernetes 的首尾字母+中间8个字母
- **Kubernetes（k8s）**：业界最流行的容器编排平台，自动管理容器的部署、扩缩容、负载均衡
- **K3S**：精简版，适合边缘计算、IoT 设备、资源有限的服务器
- 在本项目中，K3S 集群有两个节点：
  - ECS Master（100.88.70.19，阿里云 2C4G）
  - VM Worker（本地 WSL2，2C4G）
- 优势：
  - **自动扩缩容（HPA）**：访问量大时自动增加实例，访问量小时自动减少
  - **自动恢复**：某个实例挂了，自动重启
  - **声明式配置（GitOps）**：通过 Git 仓库管理配置，改代码自动生效

## 11. 什么是 Cloud GPU？（云显卡）

- 你不需要自己买昂贵的显卡，而是租云服务商的 GPU
- 常见服务商：AutoDL、阿里云、AWS、Google Cloud
- 优势：按小时付费，需要时租用，用完释放
- 本项目示例使用 AutoDL 的 RTX 4090（24GB 显存）
- 通过 SSH 隧道连接：本机和云 GPU 之间建立一条加密通道

## 12. 什么是 Tailscale？

- **Tailscale** = 一种组网工具，能让不同网络下的电脑像在同一个局域网一样直接通信
- 本项目中 ECS（阿里云）和本地 VM（WSL2）通过 Tailscale 组网
- 即使两个节点在不同的物理网络，也能互相访问
- 使用 WireGuard 加密，配置非常简单

## 13. 什么是 SSH 隧道？

- SSH 隧道 = 通过 SSH 协议建立一条加密的"管道"
- 本项目中，AutoDL 云 GPU 在公网上，不能直接访问
- 通过 SSH 隧道把云上的 vLLM 端口（:8000）映射到本地（:6006）
- 命令：`ssh -L 6006:localhost:8000 root@autodl-ip -N`
- 本地程序访问 :6006 就像访问云端 :8000 一样

> **踩坑记录**：最开始没加 `ServerAliveInterval` 参数，SSH 隧道空闲一段时间就自动断了。排查后发现 SSH 默认没有心跳保活。加上 `-o ServerAliveInterval=60` 后解决问题。

---

# ⚙️ 第三部分：核心组件科普

## 13. FastAPI（API 框架）

- **FastAPI** = 一个 Python 写的 Web 框架
- 专门用来写 API 接口，特点是**快**（性能高 + 开发快）
- 自动生成 API 文档（访问 `/docs` 就能看到漂亮的交互式文档）
- 本项目用 FastAPI 搭建了两个服务：
  - `unified_gateway.py` → Scheduler 主入口（端口 9000）
  - `dashboard.py` → 仪表盘（端口 9010）

## 14. aiohttp（异步 HTTP 客户端）

- aiohttp = Async IO HTTP（异步输入输出 HTTP 库）
- **同步**：发一个请求，干等着直到结果回来（像打电话）
- **异步**：发完请求继续做别的事，结果回来再处理（像发微信）
- 异步的好处：同样的时间内能处理更多请求
- 本项目用 aiohttp 在 Scheduler 和各后端之间转发请求

## 15. BackendRegistry（后端注册表）

- **什么是注册表？** 记录所有"可用后端"信息的清单
- 就像一个**通讯录**，记录每个后端：
  - 名字（ollama-k3s / vllm-autodl-gpu）
  - 地址（100.88.70.19:31434 / localhost:6006）
  - 有什么模型（qwen2.5:0.5b / Qwen2.5-7B）
  - 当前是否健康
  - 历史表现评分

- **健康检查（Health Check）**：每 10 秒挨个给后端发"你还好吗？"的请求
  - 如果后端回复"我很好" → 标记为 HEALTHY
  - 如果连续 3 次不回复 → 标记为 UNHEALTHY

## 16. Circuit Breaker（断路器）

- 灵感来自电路中的**保险丝/断路器**
- 三种状态：

```
CLOSED（闭合）→ 正常工作
   ↓ 连续失败 3 次
OPEN（断开）→ 拒绝请求，让后端"休息"
   ↓ 等待 30 秒
HALF_OPEN（半开）→ 放一个测试请求进来
   ↓ 成功 → 回到 CLOSED
   ↓ 失败 → 回到 OPEN
```

- 作用：**防止雪崩效应**——一个后端挂了，不停重试只会让情况更糟
- 断路器让它先"冷静"一下，再尝试恢复

> **踩坑记录**：早期测试时遇到一次断路器误判——SSH 隧道短暂中断，Scheduler 连续 3 次健康检查失败后触发了断路器。但隧道很快就恢复了，断路器还在 OPEN 状态等了 30 秒。后来把 `half_open_max_requests` 从 1 调到 2，加快恢复速度。

## 17. 负载均衡（Load Balancer）

- **什么是负载？** 请求的压力
- **什么是均衡？** 均匀分配
- **负载均衡**：把请求合理分配给各个后端，避免"有的人累死，有的人闲死"

本项目的三种负载均衡算法：

| 算法 | 怎么选后端 | 适合场景 |
|------|-----------|---------|
| **加权轮询（Weighted RR）** | 按权重随机选（权重高的被选中概率大） | 后端性能差异大的场景 |
| **最小连接（Least Connections）** | 选当前正在处理的请求最少的 | 请求耗时差异大的场景 |
| **自适应评分（Adaptive Score）** | 动态算分，综合延迟+错误率+并发量 | 最智能，也是默认策略 |

## 18. 路由策略（Routing Strategy）

- **路由** = 决定请求发到哪个后端
- 比负载均衡更高一层：先决定"方向"，再决定"具体给谁"

本项目的五种路由策略：

| 策略 | 触发方式 | 做什么 | 类比 |
|------|---------|--------|------|
| **模型感知** | 请求带 `model` 参数 | 只路由到有这个模型的后端 | "谁负责川菜就去谁那" |
| **延迟优先** | 头部 `X-Routing-Strategy: latency` | 选历史首字延迟最低的 | "谁打字快就用谁" |
| **吞吐优先** | 头部 `X-Routing-Strategy: throughput` | 选每秒处理最多请求的 | "谁手脚麻利用谁" |
| **成本感知** | 头部 `X-Routing-Strategy: cost` | 选每次调用最便宜的 | "谁便宜用谁" |
| **亲和性** | 请求带 `session_id` | 同一会话始终发到同一后端 | "上次谁服务的还是谁" |

**执行顺序**（优先级）：
```
1. 按 model 字段过滤（模型感知）
2. 过滤掉不健康的后端
3. 过滤掉断路器打开的后端
4. 检查是否有亲和性规则（session_id）
5. 根据策略选择（latency / throughput / cost / weighted）
6. 用负载均衡算法从候选池中选一个
```

---

# 🛡️ 第四部分：安全与防护科普

## 19. 什么是鉴权（Authentication）？

- **鉴权** = 验证"你是谁"
- 本项目用 **Bearer Token** 方式：
  - 每个请求的头部带上 `Authorization: Bearer test-key`
  - 服务器检查这个 key 是否在允许列表里
  - 相当于**会员卡**——有卡才能进

## 20. 什么是限流（Rate Limiting）？

- **限流** = 限制单位时间内能发多少请求
- 防止某个用户"霸占"所有资源
- 本项目用 **Token Bucket（令牌桶）** 算法：
  - 有一个桶，里面装令牌
  - 每处理一个请求，消耗一个令牌
  - 令牌每秒自动补充（比如每秒补充 10 个）
  - 没令牌了 → 请求被拒绝（HTTP 429 Too Many Requests）

**两层限流**：
| 级别 | 限制 | 防止什么 |
|------|------|---------|
| 全局 | 每秒 10 个请求 | 单个客户端打崩整个系统 |
| 每后端 | 每秒 10 个请求 | 单个后端被请求淹没 |

---

# 📊 第五部分：可观测性科普

## 21. 什么是可观测性（Observability）？

- 简单说 = **能看到系统里面在发生什么**
- 三大支柱：

| 支柱 | 是什么 | 本项目的实现 |
|------|--------|-------------|
| **日志（Logs）** | 事件记录 | Python logging 模块（带时间戳） |
| **指标（Metrics）** | 数值统计 | TTFT、TPS、错误率等 |
| **追踪（Tracing）** | 请求链路 | OpenTelemetry（可选） |

## 22. 什么是 Prometheus？

- **Prometheus** = 开源监控系统和时序数据库
- 定期"抓取"各个服务的指标数据
- 有强大的查询语言（PromQL）
- 本项目 Scheduler 在 `:9110` 端口暴露 Prometheus 指标
- K3S 集群中的 Prometheus 自动采集这些指标

## 23. 什么是 Grafana Dashboard？

- **Grafana** = 可视化仪表盘工具
- 把 Prometheus 采集的指标用漂亮的图表展示出来
- 本项目提供完整的 Dashboard JSON 配置（`dashboard-v2.json`）
- 包含：
  - 集群节点数
  - Scheduler 运行时间
  - Ollama 服务状态
  - 后端 TTFT / TPS 趋势

---

# 🧪 第六部分：压测数据解读

## 24. 什么是 TTFT 和 TPS？

| 缩写 | 全称 | 中文 | 含义 | 好还是坏 |
|------|------|------|------|---------|
| TTFT | Time To First Token | 首 Token 延迟 | 从发请求到收到第一个字的时间 | **越低越好** |
| TPS / Throughput | Tokens Per Second | 每秒 Token 数 | 每秒能生成多少个字 | **越高越好** |
| TPOT | Time Per Output Token | 每 Token 生成时间 | 生成每个字需要多少毫秒 | **越低越好** |

## 25. Ollama vs vLLM 性能对比

这是本项目的核心对比——**CPU 推理 vs GPU 推理**：

| 对比项 | Ollama (CPU) | vLLM (GPU) |
|--------|-------------|------------|
| 模型大小 | qwen2.5:0.5b (5亿参数) | Qwen2.5-7B-Instruct (70亿参数) |
| 硬件 | ECS 阿里云 2C4G | AutoDL RTX 4090 24GB |
| 总延迟 | 7.398 秒 | 0.236 秒 |
| TTFT | ~352ms | 279ms |
| TPS | 9.4 tok/s | 34.5 tok/s |
| 速度对比 | 基准 | **快 31 倍** |

### 为什么 GPU 比 CPU 快这么多？

**核心原因**：AI 推理是大量的矩阵乘法运算，这种计算非常适合**并行处理**。

- **CPU**：有 4~16 个核心，每个核心很强，但数量少——适合"单线程任务"
- **GPU**：有数千个核心（RTX 4090 有 16384 个 CUDA 核心），每个核心较弱，但加在一起无敌——适合"并行计算任务"

打个比方：
- CPU 像 4 个教授——每个都很聪明，但人数少
- GPU 像 10000 个小学生——每个人只会做简单计算，但 10000 人一起算就飞快

AI 推理 = 让 10000 个人同时做简单计算 → GPU 完胜

**更有意思的是**：即便 vLLM 跑的模型比 Ollama **大 14 倍**（7B 参数 vs 0.5B 参数），GPU 的总延迟仍然只有 CPU 的 1/31。

也就是说：**GPU 用一个比 CPU 大 14 倍的模型，速度还快了 31 倍。**

这就是为什么现在的 AI 服务都需要 GPU。

---

# 🏭 第七部分：多节点生产部署科普

## 26. 当前生产架构全景

```
                    ┌─────────────────────────────────────────┐
                    │          Tailscale 组网                   │
                    │  把不同网络的电脑连成"局域网"               │
                    └──────┬──────────────────┬───────────────┘
                           │                  │
              ┌────────────▼──────┐  ┌────────▼────────────────┐
              │  ECS 阿里云       │  │  本地 VM (WSL2)         │
              │  K3S Master       │  │  K3S Worker             │
              │  100.88.70.19     │  │  192.168.x.x            │
              │  2C4G             │  │  2C4G                    │
              │                   │  │                          │
              │  Ollama :31434    │  │  SSH 隧道 :6006         │
              │  Prometheus+Graf  │  │  ← AutoDL vLLM          │
              │  ArgoCD           │  │                          │
              └───────────────────┘  └──────────────────────────┘
                                                 │
                                    ┌────────────▼──────────┐
                                    │  AutoDL RTX 4090      │
                                    │  20核 90GB 内存       │
                                    │  vLLM 0.23.0          │
                                    │  Qwen2.5-7B 推理      │
                                    └───────────────────────┘
```

### 各节点职责

| 节点 | 位置 | 配置 | 运行什么 |
|------|------|------|---------|
| ECS Master | 阿里云 | 2C4G | K3S Master, Ollama, Prometheus, Grafana, ArgoCD |
| VM Worker | 本地 WSL2 | 2C4G | K3S Worker, SSH 隧道代理 |
| AutoDL GPU | 云端 | RTX 4090, 20C, 90GB | vLLM 0.23.0, Qwen2.5-7B |

### 推理引擎对比

| 特性 | Ollama (K3S) | vLLM (AutoDL) |
|------|-------------|---------------|
| 引擎类型 | Ollama 0.30+ | vLLM 0.23.0 |
| 模型 | qwen2.5:0.5b, nomic-embed-text | Qwen2.5-7B-Instruct |
| 硬件 | CPU only (2C4G) | RTX 4090 24GB |
| API 格式 | Ollama 原生 API | OpenAI 兼容 API |
| 路由权重 | 1.5 | 3.0 |
| 连接方式 | K3S Service NodePort :31434 | SSH 隧道 localhost:6006 |

## 27. 什么是双引擎推理？

**双引擎** = 同时使用两种不同的推理引擎，发挥各自优势：

- **Ollama**：轻量级，部署简单，适合小模型和日常开发调试
- **vLLM**：高性能，支持连续批处理（continuous batching），适合大模型生产服务

调度器根据模型类型自动路由：
- 请求 `qwen2.5:0.5b` → 路由到 Ollama K3S
- 请求 `Qwen2.5-7B-Instruct` → 路由到 vLLM AutoDL

## 28. Prometheus + Grafana 监控怎么工作？

```
Scheduler :9110 → Prometheus (每15秒采集一次) → Grafana (可视化)
                         ↓
                  AlertManager (告警)
                         ↓
                   WeChat Bot (消息推送)
```

- Scheduler 在 `:9110` 暴露指标端点
- Prometheus 通过 ServiceMonitor 自动发现并采集
- Grafana 用 dashboard-v2.json 展示仪表盘
- AlertManager 根据告警规则推送通知到微信

---

# 🔧 第八部分：配置与部署科普

## 29. 生产环境后端配置

```yaml
backends:
  - id: "ollama-k3s"
    name: "Ollama K3S Cluster"
    url: "http://100.88.70.19:31434"   # 阿里云 ECS
    engine: "ollama"
    weight: 1.5
    models:
      - "qwen2.5:0.5b"

  - id: "vllm-autodl-gpu"
    name: "vLLM AutoDL RTX4090"
    url: "http://localhost:6006"         # SSH 隧道
    engine: "openai"
    weight: 3.0
    models:
      - "Qwen2.5-7B-Instruct"
```

## 30. 怎么启动整个生产系统？

```
┌────────────────────────────────────────────────────────────────┐
│ ECS (阿里云):                                                  │
│ 确保 K3S 集群正常运行，Ollama StatefulSet 已部署                │
│ Prometheus + Grafana 已安装                                     │
├────────────────────────────────────────────────────────────────┤
│ VM (本地 WSL2):                                                │
│ 建立 SSH 隧道连接到 AutoDL:                                     │
│ ssh -o ServerAliveInterval=60 -L 6006:localhost:8000 root@...  │
├────────────────────────────────────────────────────────────────┤
│ VM (本地 WSL2) - 启动 Scheduler:                                │
│ python gateway_k3s.py                                          │
│ → Scheduler 在 :9000                                           │
│ → Metrics 在 :9110                                             │
├────────────────────────────────────────────────────────────────┤
│ 浏览器验证:                                                     │
│ curl http://localhost:9000/health                              │
│ curl http://localhost:9000/v1/backends                          │
│ curl http://localhost:9110/metrics                              │
└────────────────────────────────────────────────────────────────┘
```

---

# 🧪 第九部分：动手实践指南（小白复现步骤）

## 需要的硬件

| 最低要求 | 推荐配置 |
|---------|---------|
| 任何有 GPU 的电脑 | NVIDIA RTX 4060 或更高 |
| 8GB 显存 | 16GB+ 显存 |
| Windows 11 或 Linux | 同左 |
| 50GB 磁盘空间 | 100GB+ SSD |

## 步骤 1：安装 Python 3.11+

1. 去 https://www.python.org/downloads/ 下载 Python 3.11 或更高版本
2. 安装时**务必勾选** "Add Python to PATH"
3. 验证：打开终端（cmd/powershell），输入 `python --version`，看到版本号就对了

## 步骤 2：安装 Ollama

1. 去 https://ollama.com/download 下载安装包
2. 安装后打开终端，输入 `ollama pull qwen2.5:0.5b` 下载小模型
3. 输入 `ollama pull qwen2.5:1.5b` 下载稍大的模型
4. 验证：输入 `ollama list` 能看到已下载的模型列表

## 步骤 3：下载本项目代码

```powershell
git clone https://github.com/你的用户名/aimodel-scheduler.git
cd aimodel-scheduler
```

## 步骤 4：安装依赖

```powershell
pip install -r requirements.txt
```

## 步骤 5：启动后端和调度器

**本地单机模式（不需要 K3S 和云 GPU）：**

**终端 1：启动 Ollama（默认端口 11434）**
```powershell
ollama serve
```
看到 `Listening on 127.0.0.1:11434` 说明成功

---

**终端 2：启动 Scheduler（统一入口）**
```powershell
cd aimodel-scheduler\02-unified-api
python unified_gateway.py
```
看到 `Unified API running on http://localhost:9000` 说明成功

---

**可选：仪表盘**
```powershell
cd aimodel-scheduler\04-observability
python dashboard.py
```
浏览器打开 `http://localhost:9010` 就能看到实时状态

## 步骤 6：发送你的第一个请求

```powershell
curl -X POST http://localhost:9000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer test-key" `
  -d '{"model":"qwen2.5:0.5b","messages":[{"role":"user","content":"你好"}]}'
```

**成功时你会看到类似**：
```json
{
  "model": "qwen2.5:0.5b",
  "choices": [
    {"message": {"content": "你好！有什么可以帮助你的吗？"}}
  ]
}
```

**响应头部会显示路由信息**：
```
X-Routed-Backend: ollama-k3s     ← 这个请求发给了谁
X-Routing-Strategy: model_aware  ← 用了什么策略
```

## 步骤 7：运行压测（看看系统能承受多大压力）

```powershell
cd aimodel-scheduler\03-scheduler-benchmark

# 调度器压力测试（1/2/4/8/16 并发梯度）
python scheduler_stress_test.py

# 多后端对比测试
python cross_backend_compare.py
```

---

# 💡 第十部分：常见问题（小白 FAQ）

## Q1：我只有一台电脑，能跑这个项目吗？

**能。** 本项目设计就是在**单机上**开始开发验证的。你只需要：
1. 启动 Ollama
2. 运行 Scheduler
3. 测试路由功能

生产环境的多节点部署是可选的升级路径。

## Q2：我没有云 GPU，怎么测试 vLLM 后端？

Scheduler 自带一个 `mock_backend.py`，它模拟 vLLM 的行为：
- TTFT 30~80ms（模拟云端低延迟）
- TPOT 5ms/字符
- 支持多个模型

启动方式：
```powershell
cd 01-scheduler-core
python mock_backend.py
# → Mock vLLM 在 :11436
```

## Q3：什么是"响应式"返回和"流式"返回？

**响应式（非流式）**：
```json
{"choices": [{"message": {"content": "你好！今天天气很好，有什么可以帮你的？"}}]}
```
→ AI 全部想好了，一次性给你，你**等待时间长**但**拿到完整结果**

**流式（SSE）**：
```
data: {"choices":[{"delta":{"content":"你"}}]}
data: {"choices":[{"delta":{"content":"好"}}]}
data: {"choices":[{"delta":{"content":"！"}}]}
```
→ AI 一个字一个字给你，你**立刻看到第一个字**，但**逐个接收**

## Q4：报错 "Connection refused" 怎么办？

可能原因：
1. 后端没启动（检查 Ollama 是否在运行）
2. 端口配错了（检查 `scheduler_config.yaml` 的 url）
3. SSH 隧道断了（需要重建）

**解决**：
```powershell
# 检查端口状态
netstat -ano | findstr :11434

# 重启 Ollama
ollama serve

# 重建 SSH 隧道（如果用了 AutoDL）
ssh -o ServerAliveInterval=60 -L 6006:localhost:8000 root@...
```

## Q5：为什么我要学这个项目？学了有什么用？

| 你能学到 | 应用场景 |
|---------|---------|
| AI 模型部署和推理 | 了解 AI 从训练到上线的完整流程 |
| 微服务架构设计 | 网关、调度、负载均衡、熔断等企业级模式 |
| 异步编程（asyncio） | 高并发网络编程 |
| 容器化和云原生（K3S） | 现代 DevOps 实践 |
| 可观测性体系 | 监控、告警、仪表盘 |
| 多节点集群运维 | Tailscale 组网、SSH 隧道、跨网络通信 |

**一句话总结**：这是一个**缩小版的企业级 AI 推理调度系统**，掌握了它，你就掌握了 AI 基础设施的核心架构设计思路。

---

# 📚 第十一部分：术语速查表

| 术语 | 英文 | 一句话解释 |
|------|------|-----------|
| 推理 | Inference | AI 用学到的知识回答问题 |
| 模型 | Model | 训练好的 AI"大脑" |
| 参数 | Parameter | 模型的"知识量"，越多越聪明 |
| GPU | 显卡 | AI 计算的加速器 |
| 显存 | VRAM | GPU 的内存，决定能跑多大模型 |
| 端口 | Port | 电脑上的"门牌号" |
| HTTP | 超文本传输协议 | 电脑之间通信的"语言" |
| API | 应用程序接口 | 程序之间调用的"接口" |
| JSON | 数据格式 | 电脑之间传数据的"格式" |
| SSE | 服务器推送事件 | AI 一个字一个字往外蹦的技术 |
| 负载均衡 | Load Balancing | 把请求均匀分配给各个后端 |
| 断路器 | Circuit Breaker | 保护后端不被请求淹死的机制 |
| 限流 | Rate Limiting | 限制单位时间内的请求数 |
| 鉴权 | Authentication | 验证"你是谁" |
| 路由 | Routing | 决定请求发给哪个后端 |
| 健康检查 | Health Check | 定期检查后端是否活着 |
| 延迟 | Latency | 从请求到响应的时间 |
| 吞吐量 | Throughput | 单位时间能处理多少请求 |
| TTFT | Time To First Token | 首 token 延迟（越低越好） |
| TPS | Tokens Per Second | 每秒 token 数（越高越好） |
| K3S | 轻量 Kubernetes | 容器编排平台（精简版） |
| HPA | 自动扩缩容 | 负载高时自动加机器 |
| GitOps | Git 运维 | 用 Git 管理配置和部署 |
| Tailscale | 组网工具 | 跨网络节点直连 |
| SSH 隧道 | SSH Tunnel | 加密通道连接远程服务 |
| Prometheus | 监控系统 | 采集和查询指标的框架 |
| Grafana | 可视化工具 | 指标展示仪表盘 |

---

> **最后的话**：这个项目虽然看起来术语很多，但本质上就是"一个聪明的总机，连接多个 AI 服务员"。不要被术语吓到——每个术语背后都是一个简单的生活类比。动手跟着实践指南的步骤走一遍，你就全明白了！