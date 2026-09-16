# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- **构建版本自证指标** — exporter 暴露 `sre_lab_build_info{revision}` ,绕开「Pod 上的 tag 字符串」,由运行时行为直接证明部署的是哪个版本
- **发布回滚演练记录** — 声明式发布 → 收敛 → `git revert` 回滚 → 收敛,双向行为级证据

### Fixed
- **CI 自激循环** — 流水线写回配置仓会触发轮询再次构建,形成无限循环
- **CI 静默不触发** — 路径过滤放在触发层时依赖上一次构建的工作区;临时 agent 已销毁,导致轮询每次返回 no-changes 且不报错
- **Gitea webhook 投递被 SSRF 防护拒绝** — 默认只允许发往公网,私网目标静默失败(仅 Gitea 日志可见);`app.ini` 放行本网段
- **SCM 轮询触发器残留** — Jenkinsfile 未声明它也不会自动移除,与新触发器并存导致每次 push 构建两次;显式从任务配置中删除

### Changed
- **路径过滤下沉** — 从 Jenkins 轮询配置(`PathRestriction`)移到流水线内 `Trigger Guard` stage,在能计算 diff 的地方判定
- **触发方式改为 webhook** — 推送模型提供 `before`/`after` 两个 revision,`Trigger Guard` 因此能判定**整次推送**的变更范围,取代原来只看最后一次提交的简化

### 2026-09-17 — 控制面加固(P0 五项 + 架构层修正)

- **新增** `03-ollama-exporter/test_exporter.py` — 14 个单元用例(标准库 `unittest`,零依赖零网络),取代原来只做 `py_compile` 的 `Lint` stage
- **新增** `ci/notify_alertmanager.py` — 构建失败投递 Alertmanager 告警(触发邮件),恢复时投递同标签的已解决告警
- **新增** `08_重建/CI_重建清单.md` + `08_重建/manifests/` — 控制面「全部可从 Git 重建」的清单与对象定义
- **新增** `ci/job-config.xml` — 活体导出的 Jenkins 任务定义(触发令牌已脱敏)
- **新增** Gitea 的声明式解析 — `argocd` / `jenkins` 各一份 selector-less Service + Endpoints,集群内 `gitea` 不再依赖宿主机 docker DNS
- **修复** 控制面宿主重启后**静默失忆** — Gitea 容器定义 / `gitea` 解析来源 / Jenkins 任务与凭据,三处一起入 Git(见 D18、P26)
- **修复** Jenkins init `CrashLoopBackOff` — 删 Pod 让 StatefulSet 重建即恢复;根因是 emptyDir 里的半截插件下载状态
- **修复** webhook 变量与请求原文进构建日志 — `printPostContent` / `printContributedVariables` 由 `true` 改 `false`
- **修复** buildah 构建无缓存(前半) — `/var/lib/containers` 从 `emptyDir` 换 PVC `jenkins/buildah-storage`;Jenkins 自身那两处见 D21
- **变更** `Lint` stage 更名并升级为 `Test` — 真跑测试,而不是语法检查
- **变更** `post{success/failure}` 从 `echo` 改为真投递告警;顺带修掉日志里那句 `流水线成功: null`
- **变更** 不再把「集群内 `github.com` 的 NodeHosts 条目」当历史残留 — 实测它在承担职责(见 P25)
- **记录** 新增踩坑 P24–P27、决策 D18–D21

### 2026-09-17 — 端到端发布验证 + 验证方法论沉淀

端到端跑通并**留下机器证据**:`push 497b857 → webhook → Jenkins #24 → 14 单测 → 构建/推送镜像 → 写回 GitOps → ArgoCD 收敛 3858e32 → Deployment 滚动到 497b857`。

- **验证** 构建 #24 成功(26991ms),14 个单测通过,镜像 `497b857` 构建并推入仓库,清单写回提交 `3858e32`
- **验证** ArgoCD 6 个 Application 全部收敛到 `3858e32`(auto-sync,`reconciledAt` 持续刷新),Deployment `ai-platform/ollama-exporter` 已滚到 `497b857`
- **验证** 构建 #25 由写回提交 `3858e32` 触发但**跳过构建** —— 推送未涉及 `ci/` 或 `03-ollama-exporter/`,**自激循环被结构性阻断**(Trigger Guard 兜底生效)
- **验证** webhook 请求原文**不再进构建日志**(`printPostContent=false` 生效)
- **验证** 告警链路:Alertmanager 在 71 分钟运行窗口内 `notifications_total|email = 8`、`failed_total|email = 0`;注入告警正确路由到 email receiver,且状态能在 `active → 消失` 间往返(`send_resolved` 配得上对)
- **已知缺口** 三次构建(#23/#24/#25)**全部成功**,`post{failure}` 分支至今**未被真实触发过一次**;"与成功分支共用投递代码"是推演而非实测。已记入 Jenkins 运行手册
- **记录** 新增踩坑 P28–P31(全是**验证方法论**类:`成功通知只在 debug 级记录`、`通知计数器滞后于观测窗口`、`多容器 Pod 读日志不指定 container 返回 400`、`刚推送就查 ArgoCD 会看到旧 revision`)、决策 D22(WSL 副本是编辑源、不强行对齐远端)
- **修正** 运行手册新增「怎么证明失败通知真的到人」四步法,含"观测窗口必须 > `group_interval`"这一前置条件
- **修正** `08_重建/README.md` 新增第七节:读工作副本 `git status` 的两个陷阱(不 fetch 所以不显示 behind;这里的"脏"是设计的一部分)

## [2.0.0] — 2026-06-21

### Added
- **JWT Authentication** — HS256-signed tokens with configurable expiration (60min default), replacing hardcoded API Key
- **Circuit Breaker** — 3-failure threshold → OPEN → 30s timeout → HALF_OPEN → CLOSED recovery cycle
- **Request-Level Retry** — Automatic up-to-2 retries with 1s backoff on Ollama backend failures
- **Token Issuance Endpoint** — `POST /api/auth/token` returns `{access_token, token_type, expires_in}`
- **Prometheus Alerting Rules** — 6 rules covering GPU temperature (80°C/87°C), memory >90%, Ollama down, rate limiting, circuit breaker open
- **Dual-Model Benchmark** — 0.5B vs 1.5B C1-C8 comparison with TTFT/TPOT/Throughput/Token P99
- **PROJECT_NARRATIVE.md** — 11-chapter comprehensive project story

### Changed
- Authentication: `auth_middleware` now supports JWT-first with API Key fallback compatibility
- Configuration: `gateway_config.yaml` expanded with `jwt_*`, `circuit_breaker`, `retry` sections
- Health endpoint: Now includes `circuit_breaker` state in response
- Project structure: Reorganized from flat `scripts/` to numbered modules (`01-gateway-server/`, `02-dashboard/`, `03-benchmark/`, `04-infrastructure/`)

### Fixed
- Gateway startup CWD issue — `start_gateway.py` forces absolute paths
- Ollama Registry GFW bypass — GGUF header validation + Modelfile local import workaround
- requirements.txt GBK encoding — Migrated to pure ASCII

---

## [1.0.0] — 2026-06-20

### Added
- **Inference API Gateway** — FastAPI server with Bearer Token auth, Token Bucket rate limiter, SSE streaming proxy
- **GPU Dashboard** — Dark-themed real-time monitoring with pynvml + matplotlib (4 panels, 3s refresh)
- **Benchmark Framework** — asyncio + aiohttp concurrency testing with TTFT/TPOT/Throughput collection
- **Environment Diagnostics** — 5-layer hardware virtualization diagnostic (WMIC → CPUID → Hypervisor → VBS → MSR)
- **Model Import Tool** — ModelScope GGUF download + Ollama `create` local import
- **WSL2 Enable Script** — PowerShell admin script for Virtual Machine Platform + WSL feature installation
- **Project Documentation** — README, troubleshooting log (5 T-xxx records), final report