# 🚀 SRE Lab — K3S 高并发 AI 推理平台

> **项目驱动 · 练中学** — 从零构建生产级云原生 AI 推理平台

[![K3S](https://img.shields.io/badge/K3S-v1.31-blue)](https://k3s.io/)
[![Kubernetes](https://img.shields.io/badge/K8s-Native-326ce5)](https://kubernetes.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-ef7b4d)](https://argo-cd.readthedocs.io/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 📖 项目简介

本项目是一个**从零开始**构建的云原生 AI 推理平台，采用 **K3S 轻量级 Kubernetes** 作为基座，集成了 Ollama 大模型推理引擎 + Open WebUI 前端，覆盖了 **高可用、可观测性、自动化运维、安全** 等生产级核心能力。

**学习路径**：基础设施 → 应用部署 → 可观测性 → GitOps → 自动化弹性 → 压测验证

---

## 🏗️ 架构总览

```
                              ┌──────────────────────────────────────────┐
                              │            🌐 Internet / 用户              │
                              └──────────────┬───────────────────────────┘
                                             │
                              ┌──────────────▼───────────────────────────┐
                              │         Traefik Ingress Controller        │
                              │  (集群统一入口 · 路由 · SSL · 中间件)     │
                              └──────┬──────────────┬──────────────┬─────┘
                                     │              │              │
                    ┌────────────────▼──┐  ┌────────▼────────┐  ┌─▼──────────────┐
                    │   Open WebUI     │  │   Grafana       │  │  Prometheus    │
                    │   (AI Chat UI)   │  │   (可视化看板)  │  │  (指标采集)    │
                    └────────┬─────────┘  └─────────────────┘  └────────────────┘
                             │
                    ┌────────▼─────────┐
                    │  Ollama Service  │
                    │  (ClusterIP)     │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐     ┌──────────────────────────────┐
                    │  Ollama          │     │  可观测性栈                   │
                    │  StatefulSet     │     │  ┌──────────┐ ┌───────────┐  │
                    │  + PVC 持久化    │     │  │  Loki    │ │ Promtail  │  │
                    │  + HPA 自动扩缩  │     │  │(日志聚合)│ │(日志采集) │  │
                    │  + PDB 优雅终止  │     │  └──────────┘ └───────────┘  │
                    └──────────────────┘     └──────────────────────────────┘
```
```
                          ┌──────────────────────────────────────┐
                          │            GitOps 层                  │
                          │  ┌────────────────────────────────┐  │
                          │  │  ArgoCD → GitHub (sre-lab)      │  │
                          │  │  Auto Sync · Self Heal          │  │
                          │  │  Sealed Secrets 加密存储        │  │
                          │  └────────────────────────────────┘  │
                          └──────────────────────────────────────┘
```
```
                          ┌──────────────────────────────────────┐
                          │         告警通道                       │
                          │  AlertManager → WeChat Bot            │
                          │  (CPU/Mem/Disk/Pod 异常实时告警)       │
                          └──────────────────────────────────────┘
```

---

## 📁 目录结构

```
sre-lab/
├── README.md                            # ← 本文件 (项目总览)
│
├── 01-baseline-manifests/               # [阶段1] 手工 kubectl apply 清单
│   ├── README.md                        #     基线部署指南
│   ├── cloud-native-ai/                 #     AI 推理平台核心
│   │   ├── namespace.yaml               #       ai-platform 命名空间
│   │   ├── ollama-stack.yaml            #       Ollama StatefulSet + Headless Service + PVC
│   │   ├── open-webui.yaml              #       Open WebUI Deployment + PVC
│   │   ├── ingress.yaml                 #       Traefik Ingress 路由
│   │   ├── hpa.yaml                     #       HPA 自动扩缩容
│   │   └── pdb.yaml                     #       PDB 优雅终止
│   └── monitoring-stack/                #     监控告警体系
│       ├── prometheus-ingress.yaml      #       Prometheus Ingress
│       ├── grafana-ingress.yaml         #       Grafana Ingress
│       ├── cluster-alerts.yaml          #       集群级告警规则
│       ├── k3s-alert-patches.yaml       #       K3S 特定告警修复
│       ├── ollama-exporter.yaml         #       Ollama 指标导出
│       ├── ollama-monitor-fix.yaml      #       Ollama 监控面板
│       ├── nginx-monitor.yaml           #       Nginx 监控面板
│       └── wechat-adapter.yaml          #       WeChat 告警适配器
│
├── 02-gitops-production/                # [阶段2] ArgoCD GitOps 生产配置
│   ├── bootstrap/                       #     ArgoCD App of Apps 入口
│   │   ├── root-app.yaml               #       根应用 (加载所有子应用)
│   │   ├── ai-platform-app.yaml        #       AI 平台子应用
│   │   ├── monitoring-app.yaml         #       监控栈子应用
│   │   ├── loki-app.yaml               #       Loki 日志聚合
│   │   ├── promtail-app.yaml           #       Promtail 日志采集
│   │   ├── nginx-app.yaml              #       Nginx 示例应用
│   │   └── sealed-secrets-app.yaml     #       Sealed Secrets 加密管理
│   ├── apps/                           #     各应用 K8s 资源清单
│   │   ├── ai-platform/                #       (同 baseline 结构 + 增强)
│   │   ├── loki/                       #       Loki 部署
│   │   ├── promtail/                   #       Promtail DaemonSet
│   │   ├── nginx-demo/                 #       Nginx + Middleware 示例
│   │   └── sealed-secrets/             #       Sealed Secrets 控制器 + 使用指南
│   └── monitoring/                     #     生产监控配置 (kube-prometheus-stack 余量)
│
├── 03-benchmark/                        # [阶段3] 性能压测
│   ├── README.md                        #     压测指南
│   ├── locustfile.py                    #     Locust 流式压测 (推荐, 支持 TTPT/TPOT)
│   └── k6-script.js                     #     k6 轻量压测
│
├── cluster-health-check.sh              # 集群健康检查脚本
└── .gitignore                           # Git 忽略规则
```

---

## 🎯 学习路线 & 里程碑

| 序号 | 模块 | 核心技术 | 状态 | 验证方式 |
|------|------|---------|------|---------|
| 01 | **基础设施搭建** | K3S 安装 · kubectl · 节点管理 | ✅ | `kubectl get nodes` |
| 02 | **AI 推理部署** | Ollama StatefulSet · PVC · 探针 | ✅ | Web UI 访问 + 模型问答 |
| 03 | **Traefik 网关** | Ingress · Middleware · StripPrefix | ✅ | 统一域名访问多服务 |
| 04 | **监控系统** | kube-prometheus-stack · Grafana | ✅ | Grafana 看板查看集群指标 |
| 05 | **告警通知** | AlertManager · WeChat Bot | ✅ | WeChat 收到告警消息 |
| 06 | **日志系统 (PLG)** | Promtail · Loki · Grafana | ✅ | Grafana Explore 查询日志 |
| 07 | **GitOps** | ArgoCD · App of Apps | ✅ | GitHub 推送自动同步到集群 |
| 08 | **密码管理** | Sealed Secrets | ✅ | Git 中存储加密 Secret |
| 09 | **自动扩缩容** | HPA (CPU/Memory) · Scale Behavior | 🆕 | `kubectl get hpa` 验证状态 |
| 10 | **优雅终止** | PodDisruptionBudget | 🆕 | 节点驱逐时 Pod 不中断 |
| 11 | **压力测试** | Locust / k6 · TTPT/TPOT | 🆕 | 压测报告 + HPA 触发验证 |

---

## 🚦 快速开始

### 前置条件

- K3S 集群 (≥1 节点)
- `kubectl` 已配置
- `helm` 已安装
- Go 语言环境 (可选，用于 k6 压测)

### 1. 克隆仓库

```bash
git clone git@github.com:fei232401/sre-lab.git
cd sre-lab
```

### 2. 基线部署 (手工模式)

```bash
# AI 推理平台
kubectl apply -f 01-baseline-manifests/cloud-native-ai/

# 监控栈 (需先安装 kube-prometheus-stack helm chart)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

kubectl apply -f 01-baseline-manifests/monitoring-stack/

# 拉取 Qwen 模型
kubectl exec -n ai-platform statefulset/ollama -- ollama pull qwen2.5:1.5b
```

### 3. GitOps 部署 (生产模式)

```bash
# 安装 ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 部署根应用 (自动拉取所有子应用)
kubectl apply -f 02-gitops-production/bootstrap/root-app.yaml

# 检查同步状态
kubectl get apps -n argocd
```

### 4. Sealed Secrets 加密

```bash
# 安装 kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.3/kubeseal-0.26.3-linux-amd64.tar.gz
tar xzf kubeseal-0.26.3-linux-amd64.tar.gz kubeseal && sudo mv kubeseal /usr/local/bin/

# 创建加密 Secret
kubectl create secret generic my-secret --from-literal=api-key=xxx \
  -n ai-platform --dry-run=client -o yaml | kubeseal -o yaml > sealed-secret.yaml

# 提交到 Git，ArgoCD 自动部署
```

### 5. 压测启动

```bash
# Locust Web UI (推荐)
pip install locust
cd 03-benchmark
locust -f locustfile.py --host=http://<TRAEFIK_IP>:<PORT>

# k6 命令行快速测试
k6 run k6-script.js --env HOST=http://<TRAEFIK_IP>:<PORT>
```

---

## 🔧 技术栈详解

### AI 推理引擎

| 组件 | 版本 | 用途 |
|------|------|------|
| **Ollama** | latest | 本地 LLM 推理服务，支持 Qwen 等开源模型 |
| **Open WebUI** | main | 类 ChatGPT 的 Web 聊天界面 |
| **Qwen 2.5** | 0.5B~7B | 阿里通义千问开源模型 |

**关键设计**：
- StatefulSet + Headless Service 保证网络标识稳定
- PVC 持久化模型文件，Pod 重启无需重新拉取
- Liveness/Readiness/Startup 三重探针保障服务可用性

### 网络层

| 组件 | 用途 |
|------|------|
| **Traefik** | K3S 内置 Ingress Controller |
| **ClusterIP** | 内网统一通信，禁止外部直连 |
| **Middleware** | StripPrefix 等路由中间件 |
| **Ingress** | 统一入口路由分发 |

**端口映射收束方案**：
```
外部请求 → Traefik (80) → Ingress 路由匹配：
  /                → open-webui-service:8080
  /nginx           → my-nginx-svc:80
  /grafana         → kps-grafana:80
  /prometheus      → kps-prometheus:9090
```

### 可观测性

| 组件 | 类型 | 用途 |
|------|------|------|
| **Prometheus** | 指标采集 | 集群/应用指标 TSDB 存储 |
| **Grafana** | 可视化 | 仪表盘 + 日志查询 + 告警管理 |
| **AlertManager** | 告警路由 | 告警分组/抑制/静默 |
| **Loki** | 日志聚合 | 轻量级日志存储 (类 Prometheus 标签) |
| **Promtail** | 日志采集 | DaemonSet 采集容器日志 |

### 自动化运维

| 组件 | 用途 |
|------|------|
| **ArgoCD** | GitOps CD 工具，Git 状态 → 集群状态 |
| **HPA** | 基于 CPU/Memory 的 Pod 自动扩缩容 |
| **PDB** | 滚动更新/驱逐时保证最小可用副本 |
| **Sealed Secrets** | Git 中安全存储加密 Secret |

---

## 📊 关键指标

### HPA 扩缩容策略

| 资源 | Ollama | Open WebUI |
|------|--------|------------|
| Min Replicas | 1 | 1 |
| Max Replicas | 3 | 5 |
| CPU 阈值 | 70% | 60% |
| Memory 阈值 | 80% | 75% |
| 扩容冷却 | 60s | 30s |
| 缩容冷却 | 300s | 300s |

### 压测核心指标 (TTPT / TPOT)

```
TTPT (Time To First Token)   = 请求发出 → 第一个 token 生成  (ms)
TPOT (Time Per Output Token) = 每个 token 平均生成时间        (ms)
Throughput                   = 每秒请求数 (RPS)
P50 / P90 / P99              = 百分位延迟
```

---

## 📋 验证清单

部署完成后，逐项确认：

- [ ] `kubectl get nodes` — 所有节点 Ready
- [ ] `kubectl get pods -n ai-platform` — Ollama + Open WebUI Running
- [ ] `kubectl get pods -n logging` — Loki + Promtail Running
- [ ] `kubectl get apps -n argocd` — 全部 Synced & Healthy
- [ ] `kubectl get hpa -n ai-platform` — HPA 状态正常
- [ ] `kubectl get pdb -n ai-platform` — PDB 已创建
- [ ] 浏览器访问 Traefik IP → Open WebUI 正常聊天
- [ ] 浏览器访问 `/grafana` → Grafana 登录
- [ ] WeChat 收到测试告警消息
- [ ] ArgoCD UI 查看同步状态
- [ ] 压测后 HPA 自动触发扩容

---

## 🔐 安全最佳实践

1. **Sealed Secrets** 加密所有密钥后存入 Git
2. **ClusterIP** 为默认服务类型，禁止 NodePort/LoadBalancer 外露
3. **.gitignore** 排除 `.key`, `.pem`, `secrets/` 明文文件
4. **RBAC** 最小权限原则 (Promtail 仅读取 Pod 和日志)
5. **NetworkPolicy** 建议后续添加 Pod 间网络隔离

---

## 🎓 致谢 & 参考

- [K3S 官方文档](https://docs.k3s.io/)
- [Ollama 官方文档](https://ollama.com/)
- [ArgoCD 官方文档](https://argo-cd.readthedocs.io/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts)
- [Grafana Loki](https://grafana.com/docs/loki/latest/)

---

> 💡 **练中学，学中练** — 每个模块都配有可验证的输出，动手即理解。