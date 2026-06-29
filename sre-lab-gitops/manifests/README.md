# 01-baseline-manifests (归档参考)

> ⚠️ 此目录**不参与 GitOps 部署**，仅作为初始模板参考。

生产环境使用 `02-gitops-production/` 目录，由 ArgoCD App of Apps 管理。

---

## 资源清单

### cloud-native-ai/ — AI 推理平台核心

| 文件 | 资源类型 | 说明 |
|------|---------|------|
| `namespace.yaml` | Namespace | ai-platform 命名空间 |
| `ollama-stack.yaml` | StatefulSet + Service | Ollama 推理引擎 + Headless + PVC |
| `open-webui.yaml` | Deployment + PVC | Open WebUI 前端 |
| `ingress.yaml` | Ingress | Traefik 路由 `/` → Open WebUI |
| `hpa.yaml` | HorizontalPodAutoscaler ×2 | Ollama + WebUI 自动扩缩容 |
| `pdb.yaml` | PodDisruptionBudget ×2 | 优雅终止保障 |

### monitoring-stack/ — 监控告警体系

| 文件 | 资源类型 | 说明 |
|------|---------|------|
| `prometheus-ingress.yaml` | Ingress | `/prometheus` 路由 |
| `grafana-ingress.yaml` | Ingress | `/grafana` 路由 |
| `cluster-alerts.yaml` | PrometheusRule | 集群级告警规则 |
| `k3s-alert-patches.yaml` | PrometheusRule | K3S 特定告警修复 |
| `ollama-exporter.yaml` | HelmRelease/Config | Ollama 指标导出 |
| `ollama-monitor-fix.yaml` | ServiceMonitor | Ollama 监控采集修复 |
| `nginx-monitor.yaml` | ServiceMonitor | Nginx 监控采集 |
| `wechat-adapter.yaml` | ConfigMap | WeChat 告警适配器配置 |
