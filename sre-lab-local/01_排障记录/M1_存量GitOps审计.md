# M1 审计报告:存量 GitOps 结构

- **日期**:2026-09-16
- **对象**:`sre-lab-gitops/` 全部 118 个文件,重点是 `production/` 的 31 个
- **结论**:**不能按原样部署 `root-app`。**

---

## 一、先理清:四份目录是怎么来的

`git log` 显示 `production/` 和 `k3s-ai-platform/environments/prod/` **出自同一个 commit**:

```
3db3984  2026-06-29  refactor: 迁移原目录至sre-lab-gitops/，更新ArgoCD路径
```

**那次重构做的是「复制」而不是「移动」。** 结果是四份内容同时存在:

| 目录 | 文件数 | 布局 | 状态 | 处置 |
|---|---|---|---|---|
| `production/` | 31 | 新(`apps/` + `bootstrap/` + `monitoring/`) | ✅ **路径正确,真相来源** | 保留 |
| `k3s-ai-platform/environments/prod/` | 31 | 新,同上 | ❌ **路径坏的** | **删** |
| `k3s-ai-platform/reference/baseline-manifests/` | 18 | 旧(`cloud-native-ai/` + `monitoring-stack/`) | 归档参考,README 明说不参与部署 | 保留 |
| `manifests/` | 17 | 旧,同上 | ❌ 与上一份**逐字节相同** | **删** |

### 判定"哪份是真相来源"的依据

不是看时间戳(两者同一次提交),而是看 **`root-app.yaml` 里的 `path` 能不能对上**:

| | `path` | 判定 |
|---|---|---|
| `production/bootstrap/root-app.yaml` | `sre-lab-gitops/production/bootstrap` | ✅ 对得上 |
| `k3s-ai-platform/.../prod/bootstrap/root-app.yaml` | `k3s-ai-platform/environments/prod/bootstrap` | ❌ **少了 `sre-lab-gitops/` 前缀** |

ArgoCD 的 `path` 是**相对仓库根目录**的。仓库根是 `sre-lab/`,所以正确路径必须带 `sre-lab-gitops/`。**旧那份的 path 指向一个不存在的目录,部署即报错。**

> **这是个可复用的判据:面对多份疑似副本,不要比时间戳,要比"自引用路径能不能闭合"。**

### 旧布局 vs 新布局的内容差异

`monitoring-stack/*` → `monitoring/*` **10 个文件全部逐字节未改**;`cloud-native-ai/*` → `apps/ai-platform/*` 有 **4 个文件改过**:

| 文件 | 差异 |
|---|---|
| `hpa.yaml` / `pdb.yaml` | 新布局补了中文注释 |
| `ollama-stack.yaml` / `open-webui.yaml` | **标签从规范的 `app.kubernetes.io/*` 退化成简化的 `app: ollama`** |

**标签退化不是疏忽,是刻意对齐现场**:集群里 `service/ollama-service` 的 selector 就是 `app=ollama`。旧布局那份"教科书式"的标签**反而和现场对不上**。

> 又一次印证:**已有的不等于正确的,但"看起来不规范的"也不等于错的。** 判定依据是现场,不是审美。

---

## 二、四颗雷

### 🔴 雷 1:`ai-platform-app` 会让 ollama 双跑

| | GitOps 定义 | 集群现状 |
|---|---|---|
| 工作负载 | **`StatefulSet/ollama`** | `Deployment/ollama` |
| Service | **`Service/ollama-service`** ← **同名** | `Service/ollama-service` |
| Service | `Service/ollama-headless` | (无) |
| selector | `app: ollama` | `app: ollama` ← **相同** |

**两次伤害叠加:**

1. **ArgoCD 接管 `Service/ollama-service`**(同名同命名空间)。`selfHeal: true` 下它会按 Git 版本覆盖现有 Service
2. **ArgoCD 新建 `StatefulSet/ollama`**——它的 Pod 同样带 `app: ollama` 标签
3. → **一个 Service 同时选中两套 Pod**,流量随机分发到 Deployment 版和 StatefulSet 版

**后果**:两套 ollama 各拉一份模型、各占一份内存。而 **agent-0 内存已 82%**(M0 发现 6)。

**隐蔽点**:光看 YAML 完全看不出来——`Service/ollama-service` 这个名字长得人畜无害,危险在于**它和集群里一个已有对象同名**。

> **教训:`GitOps 接管存量` 的第一步不是写 Application,是拿清单里的每个 `kind/name` 去和集群对一遍。**

### 🔴 雷 2:`Namespace/ai-platform` 被纳入管理 + `prune: true`

```yaml
kind: Namespace
metadata:
  name: ai-platform
  labels:
    app.kubernetes.io/managed-by: manual
```

`ai-platform-app` 的 `syncPolicy` 是 `prune: true`。

**这意味着命名空间本身成了一个被 ArgoCD 管理的资源。** 一旦 `namespace.yaml` 从 Git 里被删掉或改名,**ArgoCD 会 prune 掉整个 `ai-platform` 命名空间——连同里面所有工作负载和 PVC。**

Namespace 是 **cluster-scoped 的删除边界**。把它交给 `prune: true` 的 Application 管,等于在仓库里放了一个"删一行 YAML 就删库"的开关。

**正确做法**:`Namespace` 这类**边界资源**应该单独一个 Application、单独关掉 `prune`,或者干脆不纳入 GitOps(用 `CreateNamespace=true` 让 ArgoCD 按需创建)。

> 顺带注意那个 `managed-by: manual` 标签——**是当时的作者自己标注的"这是手工 apply 的"**。它正是 D4 说的"两套接管策略"的证据。

### 🟡 雷 3:`k3s-alert-patches.yaml` 坏了两层(第二层是实测发现的)

**第一层:标签不匹配,压根没被加载**

```yaml
kind: PrometheusRule
metadata:
  name: k3s-alert-overrides
  labels:
    prometheus: kube-prometheus
    role: alert-rules
    app.kubernetes.io/part-of: kube-prometheus-stack
```

而 Prometheus 实例实际的选择器是 `ruleSelector: {"matchLabels":{"release":"monitoring"}}`。**缺 `release: monitoring` → 永不加载。**

**第二层(更严重):就算标签对了,它也覆盖不掉默认告警**

修标签之前先做了个实验。用 `Watchdog` 当探针——它是 kube-prometheus-stack 里**设计上永远 firing** 的告警(表达式 `vector(1)`)。注入一条同名 `Watchdog`、表达式 `vector(0)`、**标签正确**的规则:

```
Prometheus 里名为 Watchdog 的规则:2 条        ← 并存,不是替换
[m1.experiment]  expr='vector(0)'  → 活跃告警 0
[general.rules]  expr='vector(1)'  → 活跃告警 1   ← 默认的照样在响
```

**默认告警毫发无伤。**

**根因:Prometheus 的告警是并列求值,不存在覆盖语义。** `alertname` 只是标签之一,不是主键;两条同名规则同时存在、同时求值。默认那条表达式为真,告警就为真——**另一条规则没有任何机制能取消它**。

**所以这个文件不是"改改标签就能用",是整条思路不成立。**

**正确的三条路**:

| 方案 | 做法 | 评价 |
|---|---|---|
| **停掉规则来源** | Helm values 里关掉对应组件 `enabled` | ✅ **最干净**,scrape target 一起消失 |
| **Alertmanager 静默** | 在路由/静默层拦截 | ✅ 有效,但规则仍在求值 |
| ~~同名规则覆盖~~ | — | ❌ **不成立** |

**处置:删除该文件**,降噪方案待 M2 定稿(见 `k3s-kubeproxy-silence.yaml` 那条路)。

> **通用教训:"用同名对象覆盖配置"的语义,每个系统都不一样。** Kubernetes 里是替换,Helm 里是升级,**Prometheus 里是并存**。换系统就要重新问一次,不能想当然。

### 🟡 雷 4:`grafana-servicemonitor-patch.yaml` 是三个维度上的空操作

这个比"名字对不上"更彻底——它**假设 Helm release 叫 `prometheus-stack`,而实际叫 `monitoring`**,于是三个维度全部错位:

| 维度 | 文件里写的 | 集群实际 | 后果 |
|---|---|---|---|
| 对象名 | `prometheus-stack-grafana` | `monitoring-grafana` | 不会 patch,而是**新建孤儿对象** |
| Service 选择器 | `app.kubernetes.io/instance: prometheus-stack` | `: monitoring` | 新对象**抓不到任何 target** |
| 加载标签 | `release: prometheus-stack` | `serviceMonitorSelector: release=monitoring` | Prometheus **根本不会加载它** |

**三重失效叠加的结果:创建出一个完全没有用的孤儿对象。**

**处置:删除该文件。** 若确需调整 Grafana 指标路径,应改 Helm values,而不是在旁边写一份旁路清单。

> **要改 Helm 管理的对象,出口只有 Helm values 一个。** 在它旁边放第二份同名以外的清单,只会制造重复与困惑。

### ⚠️ 附带风险:`monitoring-app` 会部署带明文 token 的 wechat-adapter

`wechat-adapter.yaml` 里硬编码了 PushPlus token(见 M0 安全发现)。一旦 `monitoring-app` 同步,这个 Deployment 就会被**真正部署进集群**——把一个"目前只是躺在仓库里"的问题变成"正在运行的服务"。

**必须先做 D8(token 轮换 + Sealed Secrets),再部署 monitoring-app。**

---

## 三、6 个子 Application 的风险分级

| Application | 目标命名空间 | 会新建什么 | 风险 |
|---|---|---|---|
| `monitoring-app` | monitoring | 10 个资源(告警规则 / Ingress / ServiceMonitor / **wechat-adapter**) | 🟡 低,但**须先做 token 轮换** |
| `ai-platform-app` | ai-platform | StatefulSet / WebUI / HPA / PDB / Ingress,并**接管已有 Service** | 🔴 **高,见雷 1、雷 2** |
| `loki` | logging | Loki Deployment(新命名空间) | 🟢 无冲突 |
| `promtail` | logging | Promtail DaemonSet(新命名空间) | 🟢 无冲突 |
| `nginx-demo-app` | nginx-demo | 5 个资源(新命名空间) | 🟢 无冲突 |
| `sealed-secrets` | sealed-secrets | controller(新命名空间) | 🟢 无冲突,**且是 D8 的前置** |

**注意:全部 6 个子 Application 都开了 `prune: true` + `selfHeal: true`** —— 与 D2「按应用性质分级」的决定**冲突**。这是 6/29 那一版写在 D2 之前的产物。

---

## 四、M1 修正后的执行顺序

原计划(M1 = 用 ArgoCD 接管存量)需要拆成:

1. **清理目录重复**(删 `manifests/`、删 `k3s-ai-platform/environments/prod/`)→ 定出唯一真相来源
2. **装 ArgoCD**,并把 ArgoCD 自身钉到 agent-1(`nodeSelector`,见 D7)
3. **修雷 3 / 雷 4**(标签选择器、ServiceMonitor 名字)
4. **按 D2 分级调整 syncPolicy**(不再全开 `prune` + `selfHeal`)
5. **处理雷 2**(Namespace 的接管策略)
6. **处理雷 1**(ollama 双跑)—— 这个需要单独拍板:是删掉 GitOps 里的 StatefulSet 版本改为对齐现场的 Deployment,还是接受迁移
7. **先只部署 `monitoring-app`**,验证闭环
8. **`ai-platform-app` 最后,且逐资源审计**
9. `loki` / `promtail` / `sealed-secrets` / `nginx-demo` 按 M2 需要顺序启用

---

## 四点五、附带发现:集群已有现成的节点标签约定

排查雷 1 时读取 `Deployment/ollama` 的实际规格,发现它有:

```yaml
nodeSelector:
  node-role: cpu
```

顺着查节点标签,发现**集群已经有一套按资源特征给节点分类的约定**:

| 节点 | 关键标签 | 角色 |
|---|---|---|
| `k3d-ai-cluster-agent-0` | `nvidia.com/gpu: "true"` | **GPU 节点** |
| `k3d-ai-cluster-agent-1` | **`node-role: cpu`** | **CPU 节点** |
| `k3d-ai-cluster-server-0` | `node-role.kubernetes.io/control-plane: "true"` | 控制面 |

**对 D7 的直接影响**:D7 原本写的是用 `kubernetes.io/hostname: k3d-ai-cluster-agent-1` 把 ArgoCD 钉到 agent-1。

**改用 `node-role: cpu` 更好**,理由:

1. **沿用集群已有的约定**,不引入第二套规则(现在同时存在 `hostname` 和 `node-role` 两种说法,后者更语义化)
2. **节点重建后名字会变,角色不会变**。k3d 集群重建时 agent 名字可能不同,但"CPU 节点"这个角色是稳定的
3. 与 `Deployment/ollama` 保持一致——它已经这么写了

**D7 修正为:`nodeSelector: {node-role: cpu}`。**

> 又一次印证本次审计的主题:**先看现场有什么约定,再决定新增什么。** 直接发明一个新标签不算错,但和已有的两套写法并存,就是自找混乱。

---

## 五、这次审计的通用经验

> **接管存量系统时,危险不来自"清单写了什么",而来自"清单和现场的交集"。**

四颗雷里有三颗是**静默**的:
- 雷 1 的 Service 同名(不报错,只是行为变了)
- 雷 3 的标签不匹配(不报错,规则就是不加载)
- 雷 4 的名字对不上(不报错,只是多了一份)

**没有一条会抛异常。** 这和 M0 的 P1(helm 查错集群)、P4(告警进 null receiver)是**同一类错误**:

> **本项目反复出现的主题——"不报错的错误",才是运维工作里最难发现的那一类。**

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-16 | 建立,记录 M1 存量审计全部结论 |
