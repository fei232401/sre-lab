# Sealed Secrets 运行手册

- **建立**:2026-09-16
- **上游版本**:v0.40.0(2026-09-10 发布)
- **部署位置**:`kube-system` / `sealed-secrets-controller`
- **清单来源**:官方 `controller.yaml`(release asset),非手搓

---

## 一、为什么最后落在 kube-system

仓库原先那份 `production/apps/sealed-secrets/controller.yaml` 是手搓的,实测**四重损坏**:

| 问题 | 实测证据 |
|---|---|
| 镜像源已失效 | `quay.io/bitnami/sealed-secrets-controller:v0.26.3` → **HTTP 401**。Bitnami 在 2025 年调整了公开镜像目录,这个仓库已不在公开目录中 |
| 版本落后 | 写的是 0.26.3,上游最新 v0.40.0 |
| **缺 CRD** | 原文 `grep -c CustomResourceDefinition` = **0**。照现状 apply,创建第一个 SealedSecret 时才会失败 |
| 自造 RBAC | ClusterRole 里 `secrets` 有 `get/list/watch/update/create/patch` 但**没有 `delete`**,也没有 `namespaces get` |

**换用官方 v0.40.0 之后**,顺带拿到三个好处:

1. **CRD 齐全**(官方清单第 165 行起)
2. **安全上下文硬化**:`runAsNonRoot: true` / `runAsUser: 1001` / `readOnlyRootFilesystem: true` / `capabilities.drop: [ALL]` / seccomp `RuntimeDefault` —— 手搓版这些一个都没有
3. **`kubeseal` 零参数可用**(见下节)

### 关于 `--controller-name` 的坑(重要)

`kubeseal` 取公钥走的是 **Service 代理**,不是直接连 Deployment。追到源码 `pkg/kubeseal/kubeseal.go`:

```go
cert, err := c.Services(namespace).ProxyGet("http", name, portName, "/v1/cert.pem", nil).Stream(ctx)
```

即 `<ns>/services/<name>:http/proxy/v1/cert.pem`。所以 **`--controller-name` 匹配的是 Service 名**:

```
--controller-name      string   (default "sealed-secrets-controller")
--controller-namespace string   (default "kube-system")
```

- 官方清单:Service 名就叫 `sealed-secrets-controller`、在 `kube-system` → **默认值直接可用,不用加任何 flag**
- Helm chart 默认装出来 Service 叫 `sealed-secrets` → 必须显式 `--controller-name sealed-secrets`,或者装的时候 `--set-string fullnameOverride=sealed-secrets-controller`

**本仓库采用官方路径,所以下面所有命令都不带 controller flag。**

### 我们对官方清单做的三处改动

官方清单有两个不适合本环境的默认值,已就地修正:

| 改动 | 原因 |
|---|---|
| 补 `resources`(requests 20m/32Mi,limits 200m/256Mi) | 官方**完全不设 resources**,默认 BestEffort QoS。在 agent-0 已经 82% 的环境里,BestEffort 是 kubelet 内存压力下第一个被驱逐的对象 |
| 补 `nodeSelector: {node-role: cpu}` | 把控制器钉到 agent-1,与 ArgoCD 同一策略 |
| CRD 加 `argocd.argoproj.io/sync-options: Prune=false` | 该 Application 开了 `prune: true`。CRD 是 cluster-scoped 删除边界,一旦清单被移出 Git,会连带删掉**所有已存在的 SealedSecret** |

> 最后一条是 M1「雷 2」的同一类问题(**Namespace 被 `prune: true` 的 App 管**)在 CRD 上的复发。

---

## 二、封存一个 Secret

### 标准流程

```bash
kubectl --context k3d-ai-cluster -n monitoring create secret generic wechat-webhook \
  --from-literal=WECOM_WEBHOOK_URL='https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=REAL_KEY' \
  --dry-run=client -o yaml \
| kubeseal -o yaml > sealed-wechat-webhook.yaml
```

产物 `sealed-wechat-webhook.yaml` 可以直接 commit —— 用**非对称加密**,只有集群里控制器的私钥能解,公钥谁都能拿来加密。

`.gitignore` 已预置 `secrets/`、`*-plain.yaml`、`*.key`、`*.pem`,明文不会误提交。

### 离线封存(CI 里用)

先取证书,再离线封存。**证书是公钥,不敏感,可以进仓库**:

```bash
kubeseal --fetch-cert > mycert.pem
kubeseal --cert mycert.pem -o yaml < secret-plain.yaml > sealed-secret.yaml
```

---

## 三、scope 语义(决定改名/换命名空间还能不能解)

默认 `strict`,三种模式的差别是**加密时把什么绑进密文**:

| scope | 绑定 | 改名 | 换命名空间 |
|---|---|---|---|
| **`strict`(默认)** | name + namespace **都绑** | ❌ 解密失败 | ❌ 解密失败 |
| `namespace-wide` | 只绑 namespace | ✅ | ❌ |
| `cluster-wide` | 都不绑 | ✅ | ✅ |

机制原文:「We don't technically use an independent private key for each namespace, but instead we *include* the namespace name during the encryption process」—— 是**把名字混进加密过程**,不是每命名空间一把钥匙。

**例外**:`spec.encryptedData` 里的 **item key 可以随便改名**(如 `WEBHOOK_URL` → `WECOM_WEBHOOK_URL`),不影响解密。原文:「secret *items* can be renamed at will without losing the ability to decrypt」。

**本仓库一律用 `strict`** —— name 和 namespace 都是确定的,放宽只会扩大攻击面。

---

## 四、⚠️ 私钥备份(集群重建 = 全部封存文件报废)

### 事实

- 私钥以 Secret 形式**只存在于集群内**,打 `sealedsecrets.bitnami.com/sealed-secrets-key` 标签
- 官方 FAQ 原文:**「No, the private keys are only stored in the Secret managed by the controller... There are no backdoors - without that private key used to encrypt a given SealedSecrets, you can't decrypt it.」**
- 封存密钥**每 30 天自动续期**,新密钥**追加**到 active 集合,**旧密钥不删** → 老文件仍能解

### 后果

**k3d 集群重建是本项目的常态操作。** 集群一重建,私钥就没了 → 仓库里所有 SealedSecret 全部变成无法解密的废数据,必须**重新封存一遍**。

### 备份命令

```bash
kubectl --context k3d-ai-cluster -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > main.key
```

**`main.key` 是明文私钥,绝不能进 Git。** 按 M0 的教训(明文 token 挂在公开仓库上 43 天),这份文件必须存到**仓库之外**的地方。

### 恢复

集群重建后,把 `main.key` apply 回去,再重启控制器:

```bash
kubectl --context k3d-ai-cluster apply -f main.key
kubectl --context k3d-ai-cluster -n kube-system rollout restart deploy/sealed-secrets-controller
```

离线解密(不需要集群):

```bash
kubeseal --recovery-unseal --recovery-private-key main.key < sealed-secret.yaml > secret-plain.yaml
```

---

## 五、它解决什么、不解决什么

### ✅ 解决:密钥不进 Git

明文 Secret 在本地生成 → 加密 → 只提交密文。公开仓库里躺着密文是**安全**的。

### ❌ 不解决:已经泄露的密钥

**封存是"让未来的密钥不再泄露",不是"追回已经泄露的"。**

PushPlus token 的明文已经在公开仓库的 HEAD 和 3 个历史 commit 里躺了 43 天。**必须先去后台吊销/重置** —— 这一步和 sealed-secrets 完全独立、不可省略。

### ❌ 不解决:认证

README 原文:**「By design, this scheme *does not authenticate the user*. In other words, *anyone* can create a `SealedSecret` containing any `Secret` they like (provided the namespace/name matches).」**

即:**谁能改 Git,谁就能改集群里的密钥。** 这是 Git 仓库权限和 ArgoCD RBAC 的职责,不是封存要解决的问题。

---

## 六、常用排障命令

```bash
kubectl --context k3d-ai-cluster -n kube-system logs deploy/sealed-secrets-controller --tail=50
kubectl --context k3d-ai-cluster get sealedsecrets -A
kubectl --context k3d-ai-cluster get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key
```

控制器日志里出现 `Error unsealing` 时,绝大多数情况是三选一:
1. scope 不匹配(改过 name / namespace)
2. 私钥不在集群里(集群重建过)
3. 密文被手工编辑过

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-16 | 建立。手搓清单 → 官方 v0.40.0;记录 scope 语义与私钥备份要求 |
