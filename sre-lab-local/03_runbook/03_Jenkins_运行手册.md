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

### 已经欠下的一笔:JVM DNS 缓存参数

`jenkins-values.yaml` 的 `controller.javaOpts` 需要加:

```yaml
controller:
  javaOpts: >
    -Dsun.net.inetaddr.ttl=30
    -Dsun.net.inetaddr.negative.ttl=10
```

**原因与完整故事见 `06_踩坑记录.md` 的 P15** —— Jenkins 是 JVM,默认缓存 DNS 解析结果,不改这两个参数的话,DNS 变更后它**必须靠重启才能感知**。

> **这两个参数正是"需要重启才生效的事"的典型例子。** 按上面的纪律,应该尽早应用,而不是等下一次 DNS 问题发生时才后悔。

---

## 五、流水线任务

| 项 | 值 |
|---|---|
| 任务名 | `sre-lab-ci` |
| Jenkinsfile | 仓库内 `ci/Jenkinsfile` |
| SCM polling | `H/2 * * * *` |
| 构建 Pod 落点 | `node-role: cpu` 的节点 |

### SCM polling

`H/2 * * * *` —— **每 2 小时轮询一次仓库**。

> 这与 ArgoCD 的轮询是**两条独立的**发现路径:Jenkins 轮询的是"**代码有没有变**"(变了就触发构建),ArgoCD 轮询的是"**GitOps 仓库有没有变**"(变了就同步到集群)。两套轮询各管各的,不要互相假设。

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
