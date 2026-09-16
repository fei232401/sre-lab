# CI 控制面重建清单

> 建立：2026-09-17。这份清单回答一个问题：**把集群和宿主都清空之后，CI/CD 链路能不能只靠 Git 重建？**
>
> 背景：2026-09-16 宿主重启后，CI/CD 控制面整体死亡（Gitea 容器没回来、Jenkins init 崩溃、ArgoCD 6 条 Application 全部 `Unknown`）。事后复核发现根因不是某个组件坏了，而是**控制面的多个关键定义根本不在 Git 里**，重启即静默失忆。

---

## 一、控制面由哪些东西构成

| # | 组件 | 在哪儿 | 定义在 Git 的哪里 |
|---|------|--------|-------------------|
| 1 | Gitea 容器 | 宿主 docker | `08_重建/gitea_up.sh`（幂等；容器不存在时打印完整 `docker run`） |
| 2 | Gitea 仓库数据 | docker 卷 `gitea-data` | **不在 Git**（数据面）。但 `GitHub fei232401/sre-lab` 是同一份内容的副本，可作恢复源 |
| 3 | `gitea` 在集群内的名字解析 | k8s Service + Endpoints（argocd / jenkins 两个命名空间各一份） | `08_重建/manifests/gitea-endpoints.yaml`，由 `gitea_up.sh` 第 4 步 apply |
| 4 | Jenkins 任务 `sre-lab-ci` | k8s `jenkins` 命名空间 | `ci/job-config.xml`（活体导出）、流水线本体 `ci/Jenkinsfile` |
| 5 | Jenkins 凭据 | Jenkins 内部 | 只有 1 个：`gitea-webhook-token`（Secret text）。**值不在 Git**，需重新录入 |
| 6 | Gitea 拉取/推送凭据 | k8s Secret `gitea-netrc` | **值不在 Git**。Jenkinsfile 以卷挂载方式使用（`/home/jenkins/gitea-cred/netrc`） |
| 7 | Jenkins 管理员口令 | k8s Secret `jenkins` | 由 Helm chart 生成，**不在 Git** |
| 8 | buildah 构建缓存 | k8s PVC `jenkins/buildah-storage` | `08_重建/manifests/buildah-storage-pvc.yaml` |
| 9 | buildah 镜像源配置 | ConfigMap `jenkins/buildah-registries` | `sre-lab-gitops/production/ci/buildah-registries.yaml`（ArgoCD 未纳管，手工 apply） |
| 10 | 告警投递脚本 | 仓库内 | `ci/notify_alertmanager.py` |
| 11 | SMTP 口令 | SealedSecret `monitoring/alertmanager-smtp` | 密文在 `sre-lab-gitops/production/monitoring/sealed-alertmanager-smtp.yaml`；**解封私钥不在 Git** |

---

## 二、重建顺序

```bash
BASE=/home/fei/projects/sre-lab
```

**1. 起 Gitea**（幂等，可重复跑）

```bash
bash "$BASE/sre-lab-local/08_重建/gitea_up.sh"
```

它做四件事：起容器 / 校正 `RestartPolicy` / 保证 `app.ini` 的 webhook 白名单 / apply 集群侧解析对象并核对 Endpoints 是否与容器实际 IP 一致。

> `gitea_up.sh` 第 4 步依赖 `kubectl`。若集群还没起，这一步会跳过并告警 —— **此时集群内 `gitea` 会退回宿主机 docker DNS**（能用，但那是跨层副作用，容器一停就 NXDOMAIN）。

**2. 建 Jenkins 任务**

```bash
JENKINS_URL=http://172.18.0.5:30080
COOKIE_JAR=/tmp/jenkins-cookies

CRUMB=$(curl -s -c "$COOKIE_JAR" -u "$JENKINS_USER:$JENKINS_PASS" \
  "$JENKINS_URL/crumbIssuer/api/json" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)

curl -s -b "$COOKIE_JAR" -u "$JENKINS_USER:$JENKINS_PASS" \
  -H "Jenkins-Crumb: $CRUMB" -X POST \
  "$JENKINS_URL/createItem?name=sre-lab-ci" \
  -H "Content-Type: application/xml" \
  --data-binary @"$BASE/ci/job-config.xml"
```

> crumb 必须与会话绑定（同一 cookie jar）。见 `03_runbook/03_Jenkins_运行手册.md` 第三节坑 1。

**3. 补回那 1 个凭据**

在 Jenkins UI 里新建 `Secret text`，ID 必须是 `gitea-webhook-token`，值取自 Gitea 侧 webhook 的 token。

> 为什么不用 REST 建：见 `03_runbook/03_Jenkins_运行手册.md` 第三节坑 2（端点要 form 编码的 `json=` 参数）。凭据值本身不该进 Git，手工录入是刻意的。

**4. 建 buildah 缓存与镜像源配置**

```bash
kubectl --context k3d-ai-cluster apply -f "$BASE/sre-lab-local/08_重建/manifests/buildah-storage-pvc.yaml"
kubectl --context k3d-ai-cluster apply -f "$BASE/sre-lab-gitops/production/ci/buildah-registries.yaml"
```

**5. 接回触发**

- Gitea 仓库 `fei232401/sre-lab` → Settings → Web Hooks → 指向
  `http://jenkins:8080/generic-webhook-trigger/invoke?token=<TOKEN>`
- 前置条件三条（少一条就静默不工作）见 `03_runbook/04_发布与回滚手册.md` 第五节。
- **`triggers` 指令写在 Jenkinsfile 里，但注册要先跑一次构建** —— 第一次务必手动跑一次。

---

## 三、仍然不在 Git 的（诚实边界）

| 项 | 为什么 | 丢了会怎样 |
|----|--------|-----------|
| `gitea-webhook-token` 值 | 凭据，刻意不入库 | webhook 401，手工重录（Gitea 侧能看到 token） |
| `gitea-netrc` 值 | 凭据，刻意不入库 | Jenkins 无法拉/推 Gitea，从 Gitea UI 重新签发即可 |
| `jenkins` Secret 口令 | chart 生成 | `helm upgrade` 或从 chart 重新生成 |
| sealed-secrets 解封私钥 | 从来只在你本机 | `alertmanager-smtp` 永久解不开，失败告警发不出去 |
| `gitea-data` 卷内容 | 数据面 | 从 `GitHub fei232401/sre-lab` 克隆回来 |
| k3d 集群本身 | 用 `重建.sh` 重建 | 走 `重建.sh` |

**结论**：控制面的**结构**已经全部可从 Git 重建；**密钥的值**刻意不入库（这是对的），但因此有一处必须人工确认——**sealed-secrets 私钥**。它一丢，失败告警链路就断，而且断得无声（告警没人收，没人知道）。

---

## 四、本次为修「静默失忆」而做的具体改动

| 洞 | 改了什么 | 文件 |
|----|----------|------|
| #4 配置未版本化 | Gitea 容器定义 + `gitea` 解析对象 + Jenkins 任务定义 + buildah PVC 全部入 Git | `08_重建/gitea_up.sh`、`08_重建/manifests/*.yaml`、`ci/job-config.xml` |
| #2 失败无通知 | `post{failure}` 从 `echo` 改为投递 Alertmanager 告警；`post{success}` 投递同标签的已恢复告警 | `ci/Jenkinsfile`、`ci/notify_alertmanager.py` |
| #10 webhook 原文进日志 | `printPostContent` / `printContributedVariables` 由 `true` 改 `false` | `ci/Jenkinsfile` |
| #1 流水线无测试 | `Lint` stage（只有 `py_compile`）换成 `Test` stage（真跑 14 个单元测试） | `ci/Jenkinsfile`、`03-ollama-exporter/test_exporter.py` |
| #9 构建无缓存 | buildah 的 `/var/lib/containers` 从 `emptyDir` 换成 PVC | `ci/Jenkinsfile`、`08_重建/manifests/buildah-storage-pvc.yaml` |

> `#9` 还有第二处同类问题**未修**：Jenkins 自身的 `plugin-dir` / `jenkins-cache` 仍是 `emptyDir`，导致每次重启都要从 `mirror.ossplanet.net` 重下全部插件（分钟级）。它需要改 Helm values 并重启 Jenkins，不适合和本次一起做——**重启代价叠加在变更上会让归因变难**（见 `03_Jenkins_运行手册.md` 第四节）。已登记为待办。
