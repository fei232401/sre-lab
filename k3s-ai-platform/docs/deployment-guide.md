# K3S AI Platform 部署指南

## 📋 文档信息

- **文档名称**: K3S AI Platform 部署指南
- **版本**: v1.0.0
- **目标读者**: 开发工程师、运维工程师、SRE

---

## 1. 前置要求

### 1.1 系统要求

| 要求项 | 最低配置 | 推荐配置 |
|--------|---------|---------|
| CPU | 2核 | 4核+ |
| 内存 | 4GB | 8GB+ |
| 磁盘 | 40GB | 100GB+ |
| 操作系统 | Ubuntu 20.04+ / CentOS 8+ | Ubuntu 22.04 LTS |
| 网络 | 至少1个公网IP | 固定公网IP |

### 1.2 软件要求

- Kubernetes: v1.29+
- kubectl: v1.29+
- Helm: v3.12+
- Docker: v24+ (可选)

---

## 2. K3S集群安装

### 2.1 单节点安装

```bash
# 下载并安装K3S
curl -sfL https://get.k3s.io | sh -

# 验证安装
kubectl get nodes

# 查看K3S状态
systemctl status k3s

# 获取K3S token (用于添加节点)
cat /var/lib/rancher/k3s/server/node-token
```

### 2.2 高可用安装 (多节点)

```bash
# 第一步：在第一个节点执行
curl -sfL https://get.k3s.io | K3S_TOKEN=<TOKEN> K3S_URL=https://<MASTER_IP>:6443 sh -

# 其他节点：作为Agent加入
curl -sfL https://get.k3s.io | K3S_TOKEN=<TOKEN> K3S_URL=https://<MASTER_IP>:6443 K3S_NODE_NAME=<NODE_NAME> sh -
```

### 2.3 配置kubectl

```bash
# 复制kubeconfig
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config

# 验证连接
kubectl get nodes
kubectl get pods -A
```

---

## 3. 基础环境部署

### 3.1 部署顺序

```
1. StorageClass (local-path)
2. Metrics Server
3. Ingress Controller (Traefik)
4. DNS (可选)
```

### 3.2 StorageClass配置

```bash
# K3S默认已安装local-path-provisioner
kubectl get storageclass

# 输出应包含：
# NAME                   PROVISIONER             RECLAIMPOLICY
# local-path (default)   rancher.io/local-path  Delete
```

### 3.3 Metrics Server

```bash
# 部署Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 验证部署
kubectl get pods -n kube-system -l k8s-app=metrics-server

# 测试metrics API
kubectl top nodes
kubectl top pods -A
```

### 3.4 Ingress Controller (Traefik)

```bash
# Traefik已在K3S中默认启用
# 验证Traefik运行
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
```

---

## 4. 监控栈部署

### 4.1 使用Helm部署kube-prometheus-stack

```bash
# 添加Prometheus社区仓库
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 创建monitoring命名空间
kubectl create namespace monitoring

# 部署kube-prometheus-stack
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.scrapeInterval=30s \
  --set grafana.adminPassword='admin123'

# 验证部署
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

### 4.2 部署Loki日志系统

```bash
# 部署Loki
kubectl apply -f environments/prod/monitoring/loki/

# 部署Promtail
kubectl apply -f environments/prod/monitoring/promtail/

# 验证部署
kubectl get pods -n logging
```

### 4.3 部署WeChat告警适配器

```bash
# 部署WeChat Adapter
kubectl apply -f environments/prod/monitoring/wechat-adapter/

# 验证部署
kubectl get pods -n monitoring -l app=wechat-adapter
```

---

## 5. GitOps部署 (ArgoCD)

### 5.1 安装ArgoCD

```bash
# 创建命名空间
kubectl create namespace argocd

# 部署ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待ArgoCD启动
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# 获取初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 5.2 配置ArgoCD应用

```bash
# 登录ArgoCD
argocd login <ARGOCD_SERVER>

# 创建应用
argocd app create ai-platform \
  --repo <GIT_REPO_URL> \
  --path environments/prod/apps/ai-platform \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace ai-platform \
  --sync-policy automated

# 同步应用
argocd app sync ai-platform
```

---

## 6. 应用部署

### 6.1 创建命名空间

```bash
# 创建ai-platform命名空间
kubectl create namespace ai-platform
kubectl create namespace logging
kubectl create namespace nginx-demo
```

### 6.2 部署AI Platform

```bash
# 部署Ollama
kubectl apply -f environments/prod/apps/ai-platform/ollama-stack.yaml

# 部署OpenWebUI
kubectl apply -f environments/prod/apps/ai-platform/open-webui.yaml

# 部署HPA
kubectl apply -f environments/prod/apps/ai-platform/hpa.yaml

# 部署PDB
kubectl apply -f environments/prod/apps/ai-platform/pdb.yaml

# 部署Ingress
kubectl apply -f environments/prod/apps/ai-platform/ingress.yaml
```

### 6.3 部署Nginx Demo

```bash
# 部署Nginx Demo
kubectl apply -f environments/prod/apps/nginx-demo/

# 验证部署
kubectl get pods -n nginx-demo
```

### 6.4 部署Sealed Secrets

```bash
# 安装Sealed Secrets控制器
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.3/controller.yaml

# 验证安装
kubectl get pods -n kube-system -l name=sealed-secrets-controller
```

---

## 7. 验证部署

### 7.1 健康检查

```bash
# 运行健康检查脚本
bash scripts/health-check.sh

# 检查所有命名空间
kubectl get pods -A

# 检查服务
kubectl get svc -A

# 检查Ingress
kubectl get ingress -A
```

### 7.2 功能测试

```bash
# 测试Ollama API
curl http://<OLLAMA_SERVICE>:11434/api/tags

# 测试OpenWebUI
curl http://<OPENWEBUI_SERVICE>:8080/

# 测试Prometheus
curl http://<PROMETHEUS_SERVICE>:9090/-/healthy

# 测试Grafana
curl http://<GRAFANA_SERVICE>:3000/api/health

# 测试Loki
curl http://<LOKI_SERVICE>:3100/ready
```

### 7.3 监控验证

```bash
# 访问Grafana
open http://<GRAFANA_SERVICE>:3000

# 查看Kubernetes监控面板
# 查看AI Platform监控面板

# 测试告警
# 触发一个测试告警到微信
```

---

## 8. 性能测试

### 8.1 Locust压测

```bash
# 运行Locust测试
cd 03-benchmark
locust -f locustfile.py --host=http://<OPENWEBUI_SERVICE>:8080

# 并发测试
locust -f locustfile.py --headless -u 100 -r 10 --run-time 5m --host=http://<OPENWEBUI_SERVICE>:8080
```

### 8.2 k6测试

```bash
# 运行k6测试
k6 run 03-benchmark/k6-script.js
```

---

## 9. 故障排查

### 9.1 常见问题

#### Pod无法启动

```bash
# 查看Pod状态
kubectl get pods -n <namespace>

# 查看Pod详情
kubectl describe pod <pod-name> -n <namespace>

# 查看日志
kubectl logs <pod-name> -n <namespace> --previous
```

#### PVC无法绑定

```bash
# 检查StorageClass
kubectl get storageclass

# 检查PVC状态
kubectl get pvc -A

# 查看PVC详情
kubectl describe pvc <pvc-name> -n <namespace>
```

#### 网络问题

```bash
# 检查Service
kubectl get svc -n <namespace>

# 检查Endpoints
kubectl get endpoints -n <namespace>

# 测试连通性
kubectl exec -it <pod-name> -n <namespace> -- curl <service-name>:<port>
```

### 9.2 日志查看

```bash
# 查看Pod日志
kubectl logs <pod-name> -n <namespace> --tail=100

# 查看Previous容器日志
kubectl logs <pod-name> -n <namespace> --previous

# 查看所有容器日志
kubectl logs <pod-name> -n <namespace> --all-containers=true

# 实时查看日志
kubectl logs -f <pod-name> -n <namespace>
```

---

## 10. 维护操作

### 10.1 升级

```bash
# 升级应用
kubectl apply -f environments/prod/apps/ai-platform/

# 重启Pod
kubectl rollout restart deployment <deployment-name> -n <namespace>

# 查看升级状态
kubectl rollout status deployment <deployment-name> -n <namespace>
```

### 10.2 备份

```bash
# 备份K8s资源
kubectl get all -A -o yaml > backup-resources.yaml

# 备份Secrets
kubectl get secrets -A -o yaml > backup-secrets.yaml

# 备份PVC数据
kubectl exec -it <pod-name> -n <namespace> -- tar czf - /data > backup-data.tar.gz
```

### 10.3 恢复

```bash
# 恢复K8s资源
kubectl apply -f backup-resources.yaml

# 恢复Secrets
kubectl apply -f backup-secrets.yaml

# 恢复PVC数据
kubectl exec -it <pod-name> -n <namespace> -- tar xzf - /data < backup-data.tar.gz
```

---

## 11. 安全加固

### 11.1 RBAC配置

```bash
# 创建只读角色
kubectl apply -f environments/prod/infrastructure/rbac/readonly-role.yaml

# 创建应用管理员角色
kubectl apply -f environments/prod/infrastructure/rbac/app-admin-role.yaml
```

### 11.2 NetworkPolicy

```bash
# 部署NetworkPolicy
kubectl apply -f environments/prod/infrastructure/networking/network-policy.yaml
```

### 11.3 Pod安全策略

```bash
# 部署Pod Security Policy
kubectl apply -f environments/prod/infrastructure/security/psp.yaml
```

---

## 12. 监控告警配置

### 12.1 配置AlertManager

```yaml
# 编辑AlertManager配置
kubectl edit secret alertmanager-main -n monitoring

# 添加静默规则
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-main
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    route:
      receiver: 'wechat-adapter'
    receivers:
    - name: 'wechat-adapter'
      webhook_configs:
      - url: 'http://wechat-adapter-svc.monitoring.svc/webhook'
```

### 12.2 配置告警规则

```bash
# 查看告警规则
kubectl get prometheusrule -A

# 编辑告警规则
kubectl edit prometheusrule sre-lab-cluster-alerts -n monitoring
```

---

## 13. 卸载

### 13.1 卸载应用

```bash
# 删除AI Platform
kubectl delete -f environments/prod/apps/ai-platform/

# 删除Nginx Demo
kubectl delete -f environments/prod/apps/nginx-demo/
```

### 13.2 卸载监控栈

```bash
# 删除kube-prometheus-stack
helm uninstall prometheus-stack -n monitoring

# 删除命名空间
kubectl delete namespace monitoring
kubectl delete namespace logging
```

### 13.3 卸载ArgoCD

```bash
# 删除ArgoCD
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 删除命名空间
kubectl delete namespace argocd
```

### 13.4 卸载K3S

```bash
# 在Master节点执行
/usr/local/bin/k3s-uninstall.sh

# 在Agent节点执行
/usr/local/bin/k3s-agent-uninstall.sh
```

---

## 14. 快速命令参考

```bash
# 集群信息
kubectl cluster-info
kubectl get nodes
kubectl top nodes

# Pod管理
kubectl get pods -A
kubectl describe pod <name> -n <namespace>
kubectl logs <name> -n <namespace>
kubectl exec -it <name> -n <namespace> -- /bin/sh

# 部署管理
kubectl apply -f <file.yaml>
kubectl delete -f <file.yaml>
kubectl rollout status deployment <name> -n <namespace>
kubectl rollout restart deployment <name> -n <namespace>

# 扩缩容
kubectl scale deployment <name> --replicas=3 -n <namespace>
kubectl autoscale deployment <name> --min=1 --max=5 -n <namespace>

# 端口转发
kubectl port-forward svc/<service-name> 8080:80 -n <namespace>

# 资源清理
kubectl delete pods -n <namespace> --field-selector=status.phase!=Running
kubectl delete pvc -n <namespace> --field-selector=status.phase!=Bound
```

---

**文档版本**: v1.0.0
**最后更新**: 2026-06-20
**维护者**: 云原生架构专家
