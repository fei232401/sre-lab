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
- **CI 静默不触发** — 路径过滤放在触发层时依赖上一次构建的工作区,agent 即用即销导致轮询每次 1ms 返回 no-changes 且不报错

### Changed
- **路径过滤下沉** — 从 Jenkins 轮询配置(`PathRestriction`)移到流水线内 `Trigger Guard` stage,在能计算 diff 的地方判定

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