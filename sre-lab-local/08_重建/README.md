# 08 重建

> **一句话**:把这套 sre-lab 环境从"一台什么都没装的机器"重建回来的脚本 + 它诚实的验证状态。

```
sre-lab-local/08_重建/
├── 重建.sh     重建脚本(分阶段,可单独跑)
└── README.md   本文件
```

---

## ⚠️ 先说清楚:这个脚本的验证状态

**这份脚本不是"照着敲一遍就能起来"的说明,它是"从一台活着的环境反推出来的重建路径"。** 两者的区别很大,必须先讲明。

| 性质 | 状态 |
|---|---|
| **三项静默失败验收**(`./重建.sh verify`) | ✅ **已对现场实跑,三项全过**(输出见下文) |
| 只读阶段(`check` / `coredns` / `verify`) | ✅ 已实跑 |
| `bash -n` 语法检查 | ✅ 通过 |
| **所有常量与状态描述**(IP、端口、镜像名、chart 版本、Secret 名、标签) | ✅ 来自现场 `docker inspect` / `kubectl get` 实测,非记忆 |
| **创建类阶段**(cluster / registry / gitea / argocd / jenkins / apps) | ❌ **未执行** —— 跑一遍会推平当前可用环境 |
| 全文 `# 待核实:` 标记数 | **34 行,集中在 6 个阶段** |

> **没有端到端跑过一遍,就不能说它能重建成功。** 下面那张表逐项列了"哪些是实测、哪些是反推"。

### `待核实` 是什么意思

脚本里 `# 待核实:` 开头的行 = **我没有亲自执行过、也无法从现场直接观测到的那条命令**。它们全都是"反推"性质:现场容器/Release 长什么样是我亲眼看到的,但**当初是哪条命令把它造成这样的,仓库里没有任何记录**。

所以每一处 `待核实` 旁边都写了**现场观测到的事实**(创建时间、RestartPolicy、镜像、环境变量),你可以据此判断反推是否合理。

### 六处 `待核实` 及各自的"怎么确认"

| 阶段 | 反推的命令 | 现场观测依据 | 怎么确认反推对不对 |
|---|---|---|---|
| 1 网络 | `docker network create ... --label app=k3d` | 网络创建于 **2026-07-25**,集群创建于 **2026-08-03**;带 `label: app=k3d`;`k3d.cluster.network.external=true` | 推断是**更早一个 k3d 集群**留下的网络。全新重建时 `k3d cluster create` 会自建同名网络,**大概率根本不用手工建** |
| 2 registry | `k3d registry create sre-registry --port 5111` | 容器名 `k3d-sre-registry`(k3d 命名规则:`k3d-<name>`);`RestartPolicy=unless-stopped`;挂**匿名卷** | 跑完后 `docker inspect k3d-sre-registry -f '{{.HostConfig.RestartPolicy.Name}}'` 应为 `unless-stopped` |
| 3 集群 | `k3d cluster create ... --agents 2 --gpus all --api-port 0.0.0.0:46121` | 1 server + 2 agent;两个 agent 都有 `DeviceRequests Count:-1 Capabilities:gpu`;API 端口 `46121`;k3s `v1.31.5-k3s1`;`--tls-san` 只有 k3d 默认值 | **这是最不确定的一步**。创建后比对 `docker inspect k3d-ai-cluster-server-0 --format '{{json .Config.Cmd}}'` |
| 4 标签 | `kubectl label node ...` | 现场 agent-0 带 `nvidia.com/gpu=true`、agent-1 带 `node-role=cpu`、server-0 两个都无 | 标签本身是实测的;反推的只是"怎么打上去的"。跑 `kubectl get nodes --show-labels` 比对 |
| 7 Gitea | `docker run ... gitea/gitea:1.22` | 6 个 `GITEA__*` 环境变量、端口 `3001:3000` / `2222:22`、named volume `gitea-data:/data`、**`RestartPolicy=no`** | 上述全部是 `docker inspect` 实测;**反推命令里我把它改成了 `unless-stopped`**,这是一处**故意偏离现场** |
| 10/11 Helm | `helm install ... --version <ver> -f <repo 里的 values>` | chart/app 版本、revision 数、release 名;且 Jenkins / ArgoCD 的现场 values **与仓库文件完全一致** | 这两个是**把握最大**的 —— values 一致意味着 `-f` 就能复现。monitoring 则不然,见下文 |

---

## 一、怎么用

```bash
cd ~/projects/sre-lab/sre-lab-local/08_重建

./重建.sh --help          # 看阶段列表
./重建.sh check           # 0  前置检查(端口占用、工具齐备)
./重建.sh 1               # 1  Docker 网络
./重建.sh 2               # 2  本地镜像仓库
...
./重建.sh verify          # 14 三项验收(只读,可随时跑)
./重建.sh all             # 0..14 依序执行(不含 snapshot)

./重建.sh snapshot        # S  拆除前导出 —— 见第二节,先跑这个
```

**分阶段跑,不要一上来就 `all`。** 每个阶段都会打印它期望看到的结果;`待核实` 的阶段不会硬闯,而是**打印出反推的命令然后停下**,让你人工确认后重跑。

**凭据处理**:全程不落盘明文。管理员密码从 K8s Secret 读,Gitea 令牌与 webhook token **交互式提示输入**。`snapshot` 是唯一会写敏感文件的操作,写在 `~/.sre-lab-secrets/`(**仓库之外**,权限 700)。

---

## 二、⚠️ 拆除之前:`./重建.sh snapshot`

**这一步是这次重建最有价值的部分,别跳过。**

现场实测发现:**monitoring 这个 Helm Release 的 values 与仓库里的 `monitoring-values.yaml` 对不上**。

| | 仓库文件的顶层键 | 现场 Release 的顶层键 |
|---|---|---|
| 内容 | `alertmanager` `kubeControllerManager` `kubeScheduler` `kubeProxy` | 前四个 **+** `grafana` `kubeStateMetrics` `nodeExporter` `prometheus` `prometheusOperator` |

现场比仓库**多 5 个顶层键**,其中至少两项会造成可观测的行为差异:

- `prometheus.prometheusSpec.storageSpec` → **10Gi PVC**(现场确实有一个 `prometheus-...-db-...` 的 10Gi PVC 绑着)
- `grafana.*` → 里面**含一个管理员密码**

> **这意味着:如果直接按仓库文件重建,你会得到一个和现在不一样的监控栈 —— 而且它不会报错,只会"少点什么"。**

所以 `snapshot` 会在动手删任何东西**之前**,把三个 Release 的现场 values 和 Sealed Secrets 私钥导出到 `~/.sre-lab-secrets/`:

| 文件 | 里面有什么 | 丢了会怎样 |
|---|---|---|
| `monitoring-live-values.yaml` | **含 grafana 管理员密码** | 重建后监控栈与现在不一致 |
| `jenkins-live-values.yaml` | 同仓库文件,导出只为保险 | — |
| `argocd-live-values.yaml` | 同仓库文件,导出只为保险 | — |
| `sealed-secrets.key.yaml` | **Sealed Secrets 私钥** | **全集群唯一能解开 SealedSecret 的钥匙**(当前只有 `monitoring/alertmanager-smtp` 一个),集群一换,所有 sealed 文件全部作废 |

> 这四个文件**永远不许进 Git**。`~/.sre-lab-secrets/` 在仓库外,就是为了让"手滑 `git add .`"不可能够到它。

---

## 三、顺序,以及为什么是这个顺序

这个顺序**不是随便排的**,每一步都在给后面铺路。搞错顺序的后果通常**不是报错,而是卡在半路**。

| # | 阶段 | 为什么必须在这个位置 |
|---|---|---|
| 0 | 前置检查 | 端口占用 / 工具缺失会让**后面每一步**都失败得很晚。先花 5 秒查掉 |
| 1 | Docker 网络 | 集群节点、registry、Gitea **都要挂在同一张网**上。registry 和 Gitea 必须能被集群**按容器名**解析(`k3d-sre-registry:5000`、`gitea:3000`),这是它们存在的**前提** |
| 2 | 本地镜像仓库 | **CI 的第一件事就是 push 镜像。** registry 不在,流水线跑到 `Push` 阶段才炸 |
| 3 | k3d 集群 | 依赖网络 |
| 4 | 节点标签 | **所有工作负载都靠 `nodeSelector` 选节点。** 标签晚打的症状是 Pod **Pending**,而人会去查资源、查污点,**不会想到是标签没打** |
| 5 | containerd 信任 | 必须在**任何 Pod 尝试拉本地镜像之前**。k3s 的 containerd 默认走 HTTPS,给 HTTP 仓库配 `certs.d` 即可,**不用重启 k3s**(见 `06_踩坑记录.md` P16) |
| 6 | CoreDNS | 集群内的名字解析 |
| 7 | Gitea 容器 | **它是个 Docker 容器,不是 K8s 工作负载** —— 所以它在集群"外面" |
| 8 | app.ini webhook 白名单 | ⚠️ **必须在创建 webhook 定义之前**,否则 Gitea 的 SSRF 防护会**静默拒绝**投递(见 `06_踩坑记录.md` P23)。改完要重启容器 |
| 9 | Gitea 仓库 + webhook 定义 | 依赖第 8 步已生效;同时依赖 Jenkins 已在跑(webhook 的 URL 指向 Jenkins NodePort) |
| 10 | ArgoCD | **必须先于所有 Application** —— Application 是 ArgoCD 的 CRD |
| 11 | Jenkins | 独立于 ArgoCD;但 `sre-lab-ci` 任务要读 Gitea 仓库,**所以必须在第 9 步之后** |
| 12 | Jenkins 任务 / 凭据 / ConfigMap | 任务引用的凭据(`gitea-webhook-token`)与 ConfigMap(`buildah-registries`)**必须先存在**,否则任务建得起来、跑起来才失败 |
| 13 | 六个 Application | 必须在 ArgoCD 就绪之后。**它们一旦 Synced,就会去集群里找自己管的东西** —— 前面所有阶段都是它们的前置条件 |
| 14 | 三项验收 | 见第四节 |

**几个会"静默卡住"的坑,单独拎出来:**

- **Gitea 的 `[webhook] ALLOWED_HOST_LIST`**:默认值会拒绝投递到私有网段。**失败只在 `docker logs gitea` 里报**,Gitea UI 上、Jenkins 上都看不出任何异常。这正是 `06_踩坑记录.md` P23。
- **Jenkins 插件安装是分钟级的**:init 容器会重新下载全部插件。`helm install --wait` **会超时失败,但那是假失败** —— 等下载完重跑一遍就 `deployed` 了。**不要把超时当成安装失败而回滚。**
- **Application 必须先于资源存在**:ArgoCD 的 `Application` 是 CRD。集群刚从零起来时,先 `kubectl apply` 工作负载清单会报 `no matches for kind`,看起来像"清单写错了",其实是**顺序错了**。
- **ArgoCD 的硬刷新**:`selfHeal` 对**它管着的资源**是秒级的,3 分钟只是兜底的全量对账。命令里 `annotate ... refresh=hard` 是为了别等那 3 分钟。

---

## 四、三项"静默失败"验收

这三个检查项**都不是"能不能跑通"的问题,而是"它到底有没有在工作"的问题**。它们共通的形态是:**系统看起来很健康,但链路是断的**。跑:

```bash
./重建.sh verify
```

### (a) 构建的触发原因必须是 `Gitea push ...`

```
#21 触发原因: Gitea push refs/heads/main (db89aafd...) by fei232401
```

> **为什么必须是这一条**:手动打一下 webhook 端点返回 `200 triggered:true`,**不能证明链路通** —— 那绕过的是 **Gitea 自己的策略**(P23 就这么骗过我一次)。
>
> **唯一可信的验证是推一次真代码,然后看"触发原因"。** 看到 `Started by user ...` 就说明是有人手动点的,**你验的不是链路**。

### (b) Trigger Guard 的两个分支都要出现过

```
#16 闸门=命中(构建)      #17 闸门=跳过
```

> **为什么两个都要**:只验"命中"证明不了防循环;**只验"跳过"证明不了正常构建。** 两个分支都出现过,才说明闸门是**在工作**,而不是**把所有东西都放行/都拦掉**。
>
> 背景:CI 跑完会把新镜像写回 GitOps 清单,**那次 push 也会触发流水线**。闸门认出"本次只改了 `sre-lab-gitops/`"就早退 —— 循环**只走一次就停**。

### (c) `sre_lab_build_info{revision}` 必须等于镜像的 7 位短 SHA

```
Pod=ollama-exporter-6ccf4fd9b9-2ldmg  镜像 tag=0d327c2  自报 revision=0d327c2
```

> **为什么不能只看 Pod 上的 tag**:tag 只证明"**调度器让它跑这个 tag**",不证明它真的起来了、更不证明**镜像内容对**。版本号是**构建期**注入的(`--build-arg GIT_SHA`),程序通过 `/metrics` **从容器内部经真实数据面**自报回来。
>
> ⚠️ **采样时务必看清采的是哪个 Pod**:滚动更新期间新旧两代**同时存在**,我实测踩过一次 —— 采到了正在退场的旧 Pod,拿到一个**过期的、但看起来完全正常的值**。

### 实测输出(2026-09-16,对现场集群)

```
== 14 三项静默失败验收 ==
   ✓ registry 有 sre-lab/ollama-exporter
   #21 触发原因: Gitea push refs/heads/main (db89aafd...) by fei232401
   ✓ (a) 由 Gitea push 触发,链路通
   #16 闸门=命中(构建)   #17 / #18 / #20 / #21 闸门=跳过
   ✓ (b) 两个分支都出现过
   Pod=ollama-exporter-6ccf4fd9b9-2ldmg  镜像 tag=0d327c2  自报 revision=0d327c2
   ✓ (c) 运行时自报版本与镜像 tag 一致

   ✓ 三项全过
```

---

## 五、重建对象清单

### A. 在 Git 里,重建会自己回来

| 对象 | 位置 |
|---|---|
| 6 个 Application 的定义 | `sre-lab-gitops/production/bootstrap/*.yaml` |
| ai-platform / loki / nginx-demo / promtail / sealed-secrets 的工作负载 | `sre-lab-gitops/production/apps/**` |
| 告警规则、grafana / prometheus ingress | `sre-lab-gitops/production/monitoring/**`(除 sealed 文件) |
| Jenkins / ArgoCD 的 Helm values | `production/helm-values/jenkins-values.yaml`、`production/argocd/argocd-values.yaml` |
| 构建用 registries.conf | `production/ci/buildah-registries.yaml` |
| 流水线本体 | `ci/Jenkinsfile` |
| exporter 源码 + Dockerfile | `03-ollama-exporter/` |
| **改造前基线的完整命名空间快照** | `sre-lab-local/01_排障记录/00_改造前基线/ns-*.yaml` |

> 最后一行值得单独说:`ai-infra-gateway` / `cyberrouter-operator` / `vllm-3b` / `gpu-exporter` / `nvidia-device-plugin` 这些**不在任何 ArgoCD Application 的管辖范围内**,是当年 `kubectl apply` 上去的。但它们的清单**被 `00_改造前基线/` 里的全量 dump 保住了** —— 这是那次"改造前留档"最大的回报。

### B. 在 Git 里,但对不上现场

| 对象 | 差异 |
|---|---|
| `production/helm-values/monitoring-values.yaml` | 现场比它多 5 个顶层键(含 10Gi PVC、grafana 密码)。**按仓库重建会得到不一样的监控栈。** 见第二节 |

### C. 不在 Git 里,**重建会丢**

| 对象 | 在哪 | 丢了会怎样 |
|---|---|---|
| **k3d 集群本体**(含创建命令) | Docker | 创建命令**任何地方都没有记录**,只能反推(待核实) |
| Docker 网络 `k3d-ai-cluster` | Docker,创建于 2026-07-25 | IP 会变,`ALLOWED_HOST_LIST` / CoreDNS 都要跟着改 |
| **registry 容器 + 它的匿名卷** | Docker | **所有镜像都没了**,必须重建镜像 |
| **Gitea 容器 + `gitea-data` 卷** | Docker | **仓库、webhook 定义、app.ini 全丢** |
| containerd `certs.d/*/hosts.toml` | 3 个节点容器内 | Pod 拉本地镜像失败 |
| 节点标签 `node-role=cpu` / `nvidia.com/gpu=true` | K8s | 所有工作负载 Pending |
| CoreDNS `NodeHosts` | K8s ConfigMap | — |
| 3 个 Helm Release(argocd / jenkins / monitoring) | K8s | 见 B |
| **Jenkins 任务 `sre-lab-ci`** | Jenkins PVC 里的 `config.xml` | 触发源全没了 |
| **Jenkins 凭据 `gitea-webhook-token`** | Jenkins PVC 里的 `credentials.xml` | webhook 端点返回 404 |
| Secret `jenkins/jenkins`(管理员密码) | K8s | 登不进 Jenkins |
| Secret `jenkins/gitea-netrc` | K8s | CI 没法 push 回 GitOps |
| Secret `jenkins/jenkins-git-deploy-key` | K8s | 同上(历史遗留,当前走 netrc) |
| Secret `monitoring/monitoring-grafana` | K8s | Grafana 登录不了 |
| **Sealed Secrets 私钥 `sealed-secrets-keyf62t9`** | K8s | **所有 sealed 文件作废**(当前只有 1 个) |
| **6 个 Application 本身** | 手工 `kubectl apply` | 它们**不受 root-app 管**,`root-app` 现场**根本没 apply** |
| **手工构建后 `docker save/load` 进节点的镜像**:`ai-infra-gateway:v20`(server-0 上还堆着 v12–v19)、`cyberrouter-operator:v3` | 3 个节点的 containerd | **只在节点里,registry 里查不到**(`curl .../v2/ai-infra-gateway/tags/list` 返回 404)—— **集群一换就没了,且没有 Dockerfile 记录**。对照组:`ollama/ollama:latest`、`vllm/vllm-openai:latest` 来自公共仓库,可以重新拉 |
| PV 数据:ollama 模型 20Gi / Jenkins 8Gi / Prometheus 10Gi | local-path | 模型要重下 |
| Gitea 的存在性依赖 | Docker | **`RestartPolicy=no`** —— 宿主重启后 Gitea **不会自己回来** |

> **这张表本身就是结论**:上面这些东西**一个都不会报错**。它们不在,系统只是**安静地不工作** —— 这正是 `06_踩坑记录.md` P18 的形状,在整条链路上重演了很多次。

### 📌 2026-09-17 更新:表 C 里有 5 行已经不再是「全丢」

> 2026-09-16 宿主重启后,控制面整体死亡:ArgoCD 6 条 Application 全 `Unknown`、Jenkins init `CrashLoopBackOff`、Gitea 不见。事后复核确认**根因不是组件坏了,而是这张表** —— 表 C 里有 3 行恰好是控制面的命门。
>
> 完整诊断见 `06_踩坑记录.md` P24–P26,决策与代价见 `99_决策日志.md` D18–D21,**重建顺序见 `CI_重建清单.md`**。

| 表 C 里的行 | 现状 |
|---|---|
| **Gitea 容器 + `gitea-data` 卷** | 容器定义已入 Git(`gitea_up.sh`,含 `--ip` 固定与 `RestartPolicy=unless-stopped`)。**卷内容仍不在 Git**(数据面),但 `GitHub fei232401/sre-lab` 是同一份内容的副本,可作恢复源 |
| **Gitea 的存在性依赖 `RestartPolicy=no`** | 已改 `unless-stopped`;`gitea_up.sh` 每次跑都会校正回来 |
| CoreDNS `NodeHosts` | 仍不在 Git。但关键名字(集群内 `gitea`)已改由**集群内的 Service + Endpoints** 提供(`manifests/gitea-endpoints.yaml`),不再依赖它 |
| **Jenkins 任务 `sre-lab-ci`** | 定义已导出到 `ci/job-config.xml`(触发令牌已脱敏) |
| **Jenkins 凭据 `gitea-webhook-token`** | **值仍在 Git 外**(刻意)。需在 Jenkins UI 手工录入,ID 必须是 `gitea-webhook-token` |

> ⚠️ **顺带纠正本表的一处错误**:原先被当成"历史残留"的那条 `github.com` NodeHosts 条目,**其实在承担职责**(集群内要到 GitHub 靠它,插件与依赖下载要用)。判断标准很朴素:**把它拿走,看谁断。** 详见 P25。

> **表 C 的正确读法没变**:列在上面的东西**一个都不会报错**。所以"哪些已经还了、哪些还欠着"这件事**必须定期重看,不能靠记忆**。
>
> 还欠着的里面最危险的一条:**Sealed Secrets 私钥**。它一丢,`alertmanager-smtp` 永久解不开 —— 而**"告警没人收"这件事本身不会报警**。

### 一处需要你拍板的设计岔口

`production/bootstrap/root-app.yaml` **在 Git 里存在,但现场从未 apply**。也就是说设计意图是"App-of-Apps 自管",实际落地是"6 个 Application 手工 apply、自己不管自己"。

- **保持现状** = 照脚本第 13 阶段做(只 apply 那 6 个)
- **改用 root-app 自管** = 额外 apply `root-app.yaml`。⚠️ **它带 `prune: true`** —— 会**删掉 bootstrap 目录里没有的资源**。启用前务必先确认目录内容与现场一致

---

## 六、重建最可能失败的三个点

按"会不会发生 × 出了事好不好查"排序:

### 1. 集群创建命令是反推的(最不确定)

`k3d cluster create` 的原始命令**仓库里没有、本机也没有**(`~/.config/k3d/` 下只有 kubeconfig)。脚本给的是从容器配置反推的版本,**含推测成分**。

**为什么难查**:建出来的集群**看起来是好的** —— 节点 Ready、kubectl 能连。问题会在很后面才暴露:GPU 没挂上(少了 `--gpus all`)→ `vllm` 起不来;或者 agent 数量不对 → 工作负载挤在一个节点上。

**对策**:建完立刻比对 `docker inspect k3d-ai-cluster-agent-0 --format '{{json .HostConfig.DeviceRequests}}'`,必须出现 `"Capabilities":[["gpu"]]`。

### 2. Gitea 的 webhook 白名单 / 投递路径

三个前置条件(插件、凭据、`ALLOWED_HOST_LIST`)少任意一个,**链路都是静默断的**,而且**只有 Gitea 容器的日志里会说话**。

**为什么难查**:Gitea UI 上 webhook 显示"已配置",Jenkins 上什么都没有 —— 两边看起来都没问题。**必须 `docker logs gitea`。**

**对策**:重建后**第一件事不是看 Jenkins,是看 Gitea 日志**;然后按第四节 (a) 推一次真代码验触发原因。

### 3. 监控栈对不上仓库 values

B 类问题。按仓库文件装 monitoring → 装出来的栈**少 5 个顶层键**(包括 10Gi 的 Prometheus PVC)。它**不会报错**,只会:Prometheus 没有持久化、Grafana 少了一层配置。

**为什么难查**:没有报错、没有 Pending,Google 也没人问过 —— 因为这不是"错",是"**你没说要什么,所以就没给**"。

**对策**:拆之前先跑 `./重建.sh snapshot`;装完之后 `helm get values monitoring -n monitoring` 与导出的文件比对。

---

## 七、⚠️ 读 `~/projects/sre-lab` 的 `git status` 之前,先读这一节

WSL 里的 `~/projects/sre-lab` 是**编辑源**,不是发布源(D22)。它的 git 状态**长期是"脏"的**,而且**看起来比实际更糟**:

```
$ git rev-parse --short HEAD
dea2f70                    ← 远端可能已经领先好几个提交
$ git status --porcelain
 8 个 M + 6 项 ?? + 2 个只有 mode 变化的 M
$ git status -sb
## main...origin/main      ← 注意:没有 behind 标记
```

**两个必须知道的读取陷阱:**

1. **它不 fetch** —— 所以 `status -sb` **永远不显示 behind**。它不知道远端走到哪了,**不能据此判断"本地是不是最新"**。
2. **那堆 M / ?? 不等于"有未发布的改动"** —— 落盘通道是「改 UNC 上的文件 → 复制进 Windows 侧克隆 → commit → push」,**工作副本的 git 头不参与这条通道**。所以这里的"脏"是**设计的一部分**,不是待办。

**怎么判断"到底有没有东西没发布"?** 别看 `git status`,看**远端**:

```bash
git ls-remote http://127.0.0.1:3001/fei232401/sre-lab.git refs/heads/main
```

**为什么不干脆 `git pull` 对齐?** 因为**收益为零、代价为正**:这里没有任何独有内容,而 `pull` 会让 15 个已修改/未跟踪文件与入站改动**正面对撞**,冲突还要在 9p 文件系统上解。完整推理与代价见 D22。

---

## 变更记录

- 2026-09-16:建立。M5 收口产出:`重建.sh`(分阶段重建 + 三项静默失败验收)、本 README(验证状态 / 顺序理由 / 重建对象清单 / 三个失败点)
- 2026-09-17:表 C 复核更新。新增「表 C 里有 5 行已经不再是『全丢』」;纠正 `github.com` NodeHosts 条目被误判为历史残留;**新增 `gitea_up.sh`(含集群侧解析对象)与 `CI_重建清单.md`**。依据 P24–P26 / D18–D21
- 2026-09-17:新增第七节「读 `git status` 之前先读这一节」—— 工作副本是编辑源、长期显脏、且不 fetch 所以不显示 behind。依据 D22 / P28–P31
