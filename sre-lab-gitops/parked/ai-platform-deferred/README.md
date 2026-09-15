# parked/ai-platform-deferred

**这个目录不是 GitOps 监视路径。** 任何 Application 的 `source.path` 都不指向它,ArgoCD 不会读它。

放在这里的清单是**已写好但不部署**的,保留是为了不丢失工作成果,同时不让它们进入集群。

## 为什么移出来

`ai-platform-app` 原本的 `source.path` 是 `production/apps/ai-platform`,目录下 5 个文件里只有 `ollama-stack.yaml` 是"接管既有工作负载",其余的都是**新部署**。

把新部署混在接管目录里会带来一个具体问题:**ArgoCD 会因为"清单里有"就去创建它们**,而当时并不想上线这些服务。

## 各文件的处置原因

| 文件 | 内容 | 为什么移出 |
|---|---|---|
| `open-webui.yaml` | Service / Deployment / PVC | 全新部署,会上线一套 open-webui(含 20Gi 级别 PVC)。是否要上线是产品决定,不是接管决定 |
| `hpa.yaml` | `ollama-hpa` + `open-webui-hpa` | 见下 |
| `ingress.yaml` | `sre-lab-ingress` | 它的唯一 backend 是 `open-webui-service`,跟着 open-webui 一起移出 |
| `pdb-open-webui.yaml` | `open-webui-pdb` | 依赖 open-webui 的 Pod 标签,没有 Deployment 时它只是空转 |

### `hpa.yaml` 为什么单独说明

`ollama-hpa` 的 `scaleTargetRef` 写的是:

```yaml
scaleTargetRef:
  apiVersion: apps/v1
  kind: StatefulSet
  name: ollama
```

**集群里没有名为 `ollama` 的 StatefulSet,ollama 是一个 Deployment。** 实测:

```
$ kubectl -n ai-platform get sts ollama
Error from server (NotFound): statefulsets.apps "ollama" not found
```

所以这条 HPA 挂上去也永远不工作(会停在 `FailedGetScale`)。

**而且即使把 kind 改成 Deployment,也不建议直接启用**:`maxReplicas: 3` 配上 ollama 的 `limits.memory: 4Gi` 意味着峰值可到 12Gi,本环境(WSL2 单机 k3d)内存余量不足,有把节点打爆的风险。要启用的话,得先想清楚"给一个跑了 20Gi 模型卷的服务做 CPU 内存维度的横向扩容"这件事本身是否合理。

## 想启用时怎么做

1. 把对应文件 `git mv` 回 `production/apps/ai-platform/`
2. 若是 `hpa.yaml`,先修正 `ollama-hpa` 的 `scaleTargetRef.kind`
3. commit + push
4. ArgoCD 会自动同步(`ai-platform-app` 是 `automated`)
