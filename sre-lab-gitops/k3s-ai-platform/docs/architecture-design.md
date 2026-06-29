# K3S-AI-PLATFORM 架构设计文档

## 📋 文档信息

- **项目名称**: K3S-AI-PLATFORM
- **版本**: v1.0.0
- **作者**: 云原生架构专家
- **日期**: 2026-06-20
- **状态**: 生产就绪

---

## 1. 系统概述

### 1.1 项目背景

本项目是一个基于K3S的高并发AI推理平台，采用项目驱动学习的方式搭建，旨在掌握云原生核心技术和最佳实践。项目涵盖了从基础设施到应用部署的完整云原生技术栈。

### 1.2 设计目标

1. **高可用性**: 支持99.9%以上的服务可用性
2. **可扩展性**: 支持水平扩展和垂直扩展
3. **自动化**: 完善的CI/CD和GitOps流程
4. **可观测性**: 全面的监控、日志和告警体系
5. **安全性**: 多层安全防护和密钥管理

### 1.3 技术栈

| 类别 | 技术 | 版本 | 用途 |
|------|------|------|------|
| **容器编排** | K3S | v1.29+ | 集群管理 |
| **应用框架** | Ollama + OpenWebUI | Latest | AI推理 |
| **监控** | Prometheus + Grafana | Latest | 指标监控 |
| **日志** | Loki + Promtail | Latest | 日志收集 |
| **告警** | AlertManager + WeChat | Latest | 告警通知 |
| **Ingress** | Traefik | Latest | 入口路由 |
| **GitOps** | ArgoCD | Latest | 持续部署 |
| **密钥** | Sealed Secrets | Latest | 密钥管理 |
| **自动伸缩** | HPA + VPA | Kubernetes内置 | 弹性伸缩 |

---

## 2. 系统架构

### 2.1 整体架构图

```
┌────────────────────────────────────────────────────────────────┐
│                      外部网络                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   用户访问    │  │   监控访问   │  │   告警推送   │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
└─────────┼────────────────┼────────────────┼──────────────────┘
          │                │                │
          ▼                ▼                ▼
┌────────────────────────────────────────────────────────────────┐
│                    K3S Cluster                                 │
├────────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                   Ingress Layer (Traefik)               │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │  │
│  │  │ OpenWebUI │  │  Grafana   │  │ Prometheus │     │  │
│  │  │  :3000    │  │   :3100   │  │   :9090   │     │  │
│  │  └────────────┘  └────────────┘  └────────────┘     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                    Application Layer                     │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │  │
│  │  │   Ollama  │  │ OpenWebUI  │  │  Nginx    │     │  │
│  │  │  (StatefulSet) │ (Deployment)│ (Deployment)│     │  │
│  │  │  replicas:1-3 │ replicas:1-5 │ replicas:1-3 │     │  │
│  │  └────────────┘  └────────────┘  └────────────┘     │  │
│  │                                                            │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │  │
│  │  │     HPA    │  │    PDB     │  │   PVC     │     │  │
│  │  │  CPU/Mem  │  │ min:1     │  │ 20Gi+5Gi │     │  │
│  │  └────────────┘  └────────────┘  └────────────┘     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                  Observability Layer                    │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │  │
│  │  │ Prometheus │  │    Loki   │  │  Grafana  │     │  │
│  │  │   :9090   │  │   :3100   │  │   :3000   │     │  │
│  │  └────────────┘  └────────────┘  └────────────┘     │  │
│  │                                                            │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │  │
│  │  │   Loki     │  │  Promtail │  │ WeChat    │     │  │
│  │  │  (Storage)│  │  (DaemonSet)│  │ Adapter  │     │  │
│  │  └────────────┘  └────────────┘  └────────────┘     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                     GitOps Layer                        │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │  │
│  │  │  ArgoCD   │  │ Sealed    │  │  Metrics   │     │  │
│  │  │           │  │ Secrets   │  │  Server    │     │  │
│  │  └────────────┘  └────────────┘  └────────────┘     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### 2.2 组件依赖关系

```
用户请求
    │
    ▼
Traefik Ingress Controller
    │
    ├──► OpenWebUI Service
    │         │
    │         └──► Ollama Service (StatefulSet)
    │                   │
    │                   ├──► Ollama PVC (20Gi)
    │                   │
    │                   └──► Ollama Exporter (Metrics)
    │
    ├──► Grafana Service
    │         │
    │         └──► Prometheus Service
    │                   │
    │                   ├──► AlertManager Service
    │                   │         │
    │                   │         └──► WeChat Adapter
    │                   │
    │                   └──► Loki Service
    │                             │
    │                             └──► Promtail (DaemonSet)
    │
    └──► Nginx Demo Service

ArgoCD (持续部署)
    │
    ├──► 应用同步状态
    ├──► Sealed Secrets
    └──► Git Repository
```

---

## 3. 环境配置

### 3.1 环境概述

本项目采用三环境分离架构，分别为开发环境、预发布环境和生产环境。各环境配置根据用途和需求进行差异化设置。

### 3.2 环境配置对比表

| 配置项 | 开发环境 (dev) | 预发布环境 (stag) | 生产环境 (prod) |
|--------|----------------|-------------------|----------------|
| **集群规模** | 单节点 | 多节点 | 多节点高可用 |
| **节点规格** | 2C4G | 4C8G | 8C16G |
| **副本数** | 最小配置 | 中等配置 | 最大配置 |
| **资源限制** | 宽松 | 中等 | 严格 |
| **监控粒度** | 1分钟 | 30秒 | 15秒 |
| **告警阈值** | 低 | 中 | 高 |
| **数据保留** | 1天 | 3天 | 7天 |
| **自动扩缩容** | 关闭 | 按需开启 | 开启 |

### 3.3 开发环境配置 (dev)

**目录**: `environments/dev/`

#### 资源配置
- **Ollama StatefulSet**:
  - Replicas: 1
  - CPU Request: 500m / Limit: 2
  - Memory Request: 2Gi / Limit: 4Gi
  - PVC: 10Gi

- **OpenWebUI Deployment**:
  - Replicas: 1
  - CPU Request: 250m / Limit: 1
  - Memory Request: 512Mi / Limit: 1Gi
  - PVC: 2Gi

- **Prometheus**:
  - 数据保留: 1天
  - 采集间隔: 120秒

- **Loki**:
  - 数据保留: 24小时
  - Memory Limit: 512Mi

#### 特点
- 快速迭代，部署频繁
- 日志详细，便于调试
- 资源限制宽松
- 无自动扩缩容

### 3.4 预发布环境配置 (stag)

**目录**: `environments/stag/`

#### 资源配置
- **Ollama StatefulSet**:
  - Replicas: 1-2 (HPA)
  - CPU Request: 1 / Limit: 3
  - Memory Request: 4Gi / Limit: 8Gi
  - PVC: 20Gi

- **OpenWebUI Deployment**:
  - Replicas: 1-3 (HPA)
  - CPU Request: 500m / Limit: 2
  - Memory Request: 1Gi / Limit: 2Gi
  - PVC: 5Gi

- **Prometheus**:
  - 数据保留: 3天
  - 采集间隔: 60秒

- **Loki**:
  - 数据保留: 48小时
  - Memory Limit: 1Gi

#### 特点
- 模拟生产环境
- 启用自动扩缩容
- 完整测试覆盖
- 告警阈值适中

### 3.5 生产环境配置 (prod)

**目录**: `environments/prod/`

#### 资源配置
- **Ollama StatefulSet**:
  - Replicas: 1-3 (HPA)
  - CPU Request: 1 / Limit: 4
  - Memory Request: 4Gi / Limit: 8Gi
  - PVC: 20Gi
  - PDB: minAvailable 1

- **OpenWebUI Deployment**:
  - Replicas: 1-5 (HPA)
  - CPU Request: 1 / Limit: 2
  - Memory Request: 1Gi / Limit: 2Gi
  - PVC: 5Gi
  - PDB: minAvailable 1

- **Prometheus**:
  - 数据保留: 7天
  - 采集间隔: 30秒
  - PVC: 5Gi

- **Loki**:
  - 数据保留: 7天
  - Memory Limit: 2Gi
  - PVC: 2Gi

#### 特点
- 高可用配置
- 严格的资源限制
- 全面的监控告警
- 完整的安全策略

---

## 4. 核心组件设计

### 4.1 AI推理平台

#### Ollama StatefulSet
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ollama
  namespace: ai-platform
spec:
  serviceName: ollama
  replicas: 1
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      containers:
      - name: ollama
        image: ollama/ollama:latest
        ports:
        - containerPort: 11434
          name: api
        resources:
          requests:
            cpu: 500m
            memory: 2Gi
          limits:
            cpu: 2
            memory: 4Gi
        volumeMounts:
        - name: ollama-data
          mountPath: /root/.ollama
      volumes:
      - name: ollama-data
        persistentVolumeClaim:
          claimName: ollama-data
  volumeClaimTemplates:
  - metadata:
      name: ollama-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: local-path
      resources:
        requests:
          storage: 20Gi
```

#### OpenWebUI Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: open-webui
  namespace: ai-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app: open-webui
  template:
    metadata:
      labels:
        app: open-webui
    spec:
      containers:
      - name: open-webui
        image: ghcr.io/open-webui/open-webui:main
        ports:
        - containerPort: 8080
        env:
        - name: OLLAMA_BASE_URL
          value: "http://ollama:11434"
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 1
            memory: 1Gi
```

#### HPA配置
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ollama-hpa
  namespace: ai-platform
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: ollama
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 85
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Pods
        value: 1
        periodSeconds: 180
```

#### PDB配置
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ollama-pdb
  namespace: ai-platform
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: ollama
```

### 4.2 监控体系

#### Prometheus配置
```yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
  namespace: monitoring
spec:
  retention: 7d
  scrapeInterval: 30s
  evaluationInterval: 30s
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: local-path
        resources:
          requests:
            storage: 5Gi
```

#### AlertManager配置
```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 1m
  repeat_interval: 4h
  receiver: 'wechat-adapter'

receivers:
- name: 'wechat-adapter'
  webhook_configs:
  - url: 'http://wechat-adapter-svc.monitoring.svc/webhook'
    send_resolved: true

inhibit_rules:
- source_match:
    severity: 'critical'
  target_match:
    severity: 'warning'
  equal: ['alertname', 'namespace']
```

#### Loki配置
```yaml
server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
  - from: "2020-10-24"
    store: boltdb-shipper
    object_store: filesystem
    schema: v11
    index:
      prefix: index_
      period: 24h

limits_config:
  ingestion_rate_mb: 5
  ingestion_burst_size_mb: 10
  reject_old_samples: true
  reject_old_samples_max_age: 24h
```

### 4.3 GitOps配置

#### ArgoCD Application
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ai-platform
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <git-repo-url>
    targetRevision: HEAD
    path: environments/prod/apps/ai-platform
  destination:
    server: https://kubernetes.default.svc
    namespace: ai-platform
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## 5. 网络设计

### 5.1 Ingress配置

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ai-platform-ingress
  namespace: ai-platform
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
  - host: ai-platform.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: open-webui
            port:
              number: 8080
```

### 5.2 Service配置

| Service名称 | 类型 | 端口 | 用途 |
|------------|------|------|------|
| ollama | ClusterIP | 11434 | Ollama API |
| open-webui | ClusterIP | 8080 | Web界面 |
| prometheus | ClusterIP | 9090 | Prometheus |
| grafana | ClusterIP | 3000 | Grafana |
| loki | ClusterIP | 3100 | Loki |
| alertmanager | ClusterIP | 9093 | AlertManager |

---

## 6. 存储设计

### 6.1 PVC配置

| PVC名称 | 命名空间 | 存储大小 | 访问模式 | 用途 |
|--------|----------|----------|----------|------|
| ollama-data | ai-platform | 20Gi | RWO | Ollama模型存储 |
| open-webui-data | ai-platform | 5Gi | RWO | WebUI数据 |
| prometheus-data | monitoring | 5Gi | RWO | Prometheus数据 |
| loki-data | logging | 2Gi | RWO | Loki日志存储 |

### 6.2 StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
```

---

## 7. 安全性设计

### 7.1 Sealed Secrets

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: wechat-token
  namespace: monitoring
spec:
  encryptedData:
    token: AgA...  # 加密的Token
```

### 7.2 RBAC配置

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ai-platform-admin
  namespace: ai-platform
rules:
- apiGroups: [""]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["apps"]
  resources: ["*"]
  verbs: ["*"]
```

---

## 8. 扩展性设计

### 8.1 水平扩展

- **应用层**: HPA自动扩缩容
- **数据层**: StatefulSet支持有序扩展
- **存储层**: PVC动态扩容

### 8.2 垂直扩展

- **VPA**: 垂直 Pod 自动扩缩容（预留）
- **节点扩展**: 支持多节点集群

### 8.3 模块扩展

项目结构预留了以下扩展接口：
1. 新增AI模型服务
2. 新增数据处理服务
3. 新增API网关
4. 新增服务网格（Istio/Linkerd）

---

## 9. 运维设计

### 9.1 监控指标

| 指标类别 | 指标名称 | 告警阈值 |
|----------|----------|----------|
| **节点指标** | CPU使用率 | >80% |
| **节点指标** | 内存使用率 | >90% |
| **节点指标** | 磁盘使用率 | >85% |
| **应用指标** | Pod重启次数 | >5次/小时 |
| **应用指标** | Pod健康检查失败 | 持续5分钟 |
| **业务指标** | API响应时间 | >1秒 |
| **业务指标** | 请求错误率 | >1% |

### 9.2 告警规则

```yaml
groups:
- name: sre-lab.node
  rules:
  - alert: NodeHighMemoryUsage
    expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "节点内存使用率过高"

  - alert: NodeHighCPUUsage
    expr: (1 - avg by(instance)(irate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 80
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "节点CPU使用率过高"
```

### 9.3 日志收集

```yaml
scrape_configs:
- job_name: kubernetes-pods
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_node_name]
    action: replace
    target_label: __host__
  - replacement: /var/log/pods/*$1/*.log
    source_labels: [__meta_kubernetes_pod_uid, __meta_kubernetes_pod_container_name]
    target_label: __path__
```

---

## 10. 部署流程

### 10.1 环境部署顺序

```
1. 基础设施层
   ├── StorageClass配置
   ├── NetworkPolicy配置
   └── RBAC配置

2. 核心服务层
   ├── Metrics Server
   ├── Ingress Controller (Traefik)
   └── DNS配置

3. 监控告警层
   ├── Prometheus
   ├── AlertManager
   ├── Grafana
   ├── Loki
   └── Promtail

4. GitOps层
   ├── ArgoCD
   └── Sealed Secrets

5. 应用层
   ├── AI Platform (Ollama + OpenWebUI)
   ├── HPA配置
   └── PDB配置

6. 验证测试
   ├── 健康检查
   ├── 功能测试
   └── 性能测试
```

### 10.2 GitOps部署流程

```
代码提交 → GitHub → ArgoCD自动同步 → K3S集群部署
                              ↓
                        健康检查
                              ↓
                        监控告警
```

---

## 11. 灾难恢复

### 11.1 数据备份

| 数据类型 | 备份频率 | 保留时间 | 存储位置 |
|----------|----------|----------|----------|
| PVC数据 | 每日 | 7天 | 本地存储 |
| 配置数据 | 每次部署 | 30天 | Git仓库 |
| 监控数据 | 7天 | 7天 | Prometheus |
| 日志数据 | 实时 | 7天 | Loki |

### 11.2 恢复流程

1. 从Git仓库恢复配置
2. 从PVC备份恢复数据
3. 重启相关服务
4. 验证服务可用性

---

## 12. 性能优化

### 12.1 Ollama优化

```yaml
env:
- name: OLLAMA_GPU_OVERHEAD
  value: "0"
- name: OLLAMA_NUM_PARALLEL
  value: "4"
- name: OLLAMA_MAX_LOADED_MODELS
  value: "1"
```

### 12.2 Prometheus优化

```yaml
spec:
  retention: 7d
  scrapeInterval: 30s
  evaluationInterval: 30s
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
```

### 12.3 Loki优化

```yaml
limits_config:
  ingestion_rate_mb: 5
  ingestion_burst_size_mb: 10
  max_entries_limit_per_query: 5000
```

---

## 13. 最佳实践

### 13.1 资源配置

- 为每个容器设置合理的resources limits
- 使用LimitRange限制命名空间资源
- 定期Review资源配置

### 13.2 健康检查

- 合理配置livenessProbe和readinessProbe
- 避免过短的超时时间和过长的初始延迟
- 为StatefulSet配置适当的探针

### 13.3 日志管理

- 统一日志格式
- 合理的日志级别
- 定期清理历史日志

### 13.4 监控告警

- 合理的告警阈值
- 避免告警风暴
- 定期Review告警规则

---

## 14. 未来规划

### 14.1 短期规划 (1-3个月)

- [ ] 完成多模型支持
- [ ] 实现API网关
- [ ] 优化HPA策略

### 14.2 中期规划 (3-6个月)

- [ ] 引入服务网格
- [ ] 实现灰度发布
- [ ] 完善灾备方案

### 14.3 长期规划 (6-12个月)

- [ ] 多集群联邦
- [ ] 边缘计算支持
- [ ] AI模型市场

---

## 15. 附录

### 15.1 术语表

| 术语 | 说明 |
|------|------|
| HPA | Horizontal Pod Autoscaler - 水平Pod自动扩缩容 |
| VPA | Vertical Pod Autoscaler - 垂直Pod自动扩缩容 |
| PDB | Pod Disruption Budget - Pod中断预算 |
| PVC | Persistent Volume Claim - 持久化卷声明 |
| RBAC | Role-Based Access Control - 基于角色的访问控制 |
| GitOps | Git-based Ops - 基于Git的运维 |
| SLO | Service Level Objective - 服务级别目标 |

### 15.2 参考资料

- [K3S官方文档](https://docs.k3s.io/)
- [Kubernetes官方文档](https://kubernetes.io/zh-cn/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [ArgoCD官方文档](https://argoproj.github.io/cd/)
- [Loki官方文档](https://grafana.com/docs/loki/latest/)

---

**文档版本**: v1.0.0
**最后更新**: 2026-06-20
**维护者**: 云原生架构专家
