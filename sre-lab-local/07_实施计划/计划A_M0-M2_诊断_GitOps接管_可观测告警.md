# 计划 A:M0–M2 实施计划(诊断 / GitOps 接管 / 可观测告警)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把一个运行 43 天、状态未知的 k3d 集群诊断清楚,用 ArgoCD 完成 GitOps 接管,并建立"故障 → 指标 → 告警 → 手机"的完整闭环。

**Architecture:** 原地改造 `k3d-ai-cluster`。ArgoCD 以 pull 模式接管存量 workload,同步策略按应用性质分级(基础设施 `selfHeal: true` / 开发中应用 `false`)。可观测层复用已在运行的 kube-prometheus-stack,补齐 Loki/Promtail 日志链路与企业微信告警通道,用 Chaos Mesh 做故障注入来验证闭环真的能响。

**Tech Stack:** k3d / k3s / Helm / ArgoCD / kube-prometheus-stack / Loki / Promtail / Alertmanager / Chaos Mesh / Sealed Secrets / 企业微信机器人

**Spec:** `sre-lab-local/00_设计定稿.md`

---

## Global Constraints

> 每个 Task 的要求都隐含包含本节。这些是**纪律**,不是建议。

1. **所有 `kubectl` / `helm` 命令必须显式带 `--context k3d-ai-cluster`**
   —— 教训来源:`06_踩坑记录.md` P1。多集群下不带 `--context` 的命令**不报错**,只是安静地作用在错误的集群上。
2. **任何 k8s 清单都必须入 Git**,不做长期手工 `kubectl apply`(首次接管存量除外)
3. **任何步骤失败/报错,先写 `06_踩坑记录.md` 再继续**,不允许"先跳过回头再记"
4. **每个 Task 完成后更新** `06_踩坑记录.md`(有新坑则记)与 `99_决策日志.md`(有决策则记)
5. **镜像 tag 一律用 git short sha**,禁用 `latest`
6. **不碰 `k3d-topo-demo` 集群**(项目三资产,只读)
7. **内存纪律**:每个 Task 开始前跑 `free -h`,可用内存低于 2 GiB 时先排查再加组件
8. **破坏性动作前先留档**:改动任何存量资源前,先 dump 它的当前 YAML
9. **`k3d-topo-demo` 是当前 kubeconfig 的默认 context**
   —— 所以约束 1 尤其重要,一不小心就操作错集群
10. **零注释纪律**:所有写进仓库的代码/清单/脚本**一律不写注释、不做自然语言标注**
    —— 阈值依据、参数来源、设计理由**一律写进文档**(`03_runbook/` / `99_决策日志.md` / `05_学习笔记/`),不写进代码。
    **本计划正文中的 YAML 代码块写于该规则确立之前,含有解释性注释;落盘到仓库时必须全部剥离**,解释内容移到对应的文档里。
    理由:重决策轻源码——代码里的注释是第二个真相来源,只会和文档重复甚至冲突

---

## 文件结构

```
sre-lab-local/
├── 00_设计定稿.md                          [已有] 设计与选型
├── 05_学习笔记/                            [已有] 概念科普
├── 06_踩坑记录.md                          [已有] 报错记录
├── 99_决策日志.md                          [已有] ADR
├── 01_排障记录/                            [M0 产出]
│   ├── 00_改造前基线/                      ← 改造前的完整状态快照
│   ├── 01_vllm异常诊断.md
│   ├── 02_组件重启诊断.md
│   └── 03_监控覆盖盘点与差距表.md
└── 02_接管记录/                            [M1 产出]
    ├── 01_接管策略与踩坑.md
    ├── 02_同步策略对照实验.md
    └── 03_分级配置定稿.md
```

**GitOps 仓库侧**(ArgoCD 消费的真相来源,在 `sre-lab-gitops/` 下):

```
sre-lab-gitops/production/
├── bootstrap/           [已有] App-of-Apps 入口
├── apps/                [已有] 各应用清单
│   ├── ai-platform/     ← ArgoCD 接管的第一个目标(手工 apply 的,易)
│   └── game-server/     ← M4 新增
└── monitoring/          ← ArgoCD 接管第二个目标(Helm 管理的,难)
```

---

# M0:诊断与基线

> **时间盒**:0.5 天
> **这一阶段的产出不是"修好",而是"搞明白"**。每个异常都要有根因结论和证据命令。
> **翻车预案**:如果诊断下来发现故障平淡(如仅因 WSL 无 GPU),**如实告知用户并转清场重建方案**,不硬凑素材。

---

### Task 1:基线与安全网

**Files:**
- Create: `sre-lab-local/01_排障记录/00_改造前基线/`(整个目录)

**Interfaces:**
- Produces: 改造前的完整状态快照,后续任何"改坏了"都能对照回滚

**为什么先做这个:** 改造前不留档,出问题就失去了"原来是什么样"的参照。这是运维的基本纪律。

- [ ] **Step 1: 释放内存 —— 停掉闲置集群**

```bash
k3d cluster list
# 预期:ai-cluster / ew-cluster / topo-demo 三个

k3d cluster stop ew-cluster
# ew-cluster 只有 mockrouter,是闲置的。topo-demo 是项目三资产,不动。

free -h
# 记录可用内存
```

- [ ] **Step 2: 建立基线目录并 dump 集群状态**

```bash
CTX=k3d-ai-cluster
OUT=~/projects/sre-lab/sre-lab-local/01_排障记录/00_改造前基线
mkdir -p "$OUT"

# 集群骨架
kubectl --context $CTX get nodes -o wide          > "$OUT/nodes.txt"
kubectl --context $CTX get ns                     > "$OUT/namespaces.txt"
kubectl --context $CTX get all -A -o wide         > "$OUT/all-resources.txt"
kubectl --context $CTX get pvc,ingress,svc -A     > "$OUT/storage-network.txt"

# 逐命名空间完整 YAML(可回滚的凭据)
for ns in ai-platform monitoring kube-system default; do
  kubectl --context $CTX -n "$ns" get all -o yaml            > "$OUT/ns-$ns-all.yaml"
  kubectl --context $CTX -n "$ns" get cm,secret,pvc,ingress \
          -o yaml                                            > "$OUT/ns-$ns-config.yaml"
done

# Helm 与运行时
helm list -A --kube-context $CTX                 > "$OUT/helm-releases.txt"
helm repo list                                   > "$OUT/helm-repos.txt"
docker system df                                 > "$OUT/docker-df.txt"
kubectl --context $CTX get events -A --sort-by=.lastTimestamp | tail -100 > "$OUT/events-tail.txt"
```

- [ ] **Step 3: 验证基线文件非空**

```bash
wc -l "$OUT"/*.txt "$OUT"/*.yaml
# 预期:每个文件行数 > 0。若某个为 0 行,说明该命名空间为空或命令失败,需查明。
```

- [ ] **Step 4: 提交**

```bash
cd ~/projects/sre-lab
git add sre-lab-local/01_排障记录/00_改造前基线/
git commit -m "chore(m0): 改造前集群基线快照"
```

---

### Task 2:诊断 vllm-3b 的 6 个异常 Pod

**Files:**
- Create: `sre-lab-local/01_排障记录/01_vllm异常诊断.md`

**Interfaces:**
- Consumes: Task 1 的基线目录
- Produces: 每个异常 Pod 的「根因 / 证据命令 / 处置建议」,M1 接管时的依据

**背景:** `vllm-3b` 有 6 个 Pod:5 个 `ContainerStatusUnknown`、1 个 `UnexpectedAdmissionError`。`ContainerStatusUnknown` 通常意味着节点重启或容器被强制清理;`UnexpectedAdmissionError` 是**准入阶段**失败(资源不够、被驱逐、配额限制)。

**诊断原则:从外往里查 —— 先看 Pod 状态 → 看 Event → 看 Init/主容器日志 → 看节点资源 → 看 GPU。**

- [ ] **Step 1: 记录现象原文**

```bash
CTX=k3d-ai-cluster
kubectl --context $CTX -n ai-platform get pods -o wide > /tmp/vllm-pods.txt
kubectl --context $CTX -n ai-platform get deploy vllm-3b -o yaml > /tmp/vllm-deploy.yaml
kubectl --context $CTX -n ai-platform get rs -l app=vllm-3b -o wide
```

**观察点**:6 个 Pod 分属几个 ReplicaSet?是不是一个 Deployment 反复重建留下的**僵尸 Pod**?

- [ ] **Step 2: 查 Event —— 准入类错误的第一现场**

```bash
kubectl --context $CTX -n ai-platform get events --sort-by=.lastTimestamp | tail -50
kubectl --context $CTX -n ai-platform describe pod <那个 UnexpectedAdmissionError 的 Pod>
```

**观察点**:`UnexpectedAdmissionError` 的 Event 里通常会直接写原因(如 `insufficient nvidia.com/gpu`、`evicted`、`preempted`)。**这一条大概率是破案关键。**

- [ ] **Step 3: 查资源请求与节点可分配资源**

```bash
kubectl --context $CTX -n ai-platform get deploy vllm-3b \
  -o jsonpath='{.spec.template.spec.containers[0].resources}' | python3 -m json.tool

kubectl --context $CTX get nodes -o custom-columns=\
NAME:.metadata.name,\
CPU:.status.allocatable.cpu,\
MEM:.status.allocatable.memory,\
GPU:.status.allocatable.'nvidia\.com/gpu'
```

**观察点**:如果 `vllm-3b` 请求 `nvidia.com/gpu: 1` 而节点**没有 GPU 可分配**(WSL 环境很可能如此),那根因就是「**资源永远无法满足**」——僵尸 Pod 会一直堆积。

- [ ] **Step 4: 查日志(容器已经死了,要看前一次)**

```bash
# ContainerStatusUnknown 的容器已经不存在,只能看上一个容器的日志
kubectl --context $CTX -n ai-platform logs <pod> --previous --tail=50

# 如果 --previous 也拿不到,说明容器从未成功启动过
kubectl --context $CTX -n ai-platform describe pod <pod> | grep -A5 "Last State"
```

- [ ] **Step 5: 查节点是否发生过重启(ContainerStatusUnknown 的典型成因)**

```bash
kubectl --context $CTX get nodes -o jsonpath=\
'{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].lastTransitionTime}{"\n"}{end}'

kubectl --context $CTX get pods -A | grep -v Running | grep -v Completed
```

**观察点**:`ContainerStatusUnknown` + 其他 Pod 也重启多 → 大概率是**节点级事件**(Docker Desktop / WSL 重启导致 k3d 节点容器重启),不是 vllm 自己的问题。

- [ ] **Step 6: 写诊断记录**

在 `01_vllm异常诊断.md` 按此结构写(**必须包含证据命令和实际输出**):

```markdown
## 结论
<一句话根因>

## 证据链
1. 命令:`...` → 输出:`...` → 说明:`...`
2. ...

## 每个 Pod 的处置建议
| Pod | 状态 | 处置 |
|---|---|---|

## 对 M1 接管的影响
<这些 Pod 该不该纳入 GitOps?僵尸 Pod 怎么清理?>
```

- [ ] **Step 7: 提交**

```bash
git add sre-lab-local/01_排障记录/01_vllm异常诊断.md
git commit -m "docs(m0): vllm-3b 异常 Pod 诊断"
```

---

### Task 3:诊断各组件高重启次数

**Files:**
- Create: `sre-lab-local/01_排障记录/02_组件重启诊断.md`

**背景:** monitoring 命名空间的组件重启 6~24 次,`ai-infra-gateway` 重启 6 次。24 次是个不正常的数字,需要区分「节点重启导致的重启」和「组件自身崩溃导致的重启」。

- [ ] **Step 1: 拉出所有高重启组件**

```bash
CTX=k3d-ai-cluster
kubectl --context $CTX get pods -A --sort-by='.status.containerStatuses[0].restartCount' \
  -o custom-columns='NS:.metadata.namespace,POD:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,STATUS:.status.phase' \
  | tail -20
```

- [ ] **Step 2: 区分两类原因 —— 看 Last State**

```bash
CTX=k3d-ai-cluster
for p in $(kubectl --context $CTX -n monitoring get pods -o name); do
  echo "=== $p ==="
  kubectl --context $CTX -n monitoring get $p \
    -o jsonpath='{.status.containerStatuses[0].lastState}' 2>/dev/null
  echo
done
```

**关键判断**:
- `lastState.terminated.reason: OOMKilled` → **内存不够**,真问题
- `lastState.terminated.exitCode: 0` + 同一时刻 → 节点重启的连带效应,**不是组件的锅**
- `lastState.terminated.reason: Error` + exitCode 非 0 → 组件自身崩溃,要查日志
- `state.waiting.reason: CrashLoopBackOff` → 正在崩溃循环,要查日志

- [ ] **Step 3: 查节点重启时间点,与 Pod 重启时间对齐**

```bash
CTX=k3d-ai-cluster
docker ps --filter "name=k3d-ai-cluster" --format '{{.Names}}\t{{.Status}}'
# 看 k3d 节点容器的 Up 时长 —— 这就是节点最后一次重启的时间

kubectl --context $CTX get pods -A -o jsonpath=\
'{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\t"}{.status.containerStatuses[0].lastState.terminated.finishedAt}{"\n"}{end}' \
  | sort -k3
```

**观察点**:如果所有组件的 `finishedAt` 时间点高度集中,且与节点容器 Up 时长对得上 → **结论:重启是节点级事件导致的,不是组件问题**。这会大幅改变 M0 的结论。

- [ ] **Step 4: 对 OOMKilled 的组件专项分析**

```bash
CTX=k3d-ai-cluster
kubectl --context $CTX -n monitoring top pods 2>/dev/null || echo "metrics-server 可能不可用"
kubectl --context $CTX describe node k3d-ai-cluster-agent-0 | grep -A15 "Allocated resources"
```

- [ ] **Step 5: 写诊断记录并提交**

结构同上。**结论必须区分「真问题」与「节点事件连带」两类。**

```bash
git add sre-lab-local/01_排障记录/02_组件重启诊断.md
git commit -m "docs(m0): 组件重启次数诊断"
```

---

### Task 4:监控覆盖盘点与差距表

**Files:**
- Create: `sre-lab-local/01_排障记录/03_监控覆盖盘点与差距表.md`

**为什么重要:** 这是从"诊断"转到"补齐"的桥。不盘清楚有什么,后面就是盲目加组件。

- [ ] **Step 1: 清点已有的告警规则**

```bash
CTX=k3d-ai-cluster
# PrometheusRule 是 kube-prometheus-stack 的规则载体
kubectl --context $CTX -n monitoring get prometheusrule -o name

# 导出所有规则的 alert 名称
kubectl --context $CTX -n monitoring get prometheusrule -o json \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for item in d['items']:
    ns=item['metadata']['namespace']; nm=item['metadata']['name']
    for g in item['spec'].get('groups',[]):
        for r in g.get('rules',[]):
            if 'alert' in r:
                print(f\"{ns}/{nm}\t{g['name']}\t{r['alert']}\")
"
```

- [ ] **Step 2: 验证 Prometheus 真的加载了这些规则**

```bash
CTX=k3d-ai-cluster
kubectl --context $CTX -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3
curl -s localhost:9090/api/v1/rules | python3 -m json.tool | head -50
# 或者用浏览器开 http://localhost:9090/rules
kill %1
```

- [ ] **Step 3: 清点已有的抓取目标(是否只在抓默认指标)**

```bash
CTX=k3d-ai-cluster
kubectl --context $CTX -n monitoring get servicemonitor,podmonitor -o name
```

**观察点**:如果没有针对 `ai-infra-gateway` 的 ServiceMonitor,说明**业务指标根本没被抓** —— 那 M2 的"业务告警"就是空的。

- [ ] **Step 4: 写差距表**

对照 JD 要求逐项打勾:

```markdown
# 监控覆盖盘点与差距表

## 已有(可用)
| 维度 | 现状 | 证据 |
|---|---|---|
| 节点指标 | node-exporter ×3 | ... |
| K8s 对象指标 | kube-state-metrics | ... |
| GPU 指标 | gpu-exporter DaemonSet | ... |
| 告警规则 | <N> 条 | ... |

## 缺失(要在 M2 补)
| 缺口 | 影响 | 补齐方案 |
|---|---|---|
| 日志聚合 | 出故障只能 kubectl logs 逐个查 | Loki + Promtail |
| 业务指标 | 看不到 gateway 的 QPS/延迟/错误率 | ServiceMonitor |
| 告警出口 | 规则触发了没人知道 | Alertmanager + 通知网关 + 企业微信 |
| 故障注入 | 无法主动验证告警是否有效 | Chaos Mesh |

## 结论
M2 的目标是把「缺失」四行全部补上,其中**告警出口是硬指标**(手机必须真的收到)。
```

- [ ] **Step 5: 提交,并给用户一份 M0 总结**

```bash
git add sre-lab-local/01_排障记录/03_监控覆盖盘点与差距表.md
git commit -m "docs(m0): 监控覆盖盘点与差距表"
```

**M0 完成标志**:`01_排障记录/` 下四个成果齐全,且**每个异常都有根因结论**,不是"现象描述"。

---

# M1:ArgoCD 接管存量

> **时间盒**:1.5 天
> **这一阶段是本次实操最有价值的部分** —— 接管 Helm 管理的资源、处理所有权冲突、观察同步策略行为,都是真实企业里最高频也最容易翻车的动作。

---

### Task 5:安装 ArgoCD

**Files:**
- Create: `sre-lab-gitops/production/bootstrap/argocd-app.yaml`(后续用于自管理)

**Interfaces:**
- Produces: 可用的 ArgoCD 实例 + 已登录的 CLI

- [ ] **Step 1: 加 Helm 仓库并安装**

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --kube-context k3d-ai-cluster \
  --namespace argocd --create-namespace \
  --set server.service.type=ClusterIP \
  --wait
```

- [ ] **Step 2: 验证 Pod 全部 Running**

```bash
kubectl --context k3d-ai-cluster -n argocd get pods
# 预期:argocd-application-controller-0 / argocd-repo-server / argocd-server
#       / argocd-redis / argocd-applicationset-controller 全部 Running
```

- [ ] **Step 3: 取初始密码并登录 CLI**

```bash
kubectl --context k3d-ai-cluster -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# 端口转发访问 UI
kubectl --context k3d-ai-cluster -n argocd port-forward svc/argocd-server 8080:443 &
# 浏览器打开 https://localhost:8080  用户名 admin,密码取上一步的值

argocd login localhost:8080 --username admin --insecure --grants-password
```

- [ ] **Step 4: 记录到踩坑记录(至少记录端口转发/证书相关的坑)**

- [ ] **Step 5: 提交**

```bash
git add -A sre-lab-local/
git commit -m "feat(m1): 安装 ArgoCD"
```

---

### Task 6:整理 GitOps 仓库结构

**Files:**
- Modify: `sre-lab-gitops/production/`(结构调整)
- Create: `sre-lab-local/02_接管记录/01_接管策略与踩坑.md`

**为什么:** ArgoCD 消费的是 Git 里的清单。现有 `sre-lab-gitops/production/` 是当年手写的,不一定符合 ArgoCD 的目录约定。

- [ ] **Step 1: 盘点现有 YAML 与集群实际资源的一致性**

```bash
# 对照 Task 1 的基线,逐项检查 Git 里的 YAML 是否与集群实际一致
diff <(kubectl --context k3d-ai-cluster -n ai-platform get deploy -o name | sort) \
     <(find ~/projects/sre-lab/sre-lab-gitops/production/apps/ai-platform -name '*.yaml' | sort)
```

**这一步的目的**:发现「Git 里写的」和「集群里跑的」有多少差异。**差异多少直接决定接管的难度。**

- [ ] **Step 2: 把集群实际状态回写进 Git(重要)**

**接管的原则是「让 Git 先等于现状,再谈变更」** —— 如果 Git 和现状不一致就直接开 auto-sync,ArgoCD 会立刻把集群改成 Git 的样子,**可能把正在跑的东西改坏**。

```bash
# 对每个要接管的工作负载,用实际状态覆盖 Git 里的定义
for d in ai-infra-gateway ollama cyberrouter-operator; do
  kubectl --context k3d-ai-cluster -n ai-platform get deploy $d -o yaml \
    | grep -v 'kubectl.kubernetes.io/last-applied-configuration' \
    | grep -v 'creationTimestamp: ' \
    | grep -v 'resourceVersion:' \
    | grep -v 'uid:' \
    > ~/projects/sre-lab/sre-lab-gitops/production/apps/ai-platform/$d.yaml.actual
done
# 人工 diff 后合并
```

> ⚠️ **此处必然出现第一个决策点**:Git 里的清单和集群实际不一致时,**以哪个为准**?
> 原则:**先以集群实际为准**(保运行),把"应该改什么"留到 M1 之后单独做变更。

- [ ] **Step 3: 文档化接管策略**

在 `02_接管记录/01_接管策略与踩坑.md` 写清:

```markdown
## 接管策略

### 目标 A:ai-platform(手工 apply 的)
- 管理方式:纯 kubectl apply,无工具管理
- 策略:直接纳管,处理"资源已存在"的 adopt
- 风险:低

### 目标 B:monitoring + kube-system(Helm 管理的)
- 管理方式:Helm release(monitoring / traefik / traefik-crd)
- 策略:<待 Task 8 确定>
- 风险:高 —— Helm 与 ArgoCD 的所有权可能冲突

### 为什么分成两件事
（这里写你在 Task 6 Step 1 的 diff 里实际看到了什么）
```

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "docs(m1): 接管策略与 Git/集群差异盘点"
```

---

### Task 7:接管 ai-platform(第一类:手工管理的)

**Files:**
- Create: `sre-lab-gitops/production/bootstrap/ai-platform-app.yaml`
- Modify: `sre-lab-gitops/production/bootstrap/root-app.yaml`

**Interfaces:**
- Consumes: Task 6 整理好的清单
- Produces: ArgoCD Application 对象,后续所有接管都复用这个模式

- [ ] **Step 1: 先创建 Application,但【不】开 auto-sync**

```yaml
# sre-lab-gitops/production/bootstrap/ai-platform-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ai-platform
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/fei232401/sre-lab.git
    targetRevision: main
    path: sre-lab-gitops/production/apps/ai-platform
  destination:
    server: https://kubernetes.default.svc
    namespace: ai-platform
  syncPolicy:
    # ⚠️ 故意不写 automated —— 先看 ArgoCD 报告什么,再决定动不动手
    syncOptions:
      - CreateNamespace=false
```

```bash
kubectl --context k3d-ai-cluster apply -f sre-lab-gitops/production/bootstrap/ai-platform-app.yaml
```

- [ ] **Step 2: 观察 ArgoCD 报告的状态(不要动手)**

```bash
kubectl --context k3d-ai-cluster -n argocd get application ai-platform -o wide
argocd app get ai-platform
```

**预期看到的**:`OutOfSync` + 一堆资源差异。**这个状态本身就是学习材料** —— 记录下来,写进 `06_踩坑记录.md`。

- [ ] **Step 3: 看清差异清单,判断哪些是"无害差异"**

```bash
argocd app diff ai-platform
```

**常见无害差异**(应通过 `ignoreDifferences` 或修正 Git 消除):
- `spec.replicas`(HPA 会改)
- `metadata.annotations` 里的 `kubectl.kubernetes.io/last-applied-configuration`
- 默认填充的字段(`dnsPolicy`、`terminationMessagePath`、`schedulerName`…)

- [ ] **Step 4: 处理"资源已存在"的所有权问题**

```bash
# 方式:给现有资源打上 ArgoCD 的 tracking 注解,让它"认领"现有资源
kubectl --context k3d-ai-cluster -n ai-platform annotate deploy ai-infra-gateway \
  argocd.argoproj.io/tracking-id="ai-platform:/Deployment:ai-platform/ai-infra-gateway" \
  --overwrite
# 对每个资源重复
```

> ⚠️ **此处是关键踩坑点**:不做这一步,ArgoCD 会认为资源不属于它,同步时可能报冲突或重复创建。**每一个报错都记进 `06_踩坑记录.md`。**

- [ ] **Step 5: 执行同步并验证**

```bash
argocd app sync ai-platform
argocd app wait ai-platform --timeout 300

kubectl --context k3d-ai-cluster -n ai-platform get pods
# 预期:所有原有 Pod 仍在运行(replicas 未被改变)
```

**验证标准**:同步后**工作负载的副本数、镜像 tag 与同步前一致**。用 Task 1 的基线对照。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "feat(m1): ArgoCD 接管 ai-platform"
```

---

### Task 8:接管 monitoring(第二类:Helm 管理的)—— 最难的一步

**Files:**
- Create: `sre-lab-gitops/production/bootstrap/monitoring-app.yaml`
- Create: `sre-lab-local/02_接管记录/01_接管策略与踩坑.md`(追加)

**为什么难:** `monitoring` 命名空间的资源由 Helm release 管理。ArgoCD 和 Helm 都会声明对资源的"所有权",两者打架会导致:
- ArgoCD 报 `OutOfSync` 但同步无效果
- 或同步后 Helm 认为 release 被篡改

**三种可选策略**(在 Step 1 评估,Step 2 选定):

| 策略 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **A. ArgoCD 用 Helm source 渲染** | Application 的 source 指向 Helm chart + values | 保留 Helm 的价值(可升级、values 管理) | 需要把现有 release 的 values 导出;接管过程复杂 |
| **B. 只读监控,不接管** | Application 加 `IgnoreExtraneous`,ArgoCD 不碰 Helm 资源 | 零风险 | 这部分没真正 GitOps 化,故事不完整 |
| **C. 导出成纯清单** | `helm get manifest` 导出,改由 ArgoCD 管理,卸载 Helm release | 彻底,最"GitOps" | 丢失 Helm 的升级能力 |

- [ ] **Step 1: 导出 Helm release 的完整信息**

```bash
CTX=k3d-ai-cluster
helm get values monitoring -n monitoring --kube-context $CTX > /tmp/monitoring-values.yaml
helm get manifest monitoring -n monitoring --kube-context $CTX > /tmp/monitoring-manifest.yaml
helm get metadata monitoring -n monitoring --kube-context $CTX

wc -l /tmp/monitoring-manifest.yaml /tmp/monitoring-values.yaml
```

- [ ] **Step 2: 选定策略并记录理由到 `99_决策日志.md`**

> **建议策略 A**(ArgoCD 用 Helm source):它是行业标准做法,且最能体现"你懂 GitOps 和 Helm 怎么共存"。但如果你评估后觉得风险过高,**选 B 也完全可以** —— 重要的是**你评估过并留下了理由**。

**无论选哪个,都要在 `99_决策日志.md` 加一条 D6**,格式:背景 / 三个选项 / 决定 / 理由 / 后果代价。

- [ ] **Step 3: 创建 Application 并同步**

```yaml
# 若选策略 A:
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 87.19.1        # ← 必须与集群现有版本一致(Task 1 的 helm-releases.txt 里有)
    helm:
      values: |
        # ← 从 /tmp/monitoring-values.yaml 粘贴
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    syncOptions:
      - CreateNamespace=false
      - Prune=false            # 观察期内禁止删除
```

- [ ] **Step 4: 观察并处理冲突(这里会踩最多坑)**

```bash
argocd app get monitoring
argocd app diff monitoring
```

**典型问题与排查方向**:
- `Sync failed: one or more objects failed to apply` → 看具体是哪个对象,通常是 ownership 冲突
- 一直 `OutOfSync` 但 diff 为空 → 可能是 `last-applied-configuration` 注解差异,加 `ignoreDifferences`
- Helm 侧报 release 被改动 → Helm 的 release secret 与 ArgoCD 争夺资源

**每一个具体报错都按 `06_踩坑记录.md` 的模板记录**(现象/排查过程/根因/解法/经验)。

- [ ] **Step 5: 验证监控功能未被破坏**

```bash
kubectl --context k3d-ai-cluster -n monitoring get pods
# 预期:Prometheus / Grafana / Alertmanager / node-exporter 全部 Running

kubectl --context k3d-ai-cluster -n monitoring port-forward svc/monitoring-grafana 3000:80 &
# 浏览器开 http://localhost:3000,确认能登录、能看到面板
```

**这一步是硬验证**:接管不能把监控搞坏。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "feat(m1): ArgoCD 接管 monitoring(Helm 管理的资源)"
```

---

### Task 9:同步策略对照实验 + 分级配置定稿

**Files:**
- Create: `sre-lab-local/02_接管记录/02_同步策略对照实验.md`
- Create: `sre-lab-local/02_接管记录/03_分级配置定稿.md`
- Modify: 各 Application 的 `syncPolicy`

**为什么这是 M1 最有价值的一步:** 用户当年正是因为同步策略配置不当而对 ArgoCD 产生负面印象。**亲手验证三个开关的行为,是理解 GitOps 最短的路径。**

- [ ] **Step 1: 实验① —— 全关,观察手动改动**

```bash
# 现状:两个 Application 都没有 automated(全关)
kubectl --context k3d-ai-cluster -n ai-platform scale deploy ai-infra-gateway --replicas=0
sleep 30
argocd app get ai-platform | grep -i status
```

**预期**:ArgoCD 显示 `OutOfSync`,但**集群里 Pod 依然是 0 个**(它不动作)。
**记录**:同步策略全关时,ArgoCD 是"只报告不动手"的观察者。

```bash
kubectl --context k3d-ai-cluster -n ai-platform scale deploy ai-infra-gateway --replicas=1
```

- [ ] **Step 2: 实验② —— 开 selfHeal,观察漂移被纠正**

```bash
# 给 ai-platform 打开 auto-sync + selfHeal
argocd app set ai-platform --sync-policy automated --self-heal
# 注意:先确保集群状态与 Git 一致(否则 ArgoCD 会立刻同步)

sleep 60
kubectl --context k3d-ai-cluster -n ai-platform scale deploy ai-infra-gateway --replicas=0
echo "已手动改为 0,等待 ArgoCD 纠正..."
sleep 60
kubectl --context k3d-ai-cluster -n ai-platform get deploy ai-infra-gateway \
  -o jsonpath='{.spec.replicas}'; echo
```

**预期**:副本数**被自动改回 Git 里的值**。这就是用户当年"改动被应用失败"的真相。

**记录**:把时间戳也记下来 —— 从手动改到被纠正,过了多久?(面试可以讲"大约 X 秒")

- [ ] **Step 3: 实验③ —— 开 prune,观察 Git 删资源集群跟着删**

```bash
# 找一个无害的测试资源(不要拿真组件做实验)
cat <<'EOF' | kubectl --context k3d-ai-cluster -n ai-platform apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: prune-test
  namespace: ai-platform
data:
  foo: bar
EOF
# 但如果它不在 Git 里,ArgoCD 会把它当"多余资源"删掉 —— 这本身也是一次观察

# 更可控的做法:把一个资源加进 Git,同步,再从 Git 删掉,观察集群
```

**预期**:开了 prune 之后,Git 里删除的资源会在集群里被真正删除。

**⚠️ 这一步有真实删除风险,实验对象必须是测试资源。**

- [ ] **Step 4: 写对照实验记录**

```markdown
# 同步策略对照实验

| 配置 | 手动改副本数 | 观察结果 | 耗时 |
|---|---|---|---|
| 全关 | 1 → 0 | ArgoCD 报 OutOfSync,集群保持 0 | - |
| 开 selfHeal | 1 → 0 | 被自动改回 1 | <N> 秒 |
| 开 prune | 从 Git 删资源 | 集群里被删除 | <N> 秒 |

## 结论
- `selfHeal` 就是当年"改动丢失"的原因,它防的是**配置漂移**
- 个人开发环境烦人,生产环境保命
- 正确做法不是二选一,而是**按应用性质分级**
```

- [ ] **Step 5: 按分级固定配置**

```bash
# 基础设施类:开 selfHeal 防漂移
argocd app set monitoring --sync-policy automated --self-heal --auto-prune

# 开发中的应用:关 selfHeal,允许手动调试
argocd app set ai-platform --sync-policy automated  # 不加 --self-heal
```

在 `03_分级配置定稿.md` 里写清每个 Application 的配置和理由。

- [ ] **Step 6: 最终验证**

```bash
argocd app list
# 预期:所有 Application 都是 Synced + Healthy
```

**M1 完成标志**:① 两个 Application 都 Synced/Healthy;② 对照实验三项观察完成并有数据;③ 分级配置已固定并文档化。

- [ ] **Step 7: 提交**

```bash
git add -A && git commit -m "docs(m1): 同步策略对照实验与分级配置定稿"
```

---

# M2:可观测补齐 + 告警真响

> **时间盒**:1.5 天
> **本阶段的硬指标**:制造故障后,**手机在 3 分钟内真的收到告警**。做不到,M2 不算完。

---

### Task 10:部署 Loki + Promtail(日志链路)

**Files:**
- Create: `sre-lab-gitops/production/apps/loki/`(若已有则复用)
- Create: `sre-lab-gitops/production/bootstrap/loki-app.yaml`

**Interfaces:**
- Produces: Grafana 中可用的 Loki 数据源,label 为 `{namespace="...", pod="..."}`

- [ ] **Step 1: 检查 Git 里已有的 loki/promtail 清单**

```bash
ls -R ~/projects/sre-lab/sre-lab-gitops/production/apps/loki/
ls -R ~/projects/sre-lab/sre-lab-gitops/production/apps/promtail/
# 当年写过,先看能不能直接用
```

- [ ] **Step 2: 用 Helm 部署(推荐,比手写清单可靠)**

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --kube-context k3d-ai-cluster \
  --namespace monitoring \
  --set grafana.enabled=false \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=5Gi \
  --set loki.config.limits_config.retention_period=168h \
  --wait
```

**参数说明(每个都要能讲清来源)**:
- `grafana.enabled=false` — 复用已有的 Grafana,不重复部署
- `promtail.enabled=true` — Loki 本身只存,需要 Promtail 采集
- `retention_period=168h` — **本机内存/磁盘有限,7 天保留是显式选择,不是默认值**
- `persistence.size=5Gi` — 本机 759G 可用,5G 是够用的保守值

- [ ] **Step 3: 验证日志能查到**

```bash
kubectl --context k3d-ai-cluster -n monitoring get pods | grep -E 'loki|promtail'
# 预期:loki-0 Running,promtail-xxx 每个节点一个 Running

# 在 Grafana 里加 Loki 数据源,或直接查 API
kubectl --context k3d-ai-cluster -n monitoring port-forward svc/loki 3100:3100 &
curl -s "localhost:3100/loki/api/v1/labels" | python3 -m json.tool
# 预期:能看到 namespace / pod / container 等 label
```

- [ ] **Step 4: 在 Grafana 查询真实日志验证**

```bash
kubectl --context k3d-ai-cluster -n monitoring port-forward svc/monitoring-grafana 3000:80 &
# 浏览器 → Explore → 选 Loki → 查询 {namespace="ai-platform"}
```

**验证标准**:能看到 `ai-infra-gateway` 的实时日志。

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat(m2): 部署 Loki + Promtail 日志链路"
```

---

### Task 11:补齐业务指标(ServiceMonitor)

**Files:**
- Create: `sre-lab-gitops/production/monitoring/gateway-monitor.yaml`

**背景:** Task 4 若发现 `ai-infra-gateway` 没有 ServiceMonitor,说明**业务指标根本没被抓**,业务告警无从谈起。

- [ ] **Step 1: 确认 gateway 是否暴露了 /metrics**

```bash
kubectl --context k3d-ai-cluster -n ai-platform port-forward svc/ai-infra-gateway 8000:8000 &
curl -s localhost:8000/metrics | head -30
```

**观察点**:
- 有输出 → 直接接 ServiceMonitor
- 404 / 无输出 → **需要先给应用加 metrics 端点**。`sre-lab/01-gateway-server/` 里有原代码,看它当年是怎么暴露指标的

- [ ] **Step 2: 写 ServiceMonitor**

```yaml
# sre-lab-gitops/production/monitoring/gateway-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ai-infra-gateway
  namespace: monitoring
  labels:
    release: monitoring        # ← 必须匹配 kube-prometheus-stack 的 selector,否则不生效
spec:
  namespaceSelector:
    matchNames:
      - ai-platform
  selector:
    matchLabels:
      app: ai-infra-gateway    # ← 必须匹配 Service 的 label
  endpoints:
    - port: http
      interval: 30s
      path: /metrics
```

> ⚠️ **两个 `label` 是新手最常踩的坑**:ServiceMonitor 本身要有 Prometheus 能选中的 label,它的 `selector` 又要能选中目标 Service。**对不上就静默不生效**(不报错,只是没数据)。

- [ ] **Step 3: 验证指标被抓到**

```bash
kubectl --context k3d-ai-cluster apply -f sre-lab-gitops/production/monitoring/gateway-monitor.yaml
sleep 60

kubectl --context k3d-ai-cluster -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
# 浏览器 → Status → Targets,找 ai-infra-gateway,状态必须是 UP
curl -s 'localhost:9090/api/v1/targets' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    if 'gateway' in str(t['labels']): print(t['labels'], t['health'])
"
```

**验证标准**:Target 状态为 `up`。若为 `down`,看 `lastError` 字段。

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "feat(m2): 接入业务指标 ServiceMonitor"
```

---

### Task 12:部署通知网关 + 打通企业微信

**Files:**
- Create: `sre-lab-gitops/production/monitoring/notify-gateway.yaml`
- Modify: `sre-lab-gitops/production/monitoring/kube-prometheus-stack` 的 Alertmanager 配置

**Interfaces:**
- Consumes: 用户提供的企业微信机器人 webhook URL
- Produces: `http://notify-gateway.monitoring.svc:8080/webhook` 供 Alertmanager 调用

**为什么需要一个「通知网关」而不是让 Alertmanager 直连企业微信:**
1. 可以做**扇出**(同时推企业微信 + 归档到 Loki)
2. **解耦** —— 换通知渠道不用改 Alertmanager 配置
3. 企业微信要求的消息格式比较特殊,需要一个转换层

- [ ] **Step 1: ⚠️ 先向用户索取企业微信机器人 webhook**

**需要用户操作**:企业微信 → 新建群(或个人群)→ 群机器人 → 添加 → 复制 Webhook 地址。

格式形如:`https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=<UUID>`

**在拿到之前不要继续本 Task。**

- [ ] **Step 2: 把 webhook 存进 k8s Secret(先不上 Sealed Secrets)**

```bash
kubectl --context k3d-ai-cluster -n monitoring create secret generic wecom-webhook \
  --from-literal=url='<用户提供的URL>'
```

> ⚠️ 注意:这一步是**临时**的。Task 13 会把它正规化为 Sealed Secrets。**绝不把这个 URL 提交进 Git。**

- [ ] **Step 3: 写通知网关 Deployment**

```yaml
# sre-lab-gitops/production/monitoring/notify-gateway.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notify-gateway
  namespace: monitoring
  labels:
    app: notify-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notify-gateway
  template:
    metadata:
      labels:
        app: notify-gateway
    spec:
      containers:
        - name: gateway
          image: python:3.12-slim
          command: ["/bin/sh", "-c"]
          args:
            - |
              pip install --quiet flask requests && python /app/main.py
          env:
            - name: WECOM_WEBHOOK_URL
              valueFrom:
                secretKeyRef:
                  name: wecom-webhook
                  key: url
          volumeMounts:
            - name: app
              mountPath: /app
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { cpu: 200m, memory: 128Mi }
          livenessProbe:
            httpGet: { path: /healthz, port: 8080 }
            initialDelaySeconds: 20
          readinessProbe:
            httpGet: { path: /healthz, port: 8080 }
            initialDelaySeconds: 10
      volumes:
        - name: app
          configMap:
            name: notify-gateway-src
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: notify-gateway-src
  namespace: monitoring
data:
  main.py: |
    import os, json, logging
    from flask import Flask, request, jsonify
    import requests

    app = Flask(__name__)
    logging.basicConfig(level=logging.INFO)

    WECOM_URL = os.environ["WECOM_WEBHOOK_URL"]

    def render(alert):
        firing = alert.get("status") == "firing"
        icon = "🔴 触发" if firing else "✅ 恢复"
        name = alert["labels"].get("alertname", "Unknown")
        sev  = alert["labels"].get("severity", "unknown")
        desc = alert.get("annotations", {}).get("description", "")
        lines = [
            f"### {icon}: {name}",
            f"- **级别**: {sev}",
            f"- **说明**: {desc}",
        ]
        for k, v in alert["labels"].items():
            if k not in ("alertname", "severity"):
                lines.append(f"- **{k}**: {v}")
        return "\n".join(lines)

    @app.route("/healthz")
    def healthz():
        return "ok"

    @app.route("/webhook", methods=["POST"])
    def webhook():
        data = request.get_json(force=True)
        alerts = data.get("alerts", [])
        if not alerts:
            return jsonify(ok=True, sent=0)

        content = "\n\n".join(render(a) for a in alerts)
        payload = {"msgtype": "markdown", "markdown": {"content": content}}
        r = requests.post(WECOM_URL, json=payload, timeout=5)
        logging.info("wecom resp: %s %s", r.status_code, r.text)
        return jsonify(ok=True, sent=len(alerts)), 200
---
apiVersion: v1
kind: Service
metadata:
  name: notify-gateway
  namespace: monitoring
  labels:
    app: notify-gateway
spec:
  selector:
    app: notify-gateway
  ports:
    - name: http
      port: 8080
      targetPort: 8080
```

- [ ] **Step 4: 部署并手工测试(关键)**

```bash
kubectl --context k3d-ai-cluster apply -f sre-lab-gitops/production/monitoring/notify-gateway.yaml

kubectl --context k3d-ai-cluster -n monitoring port-forward svc/notify-gateway 8080:8080 &

curl -X POST localhost:8080/webhook -H 'Content-Type: application/json' -d '{
  "alerts": [{
    "status": "firing",
    "labels": {"alertname": "TestAlert", "severity": "warning", "instance": "manual-test"},
    "annotations": {"description": "这是一条手工测试告警,用来验证企业微信通道是否打通"}
  }]
}'
```

**验证标准**:**手机上的企业微信群应该立刻收到一条消息。**

⚠️ **收不到就停下排查**,不要继续。排查方向:
1. `kubectl logs -n monitoring deploy/notify-gateway` 看有没有异常
2. 企业微信返回的 `errcode` 是不是 0(常见 93000 = webhook 无效)
3. Secret 里的 URL 是否正确挂载:`kubectl exec -n monitoring deploy/notify-gateway -- env | grep WECOM`

- [ ] **Step 5: 配置 Alertmanager 指向通知网关**

```bash
kubectl --context k3d-ai-cluster -n monitoring get secret alertmanager-monitoring-kube-prometheus-alertmanager -o yaml > /tmp/am-secret.yaml
```

Alertmanager 配置通过 `alertmanager.yaml` 这个 key 提供:

```yaml
global:
  resolve_timeout: 5m
route:
  group_by: ['alertname', 'namespace']
  group_wait: 30s          # 首次告警等 30s,把同组告警一起发
  group_interval: 5m       # 同组新告警的间隔
  repeat_interval: 4h      # 未恢复的告警重复通知间隔
  receiver: 'wecom'
  routes:
    - matchers: ['severity="critical"']
      receiver: 'wecom'
      group_wait: 10s      # 严重告警快速发出
      repeat_interval: 1h
receivers:
  - name: 'wecom'
    webhook_configs:
      - url: 'http://notify-gateway.monitoring.svc:8080/webhook'
        send_resolved: true      # ← 恢复通知也要发
inhibit_rules:
  - source_matchers: ['severity="critical"']
    target_matchers: ['severity="warning"']
    equal: ['alertname', 'namespace']
```

**每个参数都要能讲清用途**(面试高频):
- `group_wait` — 消除告警抖动,同一问题的多条告警合并成一条
- `repeat_interval` — 防止同一告警把手机刷爆
- `send_resolved` — 故障恢复后也通知,否则你不知道好了没
- `inhibit_rules` — **抑制规则**:同组里已经有 critical,就不要再发对应的 warning

- [ ] **Step 5b: 把配置写进 Git(必须走 Git,不能手工改 Secret)**

**为什么不能直接改 Secret**:监控栈在 M1 已经被 ArgoCD 接管。手工改 Secret 会被 `selfHeal` 纠正回去(这正是 Task 9 实验验证过的行为)。**配置必须回到 Git 里。**

```bash
# 方式:kube-prometheus-stack 的 values 里增加 alertmanager 配置段
# 编辑 sre-lab-gitops/production/monitoring/ 下的 values 或 Application 的 helm.values
#
# 关键路径:Alertmanager 配置最终由 kube-prometheus-stack 渲染成
#   secret/alertmanager-monitoring-kube-prometheus-alertmanager 的 alertmanager.yaml 键
```

把 Step 5 那段 `alertmanager.yaml` 内容作为 `alertmanager.config` 放进去:

```yaml
alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'wecom'
      routes:
        - matchers: ['severity="critical"']
          receiver: 'wecom'
          group_wait: 10s
          repeat_interval: 1h
    receivers:
      - name: 'wecom'
        webhook_configs:
          - url: 'http://notify-gateway.monitoring.svc:8080/webhook'
            send_resolved: true
    inhibit_rules:
      - source_matchers: ['severity="critical"']
        target_matchers: ['severity="warning"']
        equal: ['alertname', 'namespace']
```

```bash
cd ~/projects/sre-lab
git add -A && git commit -m "feat(m2): Alertmanager 告警路由与企业微信 receiver"
git push origin main
argocd app sync monitoring
argocd app wait monitoring --timeout 300
```

- [ ] **Step 6: 验证 Alertmanager 配置生效**

```bash
kubectl --context k3d-ai-cluster -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 &
# 浏览器 → http://localhost:9093/#/status 看配置是否加载

# 确认 ArgoCD 没有因为手工操作产生漂移
argocd app get monitoring | grep -i status
# 预期:Synced(如果这里出现 OutOfSync,说明有手工改动没进 Git —— 正是 Task 9 验证过的行为)
```

- [ ] **Step 7: 提交**

```bash
git add -A && git commit -m "feat(m2): 通知网关与企业微信告警通道"
```

---

### Task 13:修复 PushPlus token 泄露(Sealed Secrets)

**Files:**
- Modify: `sre-lab-gitops/production/monitoring/wechat-adapter.yaml`
- Create: `sre-lab-gitops/production/apps/sealed-secrets/*`(若已有则复用)

**背景:** 见 `00_设计定稿.md` §2.4。`wechat-adapter.yaml` 里 PushPlus token 明文硬编码,而仓库是公开的。

- [ ] **Step 1: 轮换 token(需要用户操作)**

**用户登录 pushplus 后台**,作废旧 token,生成新的。**旧的已经被公开,必须作废,不只是改代码。**

- [ ] **Step 2: 部署 Sealed Secrets 控制器(若集群内没有)**

```bash
kubectl --context k3d-ai-cluster get pods -A | grep sealed-secrets
# 若无:
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --kube-context k3d-ai-cluster --namespace kube-system --wait
```

- [ ] **Step 3: 安装 kubeseal CLI**

```bash
# 见 https://github.com/bitnami-labs/sealed-secrets/releases
KUBESEAL_VERSION=0.27.0
curl -sL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" \
  | tar xz -C /tmp kubeseal
sudo install -m 755 /tmp/kubeseal /usr/local/bin/kubeseal
kubeseal --version
```

- [ ] **Step 4: 生成 SealedSecret**

```bash
kubectl --context k3d-ai-cluster -n monitoring create secret generic pushplus-token \
  --from-literal=token='<新token>' \
  --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets --controller-namespace kube-system \
      --format yaml \
  > ~/projects/sre-lab/sre-lab-gitops/production/apps/sealed-secrets/pushplus-token.yaml

cat ~/projects/sre-lab/sre-lab-gitops/production/apps/sealed-secrets/pushplus-token.yaml
# 验证:文件里 token 是加密的密文,不是明文
```

- [ ] **Step 5: 修改 wechat-adapter,从 Secret 读 token**

把原来硬编码的 `PUSHPLUS_TOKEN = "28ea..."` 改成:

```python
PUSHPLUS_TOKEN = os.environ.get("PUSHPLUS_TOKEN", "")
```

并在 Deployment 里加:

```yaml
env:
  - name: PUSHPLUS_TOKEN
    valueFrom:
      secretKeyRef:
        name: pushplus-token
        key: token
```

- [ ] **Step 6: 验证修复有效**

```bash
# 确认 pod 内的环境变量是加密存储的,且 Git 里搜不到明文 token
grep -rn "28ea" ~/projects/sre-lab/ && echo "❌ 还有明文残留" || echo "✅ 已清理"
```

- [ ] **Step 7: 写进面试话术素材 + 提交**

```bash
git add -A && git commit -m "fix(security): PushPlus token 明文泄露修复(Sealed Secrets + 轮换)"
```

---

### Task 14:扩充告警规则(awesome-prometheus-alerts)

**Files:**
- Modify: `sre-lab-gitops/production/monitoring/cluster-alerts.yaml`
- Create: `sre-lab-local/03_runbook/告警规则说明.md`

**决定依据:** `99_决策日志.md` D5 —— 采用现成规则库,但**规则来源和阈值依据要写清楚**。

- [ ] **Step 1: 从规则库挑选规则**

来源:https://github.com/samber/awesome-prometheus-alerts(templates 目录)

**选择原则**:
- 只选**你真正关心的**,不是全抄。抄 300 条规则的人会被问"这些你都看得懂吗"
- 每条规则都要能说出**为什么是这个阈值**

重点挑选(对应本集群真实场景):
- 节点:CPU / 内存 / 磁盘 / 负载
- K8s:Pod 未就绪 / 容器重启 / Deployment 副本不足 / PVC 将满
- 容器资源:CPU throttling / 内存接近 limit
- 已有规则(节点内存/CPU/磁盘/PVC/CrashLoop)直接保留

- [ ] **Step 2: 阈值依据写进文档,不写进 YAML(Global Constraint 10)**

**规则文件本身保持零注释**,阈值依据统一写进 `sre-lab-local/03_runbook/告警规则说明.md`。

规则文件长这样:

```yaml
    - alert: NodeHighMemoryUsage
      expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 80
      for: 5m
```

依据写在文档里:

```markdown
# 告警规则说明

## NodeHighMemoryUsage
- **来源**: awesome-prometheus-alerts(node-exporter 模板)
- **官方阈值**: 80%
- **本机调整**: warning 80% / critical 92%
- **依据**: 本机 19GiB 内存,监控栈常驻约 8GiB,长期占用率本身偏高;
  用 `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` 跑一周基线的实测值定档
- **面试怎么讲**: "参考了社区规则库,但按本机实测基线调过" —— 不是照抄
```

**为什么**:面试官问"你这些阈值哪来的",依据在手边就能答;而 YAML 里的注释没人看、还会和文档冲突。

- [ ] **Step 3: 应用并验证规则加载**

```bash
kubectl --context k3d-ai-cluster apply -f sre-lab-gitops/production/monitoring/cluster-alerts.yaml
sleep 30
# Prometheus UI → Alerts 页面,确认新规则已加载
```

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "feat(m2): 扩充告警规则(含阈值依据注释)"
```

---

### Task 15:部署 Chaos Mesh(故障注入)

**Files:**
- Create: `sre-lab-gitops/production/apps/chaos-mesh/`(或 Helm 安装)

**为什么用它:** `99_决策日志.md` D5 —— CRD 声明式定义故障,故障本身也能 GitOps 化。

- [ ] **Step 1: 安装**

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

helm install chaos-mesh chaos-mesh/chaos-mesh \
  --kube-context k3d-ai-cluster \
  --namespace chaos-mesh --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/k3s/containerd/containerd.sock \
  --version 2.7.0 \
  --wait
```

> ⚠️ **k3d 的运行时是 containerd 不是 docker**,`runtime` 和 `socketPath` 必须改,否则 chaos-daemon 起不来。**这里大概率会踩坑,记进 `06_踩坑记录.md`。**

- [ ] **Step 2: 验证 chaos-daemon 在每个节点都 Running**

```bash
kubectl --context k3d-ai-cluster -n chaos-mesh get pods -o wide
# 预期:chaos-controller-manager Running
#       chaos-daemon-xxxxx 每个节点一个,全部 Running
```

- [ ] **Step 3: 用一个无害的故障实验验证它能工作**

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress-test
  namespace: default
spec:
  mode: one
  selector:
    labelSelectors:
      app: <某个测试应用的 label>
  stressors:
    cpu:
      workers: 1
      load: 80
  duration: '2m'
```

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "feat(m2): 部署 Chaos Mesh 故障注入平台"
```

---

### Task 16:端到端告警演练(本阶段的最终验收)

**Files:**
- Create: `sre-lab-local/03_runbook/告警演练.md`
- Create: `sre-lab-gitops/production/chaos/`(故障实验清单,入 Git)

**这是 M2 的 DoD。做不到"手机真的响",前面 15 个 Task 都白做。**

- [ ] **Step 1: 写一个会在 3 分钟内触发告警的故障实验**

选一个**阈值低、触发快**的规则做验证,比如节点 CPU:

```yaml
# sre-lab-gitops/production/chaos/cpu-stress-drill.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress-drill
  namespace: monitoring
spec:
  mode: all
  selector:
    namespaces: [monitoring]
    labelSelectors:
      app.kubernetes.io/name: prometheus-node-exporter
  stressors:
    cpu:
      workers: 2
      load: 95
  duration: '5m'
```

- [ ] **Step 2: 计时执行演练**

```bash
date '+%H:%M:%S' > /tmp/drill-start.txt
kubectl --context k3d-ai-cluster apply -f sre-lab-gitops/production/chaos/cpu-stress-drill.yaml
echo "故障已注入,开始计时..."
```

**记录**:注入时刻 → 告警触发时刻 → 手机收到时刻。

- [ ] **Step 3: 验证告警链路每一环**

```bash
# ① Prometheus 是否产生了告警
kubectl --context k3d-ai-cluster -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
curl -s localhost:9090/api/v1/alerts | python3 -c "
import json,sys
for a in json.load(sys.stdin)['data']['alerts']:
    print(a['labels'].get('alertname'), a['state'], a['activeAt'])
"

# ② Alertmanager 是否收到
kubectl --context k3d-ai-cluster -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 &
curl -s localhost:9093/api/v2/alerts | python3 -m json.tool | head -30

# ③ 通知网关是否发出
kubectl --context k3d-ai-cluster -n monitoring logs deploy/notify-gateway --tail=20

# ④ 手机是否收到 ← 人工确认
```

- [ ] **Step 4: 验证恢复通知**

```bash
kubectl --context k3d-ai-cluster delete -f sre-lab-gitops/production/chaos/cpu-stress-drill.yaml
# 等待告警恢复,确认手机收到 ✅ 恢复通知
```

- [ ] **Step 5: 写演练 runbook**

```markdown
# 告警演练 Runbook

## 演练目标
验证「故障 → 指标 → 规则 → Alertmanager → 通知网关 → 企业微信 → 手机」全链路

## 实测数据
| 环节 | 时刻 | 耗时 |
|---|---|---|
| 故障注入 | hh:mm:ss | - |
| Prometheus 告警触发 | hh:mm:ss | +Xs |
| Alertmanager 接收 | hh:mm:ss | +Xs |
| 手机收到 | hh:mm:ss | +Xs |

## 遇到的坑
（引用 06_踩坑记录.md 的条目）

## 告警没发出的排查路径(重要!)
从后往前查:
1. 手机没收到 → 看 notify-gateway 日志
2. notify-gateway 没调用 → 看 Alertmanager 的 Alert 列表
3. Alertmanager 没收到 → 看 Prometheus 的 Alerts 页面
4. Prometheus 没触发 → 看规则表达式和 for 时长
5. 规则没加载 → 看 PrometheusRule 的 label 是否匹配
```

> **第 5 条排查路径本身就是最好的面试素材** —— "告警没响你怎么查"这个问题,大部分人答不上来。

- [ ] **Step 6: 最终验收**

```bash
argocd app list          # 全部 Synced + Healthy
kubectl --context k3d-ai-cluster get pods -A | grep -v Running | grep -v Completed
# 预期:除已知的 vllm 僵尸 Pod 外,无异常
```

**M2 完成标志**:① 手机真的收到 🔴 触发 和 ✅ 恢复两条;② 演练 runbook 有实测数据;③ 排查路径已文档化。

- [ ] **Step 7: 提交并推送**

```bash
git add -A
git commit -m "feat(m2): 端到端告警演练跑通 + runbook"
git push origin main
```

---

# 阶段收口

**计划 A 完成后,应该拥有:**

1. 一份完整的集群诊断记录(每个异常都有根因)
2. 一个被 ArgoCD 完整接管的集群(两种接管策略都实践过)
3. 一套按应用性质分级的同步策略,以及三项对照实验的真实数据
4. Prometheus + Grafana + Loki 的完整可观测栈
5. **一个真的会响的告警通道**(手机收到过)
6. Chaos Mesh 故障注入能力
7. 一条修好的安全漏洞(PushPlus token)

**然后**:向用户汇报,写计划 B(M3–M5:Jenkins CI + 发布回滚演练 + 收口)。
