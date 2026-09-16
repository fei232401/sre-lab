# Jenkins 运行手册

- **建立**:2026-09-16
- **Jenkins 版本 / chart 版本**:待核实
- **安装方式**:官方 Helm chart(`jenkinsci/helm-charts`)
- **部署位置**:`jenkins` 命名空间,构建 Pod 落在 `node-role: cpu` 的节点上
- **流水线任务名**:`sre-lab-ci`
- **Jenkinsfile 位置**:仓库内 `ci/Jenkinsfile`

---

## 一、多集群纪律(同 ArgoCD 手册)

**本机有多个 k3d 集群,`kubectl` / `helm` 都隐式使用 kubeconfig 的当前 context。**

不显式指定 context 的后果不是报错,而是**安静地作用在另一个集群上**。

```bash
kubectl config get-contexts               # 先看清楚有哪几个
kubectl --context k3d-ai-cluster ...      # 本项目所有命令都带这个
```

> **本项目纪律:所有 `kubectl` / `helm` 命令显式带 context,无一例外。**
>
> 详情见 `06_踩坑记录.md` 的 P1。

---

## 二、访问入口

**首选 NodePort(稳定)**:

```
http://172.18.0.5:30080
```

`172.18.0.5` 是 **k3d server 节点容器的 IP**,`30080` 是 `jenkins-values.yaml` 里配的 `nodePort`。

> **为什么不用 port-forward**:`kubectl port-forward` 是**本机进程**,进程一断链接就死。实测在长时间脚本里会莫名其妙地"命令还在跑但请求全部失败",而且失败形态**不是连接拒绝,是返回非预期内容**(比如 HTML 而不是 JSON)——很容易被误读成"接口变了"。集群内(Gitea 容器)和宿主机都能走 NodePort,就用它。
>
> 顺带一个坑:清理 port-forward 时写 `pkill -f "port-forward svc/jenkins"` **会匹配到自己这条命令**,把当前 shell 一起杀掉(退出码 144)。要杀就按 PID 杀。

**备选(仅本机浏览器临时看 UI)**:

```bash
kubectl --context k3d-ai-cluster port-forward -n jenkins svc/jenkins 18081:8080
```

> **注意端口映射的宿主机侧是 `18081`,不是 `8080`。** 本项目 ArgoCD 的 UI port-forward 用的是 `8080`(见 `02_ArgoCD_运行手册.md`),两个 UI 用不同端口,不要敲错。

### 管理员账号密码

凭据存在 Secret `jenkins` 里,两个键:

```bash
kubectl --context k3d-ai-cluster -n jenkins get secret jenkins \
  -o jsonpath='{.data.jenkins-admin-user}' | base64 -d; echo
kubectl --context k3d-ai-cluster -n jenkins get secret jenkins \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo
```

---

## 三、用 REST API 建任务(两个各不相同的坑)

**这两个坑的形状完全不同**,一个错在**认证**(403),一个错在**编码**(400)。不要把它们混为一谈。

### ⚠️ 坑 1:CSRF crumb **必须和会话绑定** —— 不带 cookie jar 就是 403

Jenkins 开了 CSRF 保护后,`crumbIssuer` 发的 crumb **绑定在会话上**。也就是说:

> **请求 crumb 的那一次调用,和提交 crumb 的那一次调用,必须是同一个会话。**

用 `curl` 的话,就是**必须同时带 `-c`(写 cookie)和 `-b`(读 cookie)**,让两次请求共享同一个 cookie jar。**不带 cookie 的话,无论 crumb 值对不对,一律 403。**

```bash
JENKINS_URL="http://localhost:18081"
COOKIE_JAR=/tmp/jenkins-cookies

CRUMB=$(curl -s -c "$COOKIE_JAR" \
  -u "$JENKINS_USER:$JENKINS_PASS" \
  "$JENKINS_URL/crumbIssuer/api/json" \
  | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)

curl -s -b "$COOKIE_JAR" \
  -u "$JENKINS_USER:$JENKINS_PASS" \
  -H "Jenkins-Crumb: $CRUMB" \
  -X POST \
  "$JENKINS_URL/createItem?name=sre-lab-ci" \
  --data-urlencode "json@ci/job-config.json"
```

**排查口诀:403 先看 cookie,再看 crumb 值。**

### ⚠️ 坑 2:凭据创建的端点要 **form 编码的 `json=` 参数**,发裸 JSON body 会 400

创建凭据(`createCredentials`)这个端点,**不接受裸 JSON body**。

发裸 JSON 的话,返回的是:

```
400  Nothing is submitted
```

**它的接口形态是 form 表单**,数据要放在名为 `json` 的 **form 字段**里。用 `--data-urlencode "json@<file>"` 而不是 `-H "Content-Type: application/json" --data @<file>`:

```bash
curl -s -b "$COOKIE_JAR" \
  -u "$JENKINS_USER:$JENKINS_PASS" \
  -H "Jenkins-Crumb: $CRUMB" \
  -X POST \
  "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
  --data-urlencode "json@ci/credential.json"
```

> `400 Nothing is submitted` 这个报错很有迷惑性 —— 它容易被读成"请求体是空的",而实际请求体**是满的**,只是**放错了位置**(body 里,而不是 `json` 这个 form 字段里)。**报错信息描述的是服务端看到了什么,不是你发了什么。**

### ⚠️ 坑 3:远程触发令牌(`/build?token=X`)**被 CSRF 保护挡死**

Jenkins 2.568.3 上,即便给任务配好了 `BuildAuthorizationToken`,这几种写法**全部 403**:

```
GET  /job/sre-lab-ci/build?token=<TOKEN>
POST /job/sre-lab-ci/build?token=<TOKEN>
POST /job/sre-lab-ci/build?token=<TOKEN>  (+ 管理员账号密码)
```

报错统一是 `No valid crumb was included` —— **令牌是对的,是被 CSRF 拦在更外层**。

> **根因**:本环境 JCasC 里 `allowAnonymousRead: false`,令牌这条路要求请求"够得着"任务,而 CSRF 又要求每个请求带会话绑定的 crumb。**凭证令牌和 CSRF 是两层独立机制**,配好了前者不代表能过后者。

**绕过方式就是 webhook 插件**:`generic-webhook-trigger` 提供自己的端点 `/generic-webhook-trigger/invoke?token=...`,它**不受这条 CSRF 约束**,并且支持把令牌放进 Jenkins **凭据**里(`tokenCredentialId`),**令牌值因此不需要写进任何仓库文件**。

> 配一个 `BuildAuthorizationToken` 还费了点劲:它**不是** `JobProperty`,`addProperty()` 用不了;反射时若把值设成 `String` 会抛 `IllegalArgumentException: Can not set ... BuildAuthorizationToken field ... to java.lang.String`。最后是**反射直接 set 成 `new BuildAuthorizationToken(TOKEN)`** 才成功。**这段折腾的结论是:此路不通,换插件**——记录下来免得下次再走一遍。

### 附:这条路没走通的部分

> 用 REST API 创建 `GitSSHUserPrivateKey` 类型凭据时,**返回 500**,没能成功。时间原因改用"把私钥以 K8s Secret 挂进构建 Pod"的方案。
>
> 详见 `99_决策日志.md` 的 D17(含该方案的诚实边界)。

---

## 四、⚠️ 重启 Jenkins 的代价:分钟级,而且会**重新下载全部插件**

**这是本手册里最重要的一条纪律。**

重启 Jenkins 时,它的 **init 容器**会**重新下载全部插件**。插件源是 `mirror.ossplanet.net`,**该源不稳定、会重试**,整个重启因此是**分钟级**的。

```
重启 = init 容器重下全部插件(源不稳定 + 重试)= 分钟级不可用
```

**由此推出一条排期纪律:**

> **任何"改 JVM 参数"这类需要重启才生效的事,要趁早做 —— 不要等到出问题才重启。**

出问题的时候重启,你付出的代价是"分钟级不可用"叠加在"系统已经不正常"之上 —— 而这两件事在时间上会**混在一起**,让归因变难。

### ✅ 已还:JVM DNS 缓存参数(2026-09-16)

```yaml
controller:
  javaOpts: "-Dsun.net.inetaddr.ttl=30 -Dsun.net.inetaddr.negative.ttl=10"
```

已随 `jenkins-values.yaml` 一起 `helm upgrade` 落地(rev 3,状态 `deployed`)。

**原因与完整故事见 `06_踩坑记录.md` 的 P15** —— Jenkins 是 JVM,默认缓存 DNS 解析结果,不改这两个参数的话,DNS 变更后它**必须靠重启才能感知**。

> **这笔债的偿还过程本身又是一课**:`helm upgrade --wait` 会**超时失败**,因为 init 容器在重下插件(`Ready: 0/1`)。**但它其实没坏**——等下载完,把同一条 upgrade 再跑一遍就 `deployed` 了。
>
> **教训:`--wait` 超时 ≠ 变更失败。** 先看 Pod 到底卡在哪一步,再决定是回滚还是重跑。

---

## 五、流水线任务

| 项 | 值 |
|---|---|
| 任务名 | `sre-lab-ci` |
| Jenkinsfile | 仓库内 `ci/Jenkinsfile` |
| 触发方式 | **Gitea webhook 推送**(2026-09-16 起;SCM 轮询已从任务配置中**删除**) |
| 构建 Pod 落点 | `node-role: cpu` 的节点 |

### 触发方式:webhook(已取代 SCM 轮询)

**SCM 轮询在这套架构下根本不可能工作**,已彻底移除。完整诊断见 `06_踩坑记录.md` 的 P18,一句话版本:

> 轮询要算"这次推送改了哪些路径",这需要**上一次构建的工作区**。而我们的构建 agent 是**即用即销的 k8s Pod**——轮询执行的那一刻那个节点**必然已经不存在**。于是它降级成"无变更"直接返回,并且**不报错、不告警**。
>
> 决定性证据:轮询日志里 `Done. Took 0 ms` / `No changes`。**0 毫秒干不完一次网络往返,说明它压根没去问。**

现在由 Gitea 的 push webhook 经 `generic-webhook-trigger` 插件触发。配置、令牌管理、以及**三个"少一个就静默不工作"的前置条件**见 `04_发布与回滚手册.md` 第五节。

> ⚠️ **注意一处容易看漏的地方**:`triggers` 指令写在 Jenkinsfile 里,但它的注册要**先跑一次构建**(Jenkins 要解析过 Jenkinsfile 才知道有这回事)。所以**第一次接入时必须先手动跑一次**,之后才吃 webhook。手动那次的触发原因是 `Started by user ...`——**看到这个就说明你验的不是链路。**

> 另外,任务配置里的**老 `SCMTrigger` 不会因为 Jenkinsfile 没声明它而自动消失**(实测:它和新的 `GenericTrigger` 并存,导致每次 push 构建两次)。要**显式从 `config.xml` 里摘掉**。删触发器用的 POST 同样要注意 P21 的 `charset=UTF-8`。

> **顺带纠正一个我(手册)自己写错的地方**:`H/2 * * * *` 在 5 段式 cron 里是**每 2 分钟**,不是每 2 小时。当时看着"2"就顺手写成了小时,没验证。**这类"看起来对所以没查"的陈述,是文档里最危险的一类错误。**

> 这与 ArgoCD 的轮询仍是**两条独立的**发现路径:Jenkins 管"**代码有没有变**"(变了就构建),ArgoCD 管"**GitOps 仓库有没有变**"(变了就同步)。两者各管各的,不要互相假设。

### 构建 Pod 落在 CPU 节点

构建 Pod 不请求 GPU,因此**走 `node-role: cpu` 的 nodeSelector**(沿用集群已有约定,见 D7)。

> **这一条是资源纪律,不是优化。** `agent-0` 是唯一带 GPU 的节点、长期高负载;CI 构建**没有任何理由**占用它。按"资源特征"给工作负载选节点,是这份清单里最直接体现 D7 决定的一处。

---

## 六、本地镜像仓库(k3d registry)

M3 用的本地私有仓库(选型理由见 D16)。

```bash
curl http://localhost:5111/v2/_catalog
curl http://localhost:5111/v2/<name>/tags/list
```

- `_catalog` —— 看**有哪些仓库**
- `tags/list` —— 看某个仓库**有哪些 tag**

> **集群侧访问它用的地址不是 `localhost:5111`,而是 `k3d-sre-registry:5000`。** 两个地址差一个层级:宿主机走发布的端口,集群内走 Docker 网络里的容器名 + 容器内端口。
>
> containerd 默认走 HTTPS,给这个 HTTP 仓库配 `certs.d` 的细节、以及"为什么改它不用重启 k3s",见 `06_踩坑记录.md` 的 P16。

---

## 七、常用命令

```bash
# 看 Jenkins 的 Pod
kubectl --context k3d-ai-cluster -n jenkins get pods -o wide

# 看某个构建 Pod 落在哪个节点
kubectl --context k3d-ai-cluster -n jenkins get pods -o wide --show-labels

# 看 jenkins 的 values 是否生效(例如 javaOpts)
helm --kube-context k3d-ai-cluster get values jenkins -n jenkins

# 触发一个任务(需要 cookie jar + crumb,见第三节)
curl -s -b "$COOKIE_JAR" \
  -u "$JENKINS_USER:$JENKINS_PASS" \
  -H "Jenkins-Crumb: $CRUMB" \
  -X POST "$JENKINS_URL/job/sre-lab-ci/build"
```

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-16 | 建立。收录访问入口、两个 REST API 坑(crumb 会话绑定 / `json=` form 编码)、重启代价纪律、流水线任务信息、本地镜像仓库命令 |
