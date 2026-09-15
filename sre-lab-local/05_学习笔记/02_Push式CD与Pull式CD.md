# 学习笔记 02:Push 式 CD 与 Pull 式 CD

> 记录日期:2026-09-16
> 起因:用户提问「jenkins 本身不就能 CD 吗?」

---

## 一、结论先行

**能。Jenkins 完全可以做 CD。** 但 Jenkins 的 CD 和 ArgoCD 的 CD 是**两种不同范式**,解决的问题不完全重叠。

- **Jenkins = Push 式(推)**:CI 系统主动把变更推给集群
- **ArgoCD = Pull 式(拉)**:集群内的 agent 主动去 Git 拉期望状态

---

## 二、两条路径长什么样

### Push 式(Jenkins)

```groovy
// Jenkinsfile
stage('Deploy') {
    steps {
        sh "kubectl --context prod set image deployment/game-server app=ghcr.io/...:${GIT_SHA}"
        // 或者
        sh "helm upgrade game-server ./chart --set image.tag=${GIT_SHA}"
    }
}
```

**前提**:Jenkins 必须持有集群的**管理员凭证**,并且网络能连到集群。

### Pull 式(ArgoCD)

```
Jenkins CI 只管:构建镜像 → 推 registry → 更新 GitOps 仓库里的 image tag
                                                    ↓
                          ArgoCD(在集群里)发现 Git 变了 → 拉取 → 应用
```

**Jenkins 从头到尾不需要碰集群**,也不需要集群凭证。

---

## 三、对比表(面试直接背这个)

| 维度 | **Jenkins Push CD** | **ArgoCD Pull CD** |
|---|---|---|
| 变更方向 | CI 系统 → 集群 | 集群 → Git 仓库 |
| **集群凭证** | ⚠️ **必须把集群 admin 凭证交给 CI** | ✅ **凭证不出集群** |
| **漂移检测** | ❌ 做不到(推完就不管了) | ✅ 核心能力,持续对比 |
| 审计来源 | Jenkins 构建历史 | git log |
| 手动改动 | 无感知,下次部署静默覆盖 | 检测到并纠正 |
| 回滚 | 重跑一次旧版本构建 | `git revert` |
| 网络要求 | CI 要能连到集群 | 集群要能连到 Git |
| 组件数量 | 0(复用 Jenkins) | +1(ArgoCD) |
| 学习成本 | 低 | 中 |

### 最关键的那一行:集群凭证

Push 模式下,Jenkins 需要一份**能改整个集群的凭证**(通常是 `cluster-admin`)。

- Jenkins 一旦被攻破(插件漏洞是 Jenkins 的常见攻击面)→ **等于集群失守**
- CI 系统的攻击面远大于集群内的一个只读 agent

**这是"为什么生产环境倾向 pull 模式"最核心的答案。**

---

## 四、那为什么还要做 Push 式?

因为你**真的会遇到**:

1. **存量系统**:很多公司的 CD 就是 Jenkins 推的,你接手时它就是推的
2. **简单场景**:单集群、单人维护,推模式确实更省事
3. **非 K8s 目标**:部署到虚机、裸机、数据库变更时,ArgoCD 管不了,还是得 Jenkins 推
4. **面试必问**:面试官问"Jenkins 能不能做 CD",答"能,但我更倾向 GitOps"要有依据

---

## 五、本项目的处理方式:两个都做,做对照

**不是二选一,而是同一次发布两条路都跑一遍,把差异实测出来。**

| 路径 | 实现 |
|---|---|
| **主线** | Jenkins CI → 推镜像 → 回写 GitOps repo → ArgoCD pull 部署 |
| **对照** | Jenkins CI → 推镜像 → 同一个 Jenkinsfile 里加一个 stage 直接 `kubectl set image` |

**成本**:约半天(在现有 Jenkinsfile 里加一个 stage)
**产出**:**"我实际对比过 push 和 pull 两种 CD 模式"** —— 这是能压住大部分候选人的东西

### 对照实验要观察什么

| 观察点 | Push 模式 | Pull 模式 |
|---|---|---|
| 部署耗时 | ? | ? |
| 部署后改集群,谁会发现 | 没人 | ArgoCD 报 OutOfSync |
| 回滚怎么操作 | 需要保留历史 tag | `git revert` 一次提交 |
| Jenkins 需要什么权限 | cluster-admin | 只读 Git |

---

## 六、面试怎么讲

> "Jenkins 能做 CD,是 push 模式,在 pipeline 里执行 `kubectl set image` 或 `helm upgrade`。ArgoCD 是 pull 模式,集群内的 agent 去拉 Git 的期望状态。
>
> 核心区别是**集群凭证的边界**:push 模式要把 cluster-admin 凭证交给 Jenkins,Jenkins 的插件生态又是重灾区,一旦被攻破集群就失守;pull 模式下凭证不出集群,只读 Git 就够了。另外 push 模式没有漂移检测能力。
>
> 我实际两条路都跑过,在一个环境里做了对比。存量的非 K8s 部署场景,还是得用 Jenkins push。"

---

## 关联

- [[01_ArgoCD到底是什么]] — 拉模式的具体实现
- `99_决策日志.md` — D2:CD 引擎的决策过程
