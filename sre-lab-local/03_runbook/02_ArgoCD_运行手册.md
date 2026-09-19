# ArgoCD 运行手册

- **建立**:2026-09-16
- **ArgoCD 版本**:chart `argo/argo-cd` 10.9.1 / app `v3.5.3`
- **安装方式**:Helm upgrade
- **部署位置**:`argocd` 命名空间,全部 Pod 钉在 `agent-1`(`global.nodeSelector: {node-role: cpu}`)

---

## 一、多集群纪律(最容易出静默事故的地方)

**本机有多个 k3d 集群,`kubectl` / `helm` / `argocd` 都隐式使用 kubeconfig 的当前 context。**

不显式指定 context 的后果不是报错,而是**安静地作用在另一个集群上**。

```bash
kubectl config get-contexts          # 先看清楚有哪几个
kubectl --context k3d-ai-cluster ... # 本项目所有命令都带这个
helm    --kube-context k3d-ai-cluster ...
```

> **本项目纪律:所有 `kubectl` / `helm` 命令显式带 context,无一例外。**
>
> 详情见 `06_踩坑记录.md` 的 P1。

---

## 二、Git 拉取超时 15 秒:**是瞬时的,会自愈**

### 现象

```
grpc.time_ms=15001.801
... Client.Timeout exceeded while awaiting headers
```

卡在 **15 秒零 1 毫秒**上。

### 行为特征

| 特征 | 值 |
|---|---|
| 超时值 | **硬编码 15 秒**,无环境变量可调 |
| 触发条件 | 通常是**冷连接**(DNS + TLS 握手),WSL2 + 国内网络下偶发 |
| 后续 | **ArgoCD 默认约每 3 分钟重新对账一次**,下一次连接是热的,通常就过了 |
| 是否需要干预 | **通常不需要**。这是收敛式控制器的正常工作方式 |

### 验证超时不可配(已实测)

```bash
grep -ao 'ARGOCD_REPO_SERVER_[A-Z_]*' /usr/local/bin/argocd-repo-server | sort -u
```

结果里**没有任何与 Git 操作超时相关的变量**。

### 如果你怀疑它挂了

先强制刷新,再判断:

```bash
kubectl --context k3d-ai-cluster -n argocd annotate application <name> \
  argocd.argoproj.io/refresh=hard --overwrite
```

### ⚠️ 排查纪律:先看时间戳,再下结论

**一次采样 = 一个瞬时快照,不等于系统状态。**

本项目实际踩过这个坑(P10):我查到报错、判断成"网络持久故障",但**被接管的对象其实 3 分钟前就创建成功了**,我查到的是一个已经被重试覆盖掉的中间状态。

**正确的第一步**是去看对象的创建时间 / 状态持续时间:

```bash
kubectl --context k3d-ai-cluster -n <ns> get deploy <name> \
  -o jsonpath='{.metadata.creationTimestamp}'
```

如果创建时间是几分钟前、期间没有新的失败 —— 大概率已经自愈了。

---

## 三、`Application` 的同步策略与目录语义

### 当前各 App 的 `source.path`

| Application | path | 性质 |
|---|---|---|
| `sealed-secrets` | `sre-lab-gitops/production/apps/sealed-secrets` | 纯清单 |
| `monitoring-app` | `sre-lab-gitops/production/monitoring` | 纯清单 |
| 其余子 App | `sre-lab-gitops/production/apps/*` | 纯清单 |

### ⚠️ 硬规则:监视目录里不能放非清单文件

ArgoCD 会把 `source.path` 下**所有 YAML 当成 k8s 清单去 apply**。

**Helm values 文件必须放在监视目录之外。** 本项目放在 `production/helm-values/` —— 该路径不在任何 Application 的 `source.path` 内。

> **规律:GitOps 监视目录的边界就是语义边界。** 目录里放什么,决定了 ArgoCD 会对什么动手。

### ⚠️ 删除边界:不要把 cluster-scoped 资源交给 `prune: true`

`Namespace` 和 `CRD` 都是 cluster-scoped 的**删除边界**:删一个对象会级联删掉下面所有东西。交给 `prune: true` 等于在仓库里放一个"删一行 YAML 就删库"的开关。

| 资源 | 处置 |
|---|---|
| `Namespace` | 用 `CreateNamespace=true`,由 ArgoCD 按需创建但**不纳入生命周期管理** |
| `CRD`(如 `sealedsecrets.bitnami.com`) | 在清单里加 `argocd.argoproj.io/sync-options: Prune=false` |

### ⚠️ `Synced` 不等于"同步到了远端最新 commit"

**这是最容易骗过自己的一条。** `status.sync.status == Synced` 的含义是:

> "集群状态与 **ArgoCD 当前已知的那个 revision** 一致"

它与"仓库远端 HEAD"**没有任何关系**。ArgoCD 默认约 3 分钟轮询一次 Git,在这期间的窗口里:

- 你 push 了新 commit
- ArgoCD 仍停在旧 revision 上
- 它照样报 `Synced` / `Healthy` —— **因为相对那个旧 revision,集群确实是一致的**

**实测踩到**:push 删掉某个对象的 commit 后,ArgoCD 报 `Synced`,但被删的对象**还留在集群里**。一查 revision 才知道它还停在 push 之前那个 commit。

**正确做法:任何"我改了 Git,去验证集群"的动作,先核对 revision。**

```bash
kubectl --context k3d-ai-cluster -n argocd get application <app> \
  -o jsonpath='{.status.sync.revision}{"\n"}'
git rev-parse HEAD
```

两个值不一致时,不要等轮询,**直接触发 hard refresh**:

```bash
kubectl --context k3d-ai-cluster -n argocd annotate application <app> \
  argocd.argoproj.io/refresh=hard --overwrite
```

> **规律:`Synced` 是一个相对量,不是一个绝对量。** 凡是以"当前状态 == 期望状态"表述的健康信号,都要先问一句"期望状态是谁的期望、是哪个时刻的期望"。

### ⚠️ ArgoCD 的 Git 源:**一个必须能脱离集群存活的东西**

6 个 Application 的 `source.repoURL` 都是 `http://gitea:3000/fei232401/sre-lab.git`。也就是说 —— **ArgoCD 的全部收敛能力,押在一个集群外的 Git 服务上。**

2026-09-16 宿主重启后那个 Git 服务没了,6 条 Application 全部变成:

```
ComparisonError: failed to list refs: Get "http://gitea:3000/fei232401/sre-lab.git/info/refs?service=git-upload-pack":
dial tcp: lookup gitea on 10.43.0.10:53: no such host
```

> **关键认知:`Unknown` 期间发生的事不是"集群坏了",而是"没人再看它了"。** 工作负载照常跑,但**任何漂移都不会被纠正**,而且**不会有人收到通知**。

**三条设计结论(2026-09-17 起,依据 D18):**

| 结论 | 理由 |
|------|------|
| Git 服务必须**留在集群外** | 放进被它管理的集群 = **集群一灭,你连"从 Git 恢复"都做不到**(更深的自锁) |
| 它的**名字解析**必须由**集群内的声明式对象**提供 | 原先靠宿主机 docker DNS 的跨层副作用,容器一停即 `NXDOMAIN`。现改为在 `argocd` / `jenkins` 各放一份 selector-less Service + Endpoints |
| 它**不能是裸容器、无载体定义** | `RestartPolicy` 必须 `unless-stopped`,且有幂等重建脚本(`08_重建/gitea_up.sh`) |

> ⚠️ **一处新的、更隐蔽的失效可能**:Endpoints 里硬编码了 Gitea 容器的 IP。容器重建换了 IP → **k8s DNS 会抢先返回一个死端点**,报的是连接失败而不是 `NXDOMAIN`,**比原来更难看出来**。所以 `gitea_up.sh` 每次跑都会按**实际容器 IP** 重放这两个对象并核对。

**想确认 ArgoCD 的 Git 源是死是活,查这一处就够:**

```bash
kubectl --context k3d-ai-cluster -n argocd get applications \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,REV:.status.sync.revision'
```

只要出现 `Unknown`,先去看 `status.conditions` 里的 `ComparisonError` —— 那多半就是 Git 源的问题。

---

## 四、`monitoring-app` 的 apply 顺序(⚠️ 曾有硬约束,**现已解除**)

> 📌 **回填(2026-09-16 晚):本节描述的是一道曾经存在的窗口,现在窗口已经正常关闭。**
> 保留原文结构与教训,但**结论已更新**——按旧结论操作会与现实对不上。

**曾经的问题**:`production/monitoring/` 目录里有过一份 `wechat-adapter.yaml`,把 PushPlus token **明文硬编码在清单里**(见 D8 / D11)。清单是要进 Git 的,而 `monitoring-app` 一旦 apply,ArgoCD 会立刻把它部署进集群——**等于把明文凭证连人带文件一起推进生产**。

所以当时定下的顺序是硬性的:

```
1. 先重写/删除 wechat-adapter.yaml(D12 的适配器替换)
2. 确认目录里再没有任何明文凭证
3. 再 apply monitoring-app.yaml
```

**验证方法**(每次动 `monitoring-app` 之前都值得跑一遍):

```bash
grep -rniE "pushplus|PUSHPLUS_TOKEN|[0-9a-f]{32}" sre-lab-gitops/production/monitoring/
```

**目标状态是无输出。有输出就不要 apply。**

> ✅ **当前(2026-09-16 晚)实跑结果:无输出。**
>
> 该文件已删除,告警通道改为企业微信机器人 + `SealedSecret`(`sealed-alertmanager-smtp.yaml`)。
> `monitoring-app` 已于更早时候 apply,当前 **Synced / Healthy**,与 `sealed-secrets` 等共 6 个 Application 并存。
>
> **也就是说:第 1、2 步在 apply 之前完成了,这道约束没有被违反。** 本节由"待办"降级为"回归检查项"。

> ⚠️ **残留风险(如实记)**:那串 token 的**完整值仍在 git 历史里**(提交 `266b65a` / `3db3984b` 的 blob),且已随 `origin`(GitHub 公开镜像)推走;D11 决定**不吊销**该凭证,理由是项目已不再使用 PushPlus。也就是说:**它是"不再使用",不是"已失效"。** 谁拿到它,就还能往那个 PushPlus 账号的订阅者推消息。风险低但非零,决定已记录在案,此处只做如实标注。

---

## 五、常用命令

```bash
# 看所有 Application
kubectl --context k3d-ai-cluster -n argocd get applications

# 看某个 App 的详细状态(含同步失败原因)
kubectl --context k3d-ai-cluster -n argocd get application <name> -o yaml

# 强制重新对比(怀疑状态陈旧时)
kubectl --context k3d-ai-cluster -n argocd annotate application <name> \
  argocd.argoproj.io/refresh=hard --overwrite

# 看某个 App 管了哪些对象
kubectl --context k3d-ai-cluster -n argocd get application <name> \
  -o jsonpath='{.status.resources[*].kind}/{.status.resources[*].name}'

# 访问 UI
kubectl --context k3d-ai-cluster -n argocd port-forward svc/argocd-server 8080:443
```

---

## 六、本项目对上游 chart 的三处偏离

ArgoCD 上游 chart **完全不设 `resources`**(全部 `{}` = BestEffort QoS)。在内存吃紧的节点上,**BestEffort 是 kubelet 内存压力下第一个被驱逐的对象**。

`production/argocd/argocd-values.yaml` 因此:

| 偏离 | 原因 |
|---|---|
| 给 6 个组件都补了 `resources` | 避免 BestEffort 被优先驱逐 |
| `global.nodeSelector: {node-role: cpu}` | 全部钉到 agent-1 |
| `dex.enabled: false` | 不用 SSO,省一个组件 |

**注意一个 chart 的行为细节**:组件级的 `nodeSelector` 是**替换**而不是**合并** `global.nodeSelector`,不是叠加。本项目只用 `global` 一处,不受影响。

**实测结果**:6 个 Pod 全部落在 agent-1,实际内存 139Mi(而 requests 合计 640Mi)。

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-16 | 建立。收录多集群纪律、15s 超时行为、目录语义、apply 顺序约束 |
| 2026-09-17 | 新增「ArgoCD 的 Git 源:一个必须能脱离集群存活的东西」——记录 6 条 Application 全 `Unknown` 的机制、三条设计结论(D18)、以及 Endpoints 硬编码 IP 带来的新失效面 |
