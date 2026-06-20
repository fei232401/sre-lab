#===============================================================================
# K3S AI Platform 环境配置说明
#===============================================================================

## 📋 环境概述

本项目采用三环境分离架构，支持从开发到生产的完整流程。

## 🏗️ 环境结构

```
environments/
├── dev/                    # 开发环境
│   ├── apps/              # 应用配置
│   ├── infrastructure/    # 基础设施
│   └── monitoring/        # 监控配置
│
├── stag/                  # 预发布环境
│   ├── apps/
│   ├── infrastructure/
│   └── monitoring/
│
└── prod/                  # 生产环境
    ├── apps/
    ├── infrastructure/
    └── monitoring/
```

## ⚙️ 环境配置差异

### 资源配置对比

| 组件 | 开发环境 | 预发布环境 | 生产环境 |
|------|---------|-----------|---------|
| **Ollama** | | | |
| - Replicas | 1 | 1-2 | 1-3 |
| - CPU | 500m-2 | 1-3 | 1-4 |
| - Memory | 2-4Gi | 4-8Gi | 4-8Gi |
| - PVC | 10Gi | 20Gi | 20Gi |
| **OpenWebUI** | | | |
| - Replicas | 1 | 1-3 | 1-5 |
| - CPU | 250m-1 | 500m-2 | 1-2 |
| - Memory | 512Mi-1Gi | 1-2Gi | 1-2Gi |
| - PVC | 2Gi | 5Gi | 5Gi |
| **Prometheus** | | | |
| - 数据保留 | 1天 | 3天 | 7天 |
| - 采集间隔 | 120s | 60s | 30s |
| - Storage | 2Gi | 5Gi | 5Gi |
| **Loki** | | | |
| - 数据保留 | 24h | 48h | 7天 |
| - Memory | 512Mi | 1Gi | 2Gi |
| - Storage | 1Gi | 2Gi | 2Gi |

### 特性对比

| 特性 | 开发环境 | 预发布环境 | 生产环境 |
|------|---------|-----------|---------|
| HPA | 关闭 | 按需开启 | 开启 |
| PDB | 关闭 | 开启 | 开启 |
| 告警静默 | 全部静默 | 部分静默 | 全部开启 |
| 日志级别 | Debug | Info | Warning |
| 监控告警 | 简化 | 完整 | 完整+扩展 |

## 🚀 部署流程

### 1. 开发环境部署

```bash
# 部署开发环境
kubectl apply -f environments/dev/

# 验证部署
kubectl get pods -n ai-platform
```

### 2. 预发布环境部署

```bash
# 部署预发布环境
kubectl apply -f environments/stag/

# 运行测试
kubectl exec -it <pod-name> -n ai-platform -- /test.sh
```

### 3. 生产环境部署

```bash
# 部署生产环境
kubectl apply -f environments/prod/

# 验证健康状态
bash scripts/health-check.sh
```

## 🔧 环境变量

### 开发环境变量

```yaml
OLLAMA_MODEL: "qwen2.5:0.5b"
LOG_LEVEL: "debug"
ENABLE_HPA: "false"
ENABLE_PDB: "false"
```

### 预发布环境变量

```yaml
OLLAMA_MODEL: "qwen2.5:0.5b"
LOG_LEVEL: "info"
ENABLE_HPA: "true"
ENABLE_PDB: "true"
ALERT_THRESHOLD: "medium"
```

### 生产环境变量

```yaml
OLLAMA_MODEL: "qwen2.5:0.5b"
LOG_LEVEL: "warning"
ENABLE_HPA: "true"
ENABLE_PDB: "true"
ALERT_THRESHOLD: "high"
```

## 📊 监控配置

### 开发环境

```yaml
prometheus:
  scrapeInterval: 120s
  evaluationInterval: 120s
  retention: 1d
```

### 预发布环境

```yaml
prometheus:
  scrapeInterval: 60s
  evaluationInterval: 60s
  retention: 3d
```

### 生产环境

```yaml
prometheus:
  scrapeInterval: 30s
  evaluationInterval: 30s
  retention: 7d
```

## 🔐 安全配置

### 开发环境
- RBAC: 开发人员完全权限
- NetworkPolicy: 禁用
- Sealed Secrets: 可选

### 预发布环境
- RBAC: 开发人员只读权限
- NetworkPolicy: 部分启用
- Sealed Secrets: 必需

### 生产环境
- RBAC: 最小权限原则
- NetworkPolicy: 完全启用
- Sealed Secrets: 必需
- Pod安全策略: 严格模式

## 🔄 环境切换

### GitOps流程

```
Dev环境 → Stag环境 → Prod环境
   ↓           ↓           ↓
 自动部署    自动部署    手动批准
   ↓           ↓           ↓
 快速迭代    功能测试    生产验证
```

### ArgoCD同步策略

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
    # 仅dev环境自动同步
```

## 📝 配置管理

### ConfigMap示例

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-platform-config
  namespace: ai-platform
data:
  ENVIRONMENT: "prod"
  LOG_LEVEL: "info"
  ENABLE_HPA: "true"
  ENABLE_PDB: "true"
```

### Secret示例 (Sealed)

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: ai-platform-secrets
  namespace: ai-platform
spec:
  encryptedData:
    WECHAT_TOKEN: AgA...
    API_KEY: AgB...
```

## 🧪 测试配置

### 开发环境测试
- 单元测试: 每次提交
- 集成测试: 每日
- 性能测试: 每周

### 预发布环境测试
- 单元测试: 每次提交
- 集成测试: 每次合并
- 性能测试: 每次发布
- E2E测试: 每次发布

### 生产环境测试
- 单元测试: 每次提交
- 集成测试: 每次合并
- 性能测试: 每月
- 混沌测试: 每季度

## 📈 扩缩容策略

### 开发环境
- 手动扩缩容
- 无自动扩缩容
- 固定副本数

### 预发布环境
- HPA基于CPU/Memory
- 副本数: 1-3
- 扩容阈值: 80%

### 生产环境
- HPA基于CPU/Memory
- 副本数: 1-5 (Ollama: 1-3)
- 扩容阈值: 80%
- 缩容冷却: 300秒

## 🔄 回滚策略

### 开发环境
- 自动回滚
- 保留版本: 3个

### 预发布环境
- 半自动回滚
- 保留版本: 5个

### 生产环境
- 手动回滚
- 保留版本: 10个

## 📞 环境支持

### 开发环境
- 联系人: 开发团队
- 响应时间: 即时
- 维护时间: 随时

### 预发布环境
- 联系人: 开发+运维
- 响应时间: <1小时
- 维护时间: 工作时间

### 生产环境
- 联系人: 运维团队
- 响应时间: <15分钟
- 维护时间: 变更窗口

## 🎯 成功标准

### 开发环境
- [x] 所有Pod运行正常
- [x] 基本功能可用
- [x] 日志正常

### 预发布环境
- [x] 所有测试通过
- [x] 性能达标
- [x] 监控告警正常

### 生产环境
- [x] 99.9%可用性
- [x] TTFT < 500ms
- [x] QPS > 100
- [x] 监控告警完善
- [x] 备份恢复正常
