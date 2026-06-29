# 🚀 SRE Lab — K3S 高并发 AI 推理平台

> **项目驱动 · 练中学** — 从零构建生产级云原生 AI 推理平台

[![K3S](https://img.shields.io/badge/K3S-v1.31-blue)](https://k3s.io/)
[![Kubernetes](https://img.shields.io/badge/K8s-Native-326ce5)](https://kubernetes.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-ef7b4d)](https://argo-cd.readthedocs.io/)
[![Tailscale](https://img.shields.io/badge/Tailscale-Mesh-4912FF?logo=tailscale)](https://tailscale.com/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 📖 仓库简介

本仓库整合了 SRE Lab 的 GitOps 生产配置及相关子项目，包含以下内容：

- **sre-lab-gitops/** — SRE Lab K3S AI 推理平台的完整部署配置（含 ArgoCD 监听的生产目录）
- **ai-model-scheduler/** — AI Model Scheduler 统一异构调度层
- **ai-infra-gateway/** — AI Infra Gateway（Windows 裸金属推理网关）
- **resources/** — 学习资料与项目交付文档归档
- **docs/** — 项目文档与开发日志
- **backups/** — 原始备份归档（K8s 资源快照、工作区备份等）

---

## 📁 仓库目录结构

```
sre-lab/                                 # ⭐ GitHub 仓库根目录
│                                        #    git@github.com:fei232401/sre-lab.git
├── .gitignore
├── README.md                            # ← 本文件 (仓库总览)
│
├── sre-lab-gitops/                      # 🚨 ArgoCD 监听目录
│   ├── manifests/                       #     基线 K8s 清单 (原 01-baseline-manifests)
│   ├── production/                      # ⚠️ ArgoCD GitOps 生产配置 (原 02-gitops-production)
│   │   ├── bootstrap/                   #     ArgoCD App of Apps 入口
│   │   ├── apps/                        #     各应用 K8s 资源清单
│   │   └── monitoring/                  #     生产监控配置
│   ├── benchmark/                       #     性能压测 (原 03-benchmark)
│   ├── k3s-ai-platform/                 #     K3S AI 平台
│   ├── scripts/                         #     通用运维脚本
│   │   └── cluster-health-check.sh      #     集群健康检查脚本
│   ├── grafana/                         #     Grafana 仪表盘配置
│   │   └── dashboard-v2.json
│   └── cluster-config/                  #     集群配置备份 (kubeconfig 等)
│
├── ai-model-scheduler/                  # 🆕 AI Model Scheduler 子项目
│   ├── 01-scheduler-core/               #     调度器核心代码
│   ├── 02-unified-api/                  #     统一 API 网关
│   ├── 03-scheduler-benchmark/          #     调度器压力测试
│   ├── 04-observability/                #     可观测性
│   ├── docs/                            #     调度器文档
│   ├── README.md
│   └── requirements.txt
│
├── ai-infra-gateway/                    # 🆕 AI Infra Gateway 子项目
│   ├── 01-gateway-server/               #     Python 推理网关服务
│   ├── 02-dashboard/                    #     GPU 实时监控仪表盘
│   ├── 03-benchmark/                    #     Ollama 本地压测
│   ├── 04-infrastructure/               #     基础设施与 Prometheus Exporter
│   ├── 05-autodl-benchmark/             #     AutoDL 云端 vLLM 压测
│   ├── docs/                            #     网关项目文档
│   ├── CHANGELOG.md
│   └── README.md
│
├── resources/                           # 🆕 资料归档
│   ├── training/                        #     学习培训资料
│   │   ├── AI Infra 全链路专家教材 v1.docx
│   │   ├── AI Infra 生产环境实战进阶手册 v1.docx
│   │   └── ... (更多教程)
│   └── deliverables/                    #     项目交付文档
│       ├── AI Infra 项目整合建议.docx
│       ├── 基础功法.docx
│       └── 融合功法GLM.docx
│
├── docs/                                # 🆕 项目文档与日志
│   ├── AI_INFRA_DEVELOPMENT_LOG.md      #     开发日志
│   ├── ARCHITECT_AUDIT.md               #     架构审计
│   ├── FINAL_REPORT.md                  #     最终报告
│   ├── PROJECT_NARRATIVE.md             #     项目详细叙事
│   └── SRE_LAB_ARCHITECT_COMPARISON.md  #     架构对比分析
│
└── backups/                             # 🆕 原始备份归档
    ├── backup/                          #     K8s 资源备份 (yaml + txt)
    ├── scheduler-deploy/                #     调度器部署包
    └── workingspace/                    #     完整工作区快照
```

---

## ⚠️ ArgoCD 工作区说明

`sre-lab-gitops/production/` 目录被 **ArgoCD** 监听，**请勿直接修改**。

该目录对应原始仓库中的 `02-gitops-production/`，在重构后被移动到新路径。如果你使用 ArgoCD 管理，需要同步修改 Application 的 `spec.source.path` 配置：

| 原路径 | 新路径 |
|--------|--------|
| `02-gitops-production/bootstrap/` | `sre-lab-gitops/production/bootstrap/` |
| `02-gitops-production/apps/` | `sre-lab-gitops/production/apps/` |
| `02-gitops-production/monitoring/` | `sre-lab-gitops/production/monitoring/` |

需要修改 ArgoCD 中以下 Application 的 path 字段：
- `root-app`（根应用）
- `ai-platform-app`
- `monitoring-app`
- `loki-app`
- `promtail-app`
- `nginx-app`
- `sealed-secrets-app`

---

## 🚀 各项目本地启动

### SRE Lab GitOps（K3S 生产部署）

详见 `sre-lab-gitops/` 各子目录的 README。

### AI Model Scheduler

```bash
cd ai-model-scheduler
pip install -r requirements.txt
python 02-unified-api/unified_gateway.py
```

### AI Infra Gateway

```bash
cd ai-infra-gateway
pip install -r requirements.txt
python 01-gateway-server/start_gateway.py       # 启动网关 :8000
python 02-dashboard/dashboard_v2.py             # 启动仪表盘 :9090
```

---

## 🔗 相关链接

- **GitHub 仓库**: `git@github.com:fei232401/sre-lab.git`
- **SRE Lab 原始 README**: 详见 `sre-lab-gitops/` 子目录
- **AI Infra Gateway**: 详见 `ai-infra-gateway/README.md`
- **AI Model Scheduler**: 详见 `ai-model-scheduler/README.md`

---

## 🎓 学习路线（SRE Lab 核心）

| 序号 | 模块 | 核心技术 | 状态 |
|------|------|---------|------|
| 01 | 基础设施搭建 | K3S 安装 · kubectl · 节点管理 | ✅ |
| 02 | AI 推理部署 | Ollama StatefulSet · PVC · 探针 | ✅ |
| 03 | Traefik 网关 | Ingress · Middleware · StripPrefix | ✅ |
| 04 | 监控系统 | kube-prometheus-stack · Grafana | ✅ |
| 05 | 告警通知 | AlertManager · WeChat Bot | ✅ |
| 06 | 日志系统 (PLG) | Promtail · Loki · Grafana | ✅ |
| 07 | GitOps | ArgoCD · App of Apps | ✅ |
| 08 | 密码管理 | Sealed Secrets | ✅ |
| 09 | 多节点扩展 | K3S Agent · Tailscale 组网 | ✅ |
| 10 | ExternalService | 集群外服务发现 | ✅ |
| 11 | 自动扩缩容 | HPA · Scale Behavior | ✅ |
| 12 | 优雅终止 | PodDisruptionBudget | ✅ |
| 13 | 压力测试 | Locust / k6 · TTPT/TPOT | ✅ |

---

## 📄 License

MIT — see [LICENSE](./LICENSE) for details.