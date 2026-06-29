#===============================================================================
# K3S AI Platform 扩展策略与维护指南
#===============================================================================

## 📋 文档信息

- **文档名称**: K3S AI Platform 扩展策略与维护指南
- **版本**: v1.0.0
- **目标读者**: 运维工程师、SRE、架构师

---

## 1. 水平扩展策略

### 1.1 应用层扩展

#### Ollama扩展
```yaml
# HPA配置
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

#### OpenWebUI扩展
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: open-webui-hpa
  namespace: ai-platform
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: open-webui
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 75
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 85
```

### 1.2 节点层扩展

#### 添加新节点
```bash
# 在新节点上执行
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<MASTER_IP>:6443 \
  K3S_TOKEN=<NODE_TOKEN> \
  K3S_NODE_NAME=<NODE_NAME> \
  sh -
```

#### 节点池管理
```bash
# 查看所有节点
kubectl get nodes -o wide

# 查看节点资源
kubectl describe node <NODE_NAME>

# 标记节点
kubectl label node <NODE_NAME> node-role.kubernetes.io/worker=worker

# 隔离节点
kubectl cordon <NODE_NAME>

# 驱逐Pod
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data
```

---

## 2. 垂直扩展策略

### 2.1 Pod资源调整

#### VPA (Vertical Pod Autoscaler)
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: ollama-vpa
  namespace: ai-platform
spec:
  targetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: ollama
  updatePolicy:
    updateMode: "Auto"
```

### 2.2 存储扩展

#### PVC扩容
```bash
# 编辑PVC
kubectl edit pvc ollama-data -n ai-platform

# 将spec.resources.requests.storage增大
# 例如：从20Gi改为30Gi
```

---

## 3. 项目集成扩展

### 3.1 添加新应用

#### 步骤1：创建应用目录
```bash
mkdir -p environments/prod/apps/my-new-app
```

#### 步骤2：创建应用配置
```yaml
# environments/prod/apps/my-new-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-new-app
  namespace: ai-platform
  labels:
    app: my-new-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-new-app
  template:
    metadata:
      labels:
        app: my-new-app
    spec:
      containers:
      - name: my-new-app
        image: my-new-app:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

#### 步骤3：配置Ingress
```yaml
# environments/prod/apps/my-new-app/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-new-app-ingress
  namespace: ai-platform
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: my-app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-new-app
            port:
              number: 8080
```

#### 步骤4：配置HPA
```yaml
# environments/prod/apps/my-new-app/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-new-app-hpa
  namespace: ai-platform
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-new-app
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

#### 步骤5：添加ArgoCD应用
```yaml
# argocd/apps/my-new-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-new-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <GIT_REPO>
    targetRevision: HEAD
    path: environments/prod/apps/my-new-app
  destination:
    server: https://kubernetes.default.svc
    namespace: ai-platform
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 3.2 多模型支持

#### 添加新模型
```bash
# 在Ollama Pod中执行
kubectl exec -it ollama-0 -n ai-platform -- ollama pull qwen2.5:1.5b

# 或在应用配置中预加载
env:
- name: OLLAMA_MODELS
  value: "qwen2.5:0.5b,qwen2.5:1.5b,llama2:7b"
```

---

## 4. 集群联邦 (未来扩展)

### 4.1 多集群架构

```
Region 1 (上海)
├── Cluster: prod-shanghai
│   ├── AI Platform Primary
│   └── Monitoring
│
Region 2 (北京)
├── Cluster: prod-beijing
│   ├── AI Platform Secondary
│   └── Monitoring
│
Global
├── ArgoCD Federation
└── Centralized Logging
```

### 4.2 跨集群服务发现

```yaml
# ServiceExport
apiVersion: multicluster.k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: ollama-global
  namespace: ai-platform
---
# ServiceImport
apiVersion: multicluster.k8s.io/v1alpha1
kind: ServiceImport
metadata:
  name: ollama-global
  namespace: ai-platform
spec:
  clusters:
  - name: prod-shanghai
  - name: prod-beijing
```

---

## 5. 服务网格 (未来扩展)

### 5.1 Istio集成

```bash
# 安装Istio
curl -L https://istio.io/downloadIstio | sh -
istioctl install --set profile=default

# 启用Sidecar自动注入
kubectl label namespace ai-platform istio-injection=enabled
```

### 5.2 流量管理

```yaml
# 虚拟服务
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: ollama
  namespace: ai-platform
spec:
  hosts:
  - ollama.ai-platform.svc.cluster.local
  http:
  - route:
    - destination:
        host: ollama.ai-platform.svc.cluster.local
        subset: v1
      weight: 100
```

---

## 6. 灾难恢复

### 6.1 备份策略

| 备份项 | 频率 | 保留时间 | 存储位置 |
|--------|------|----------|----------|
| K8s资源 | 每日 | 30天 | Git仓库 |
| PVC数据 | 每周 | 4周 | 对象存储 |
| Secrets | 每次变更 | 30天 | Git仓库 |
| 监控数据 | 实时 | 7天 | Loki |
| 日志数据 | 实时 | 7天 | Loki |

### 6.2 备份脚本

```bash
#!/bin/bash
# backup.sh - K3S AI Platform备份脚本

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=/backup/k3s-ai-platform

# 创建备份目录
mkdir -p $BACKUP_DIR/$DATE

# 备份K8s资源
kubectl get all -A -o yaml > $BACKUP_DIR/$DATE/resources.yaml

# 备份Secrets (加密)
kubectl get secrets -A -o yaml | \
  kubeseal --format=yaml > $BACKUP_DIR/$DATE/secrets.yaml

# 备份PVC元数据
kubectl get pvc -A -o yaml > $BACKUP_DIR/$DATE/pvc.yaml

# 备份配置文件
cp -r /root/sre-lab $BACKUP_DIR/$DATE/config

# 上传到对象存储
# aws s3 cp --recursive $BACKUP_DIR/$DATE s3://my-bucket/k3s-backup/

# 清理旧备份 (保留30天)
find $BACKUP_DIR -type d -mtime +30 -exec rm -rf {} \;
```

### 6.3 恢复流程

```bash
#!/bin/bash
# restore.sh - K3S AI Platform恢复脚本

BACKUP_DATE=$1
BACKUP_DIR=/backup/k3s-ai-platform/$BACKUP_DATE

# 恢复K8s资源
kubectl apply -f $BACKUP_DIR/resources.yaml

# 恢复Secrets
kubeseal --recovery --file $BACKUP_DIR/secrets.yaml | kubectl apply -f -

# 恢复配置
cp -r $BACKUP_DIR/config/* /root/sre-lab/

# 验证恢复
kubectl get pods -A
bash /root/sre-lab/scripts/health-check.sh
```

---

## 7. 性能优化

### 7.1 Ollama优化

#### 资源配置优化
```yaml
env:
- name: OLLAMA_GPU_OVERHEAD
  value: "0"
- name: OLLAMA_NUM_PARALLEL
  value: "4"
- name: OLLAMA_MAX_LOADED_MODELS
  value: "1"
```

#### 缓存优化
```yaml
resources:
  requests:
    cpu: 1
    memory: 4Gi
  limits:
    cpu: 2
    memory: 8Gi
```

### 7.2 Prometheus优化

#### 分片策略
```yaml
spec:
  replicas: 2
  shards: 2
```

#### 查询优化
```yaml
spec:
  prometheusSpec:
    queryLogFile: /var/log/prometheus/query.log
    maxSamplesPerQuery: 10000000
```

### 7.3 Loki优化

#### 分发策略
```yaml
ingester:
  chunk_target_size: 2097152
  max_chunk_age: 15m
```

#### 查询优化
```yaml
limits_config:
  max_entries_limit_per_query: 5000
  query_timeout: 300s
```

---

## 8. 监控与告警

### 8.1 关键指标

| 指标 | 阈值 | 告警级别 |
|------|------|---------|
| API响应时间 | > 1s | Warning |
| API错误率 | > 1% | Warning |
| CPU使用率 | > 80% | Warning |
| Memory使用率 | > 90% | Critical |
| 磁盘使用率 | > 85% | Warning |
| Pod重启次数 | > 5次/小时 | Warning |

### 8.2 自定义告警

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ai-platform-alerts
  namespace: ai-platform
spec:
  groups:
  - name: ai-platform
    rules:
    - alert: HighAPIErrorRate
      expr: |
        sum(rate(http_requests_total{status=~"5.."}[5m])) /
        sum(rate(http_requests_total[5m])) > 0.01
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "API错误率过高"
        description: "API 5xx错误率超过1%"
```

---

## 9. 容量规划

### 9.1 当前容量

| 组件 | 当前容量 | 最大容量 | 使用率 |
|------|---------|---------|--------|
| Ollama | 1-3 Pods | 3 Pods | 33% |
| OpenWebUI | 1-5 Pods | 5 Pods | 20% |
| Prometheus | 512Mi RAM | 512Mi RAM | 50% |
| Loki | 2Gi Storage | 2Gi Storage | 40% |

### 9.2 扩展计划

| 阶段 | 时间 | 扩展内容 |
|------|------|---------|
| Phase 1 | 1-3月 | 增加Ollama副本到3个 |
| Phase 2 | 3-6月 | 增加OpenWebUI副本到5个 |
| Phase 3 | 6-12月 | 增加节点数量到3个 |
| Phase 4 | 12+月 | 多集群联邦 |

---

## 10. 维护窗口

### 10.1 计划维护

| 维护类型 | 频率 | 维护时间 | 影响范围 |
|---------|------|---------|---------|
| K3S升级 | 每季度 | 周末2小时 | 服务短暂中断 |
| 监控升级 | 每月 | 周中1小时 | 无影响 |
| 应用升级 | 按需 | 随时 | 滚动升级无影响 |

### 10.2 紧急维护

- **响应时间**: < 15分钟
- **维护窗口**: 立即
- **通知方式**: 微信告警 + 邮件

### 10.3 变更管理

```bash
# 变更申请流程
1. 创建Issue: https://github.com/<user>/sre-lab/issues
2. 评审变更
3. 批准变更
4. 执行变更
5. 验证变更
6. 关闭Issue
```

---

## 11. 文档维护

### 11.1 文档更新

| 文档 | 更新频率 | 负责人 |
|------|---------|--------|
| 架构设计文档 | 每季度 | 架构师 |
| 部署指南 | 按需 | 运维工程师 |
| 运维手册 | 每月 | SRE |
| 健康检查脚本 | 每周 | SRE |

### 11.2 知识库

```bash
# 文档目录结构
/root/sre-lab/k3s-ai-platform/docs/
├── architecture-design.md      # 架构设计
├── deployment-guide.md        # 部署指南
├── operations-manual.md       # 运维手册
├── monitoring-guide.md       # 监控指南
├── troubleshooting.md        # 故障排查
└── faq.md                   # 常见问题
```

---

## 12. 团队协作

### 12.1 角色与职责

| 角色 | 职责 | 权限 |
|------|------|------|
| 开发工程师 | 应用开发 | 开发环境完全权限 |
| 运维工程师 | 部署维护 | 运维权限 |
| SRE | 监控告警 | 只读权限 |
| 架构师 | 架构设计 | 完全权限 |

### 12.2 沟通渠道

- **即时通讯**: 企业微信群
- **Issue跟踪**: GitHub Issues
- **文档协作**: GitHub Wiki
- **告警通知**: 微信 + 邮件

### 12.3 值班安排

```yaml
# 值班表 (示例)
oncall_schedule:
  - week: 2024-W25
    primary: developer1@example.com
    secondary: developer2@example.com
  - week: 2024-W26
    primary: developer2@example.com
    secondary: developer1@example.com
```

---

**文档版本**: v1.0.0
**最后更新**: 2026-06-20
**维护者**: 云原生架构专家
**下次审查**: 2026-09-20
