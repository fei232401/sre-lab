# 🚀 SRE Lab — GitHub 仓库总览

[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![K3S](https://img.shields.io/badge/K3S-v1.31-blue)](https://k3s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-ef7b4d)](https://argo-cd.readthedocs.io/)

---

## 📁 仓库目录结构

```
sre-lab/                                   # ⭐ 仓库根目录
│                                           #    git@github.com:fei232401/sre-lab.git
├── .gitignore
├── README.md                               # ← 本文件
├── LICENSE                                 # MIT
│
├── 📁 sre-lab-gitops/                      # 🚨 SRE Lab — ArgoCD 工作区
│   ├── 📁 production/                      # ⚠️ ArgoCD GitOps 生产配置（原 02-gitops-production）
│   │   ├── 📁 bootstrap/                   #     App of Apps 入口（7个 Application YAML）
│   │   │   ├── root-app.yaml               #     → 根应用，加载所有子应用
│   │   │   ├── ai-platform-app.yaml        #     → AI 推理平台
│   │   │   ├── monitoring-app.yaml         #     → 监控栈（Prometheus/Grafana）
│   │   │   ├── loki-app.yaml               #     → Loki 日志聚合
│   │   │   ├── promtail-app.yaml           #     → Promtail 日志采集
│   │   │   ├── nginx-app.yaml              #     → Nginx 示例
│   │   │   └── sealed-secrets-app.yaml     #     → Sealed Secrets 加密
│   │   ├── 📁 apps/                        #     各应用 K8s 清单
│   │   │   ├── ai-platform/                #     Ollama + Open WebUI
│   │   │   ├── loki/                       #     Loki 部署
│   │   │   ├── nginx-demo/                 #     Nginx + Middleware
│   │   │   ├── promtail/                   #     Promtail DaemonSet
│   │   │   └── sealed-secrets/             #     Sealed Secrets 控制器
│   │   └── 📁 monitoring/                  #     监控告警规则
│   │
│   ├── 📁 manifests/                       #     基线 K8s 清单（原 01-baseline-manifests）
│   │   ├── cloud-native-ai/                #     AI 推理平台核心
│   │   └── monitoring-stack/               #     监控告警体系
│   │
│   ├── 📁 benchmark/                       #     性能压测（原 03-benchmark）
│   │   ├── locustfile.py                   #     Locust 流式压测
│   │   └── k6-script.js                    #     k6 轻量压测
│   │
│   ├── 📁 k3s-ai-platform/                 #     K3S AI 平台项目
│   │   ├── 📁 docs/                        #     平台文档（架构/部署/运维）
│   │   ├── 📁 environments/prod/           #     生产环境配置
│   │   ├── 📁 reference/                   #     参考清单副本
│   │   ├── 📁 scripts/                     #     运维脚本
│   │   └── 📁 tools/benchmark/             #     压测工具
│   │
│   ├── 📁 scripts/                         #     通用运维脚本
│   │   └── cluster-health-check.sh         #     集群健康检查
│   │
│   ├── 📁 grafana/                         #     Grafana 仪表盘
│   │   └── dashboard-v2.json
│   │
│   └── 📁 cluster-config/                  #     集群配置备份
│       ├── k3s-full-backup.tar.gz
│       └── kubeconfig-vm.yaml
│
├── 📁 ai-model-scheduler/                  # AI Model Scheduler（异构调度层）
│   ├── 01-scheduler-core/                  #     调度器核心
│   ├── 02-unified-api/                     #     统一 API 网关
│   ├── 03-scheduler-benchmark/             #     压测
│   ├── 04-observability/                   #     可观测性
│   ├── docs/                               #     文档
│   └── README.md
│
├── 📁 ai-infra-gateway/                    # AI Infra Gateway（Windows 裸金属推理网关）
│   ├── 01-gateway-server/                  #     FastAPI 推理网关
│   ├── 02-dashboard/                       #     GPU 实时监控
│   ├── 03-benchmark/                       #     Ollama 本地压测
│   ├── 04-infrastructure/                  #     基础设施 + Prometheus Exporter
│   ├── 05-autodl-benchmark/                #     vLLM 云端压测
│   ├── docs/                               #     项目文档
│   └── README.md
│
├── 📁 resources/                           # 资料归档
│   ├── 📁 training/                        #     学习培训资料
│   └── 📁 deliverables/                    #     项目交付文档
│
├── 📁 docs/                                # 项目文档与日志
│   └── AI_INFRA_DEVELOPMENT_LOG.md
│
└── 📁 backups/                             # 原始备份归档
    ├── 📁 backup/                          #     K8s 资源快照
    ├── 📁 scheduler-deploy/                #     调度器部署包
    └── 📁 workingspace/                    #     工作区完整副本
```

---

## 🚨 ArgoCD 工作区说明

**`sre-lab-gitops/production/`** 目录被 ArgoCD 监听，通过同一仓库内的 YAML 自动同步到 K3S 集群。

### ArgoCD Application 路径映射

| 原始路径 | 新路径 |
|---------|--------|
| `02-gitops-production/bootstrap` | `sre-lab-gitops/production/bootstrap` |
| `02-gitops-production/apps/ai-platform` | `sre-lab-gitops/production/apps/ai-platform` |
| `02-gitops-production/apps/loki` | `sre-lab-gitops/production/apps/loki` |
| `02-gitops-production/apps/nginx-demo` | `sre-lab-gitops/production/apps/nginx-demo` |
| `02-gitops-production/apps/promtail` | `sre-lab-gitops/production/apps/promtail` |
| `02-gitops-production/apps/sealed-secrets` | `sre-lab-gitops/production/apps/sealed-secrets` |
| `02-gitops-production/monitoring` | `sre-lab-gitops/production/monitoring` |

> 仓库内的所有 bootstrap YAML **已经同步更新为新路径**。如果在 ArgoCD 界面上之前配置过 Application，需要手动更新其 `spec.source.path` 字段。

---

## 📦 子项目说明

| 项目 | 路径 | 说明 |
|------|------|------|
| **SRE Lab GitOps** | `sre-lab-gitops/` | K3S 生产部署全套配置（K8s 清单 + ArgoCD + 压测 + 监控） |
| **AI Model Scheduler** | `ai-model-scheduler/` | 统一异构调度层，连接 Gateway + SRE-LAB + vLLM |
| **AI Infra Gateway** | `ai-infra-gateway/` | Windows 裸金属推理网关，FastAPI + Ollama + Prometheus |

---

## 🔗 相关链接

- **GitHub**: `git@github.com:fei232401/sre-lab.git`
- **SRE Lab 原始 README**: 详见 `sre-lab-gitops/k3s-ai-platform/README.md`
- **AI Infra Gateway**: 详见 `ai-infra-gateway/README.md`
- **AI Model Scheduler**: 详见 `ai-model-scheduler/README.md`

---

## 📄 License

MIT — see [LICENSE](./LICENSE) for details.