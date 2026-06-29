# K3S-AI-PLATFORM (Archived — Superseded by Parent SRE-LAB)

> ⚠️ **此目录为早期架构迭代存档**。当前生产级配置已迁移至父目录 `sre-lab/` 的 `01-baseline-manifests/` 和 `02-gitops-production/`。

基于K3S的高并发AI推理平台 - 云原生生产级架构

## 📋 项目概述

K3S-AI-PLATFORM 是一个基于K3S/kubernetes的高并发AI推理平台，采用云原生最佳实践，支持容器化、微服务架构、自动伸缩等特性。项目设计为支持多环境部署（dev/stag/prod），并预留了扩展接口以便后续集成更多项目。

## 🏗️ 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                     K3S Cluster                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │ AI Platform │  │ Monitoring  │  │    Logging      │   │
│  │   (Ollama)  │  │ (Prometheus │  │   (Loki +       │   │
│  │ + OpenWebUI │  │  + Grafana) │  │   Promtail)     │   │
│  └─────────────┘  └─────────────┘  └─────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │  Ingress    │  │   GitOps    │  │    Security     │   │
│  │  (Traefik)  │  │  (ArgoCD)   │  │ (Sealed Secret)│   │
│  └─────────────┘  └─────────────┘  └─────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │   Storage   │  │   Network   │  │    Scaling      │   │
│  │(Local-Path) │  │ (Traefik)   │  │     (HPA)      │   │
│  └─────────────┘  └─────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 📁 项目结构

```
k3s-ai-platform/
├── docs/                    # 架构设计文档
├── environments/            # 环境配置
│   ├── dev/                # 开发环境
│   ├── stag/               # 预发布环境
│   └── prod/               # 生产环境
│       ├── apps/           # 应用配置
│       ├── infrastructure/ # 基础设施
│       └── monitoring/     # 监控配置
├── scripts/                 # 运维脚本
├── tools/                  # 工具集
└── reference/              # 参考资料
```

## 🚀 快速开始

### 1. 环境准备
- K3S集群 (v1.29+)
- kubectl (v1.29+)
- Helm (v3.12+)
- 至少2核CPU，4GB内存

### 2. 安装步骤
```bash
# 克隆项目
git clone <repository>
cd k3s-ai-platform

# 部署基础环境
kubectl apply -f environments/prod/infrastructure/

# 部署监控栈
kubectl apply -f environments/prod/monitoring/

# 部署应用
kubectl apply -f environments/prod/apps/
```

### 3. 验证部署
```bash
# 运行健康检查
bash scripts/health-check.sh

# 检查Pod状态
kubectl get pods -A
```

## 📊 核心组件

### AI推理平台
- **Ollama**: 本地大语言模型推理引擎
- **OpenWebUI**: Web用户界面
- **HPA**: 自动扩缩容
- **PDB**: 优雅终止保护

### 监控告警
- **Prometheus**: 指标收集与存储
- **Grafana**: 可视化面板
- **AlertManager**: 告警管理
- **WeChat Adapter**: 微信告警推送

### 日志系统
- **Loki**: 日志存储与查询
- **Promtail**: 日志收集代理

### GitOps
- **ArgoCD**: 持续部署
- **Sealed Secrets**: 密钥管理

## 🔧 环境配置

### 开发环境 (dev)
- 单节点K3S
- 资源限制宽松
- 快速迭代

### 预发布环境 (stag)
- 多节点K3S
- 生产配置
- 完整测试

### 生产环境 (prod)
- 高可用K3S集群
- 严格资源限制
- 监控告警全开

## 📈 性能指标

- **TTFT** (Time To First Token): < 500ms
- **QPS**: 100+ requests/s
- **可用性**: 99.9%
- **HPA响应时间**: < 30s

## 🔐 安全特性

- Sealed Secrets加密存储
- RBAC权限控制
- NetworkPolicy网络隔离
- Pod安全策略

## 📝 许可证

MIT License

## 👥 维护者

- 项目发起人: 云原生学习者
- 架构设计: 云原生架构专家

## 🤝 贡献

欢迎提交Issue和Pull Request！

## 📚 相关文档

- [架构设计文档](./docs/architecture-design.md)
- [部署指南](./docs/deployment-guide.md)
- [监控配置说明](./docs/monitoring-guide.md)
- [运维手册](./docs/operations-manual.md)
