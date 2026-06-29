# AI Model Scheduler Benchmark Results
## Test Date: 2026-06-29

### Environment
| Component | Spec |
|-----------|------|
| ECS (K3S Master) | 2C4G, Alibaba Cloud |
| VM (K3S Worker) | 2C4G, Local (WSL2/Tailscale) |
| AutoDL (GPU) | RTX 4090 24GB, 20C 90GB |

### Ollama vs vLLM Performance

| Metric | Ollama (CPU) | vLLM (GPU RTX 4090) |
|--------|-------------|---------------------|
| Model | qwen2.5:0.5b (0.5B) | Qwen2.5-7B-Instruct (7B) |
| Total Latency | 7.398s | 0.236s |
| TTFT | ~352ms | 279ms |
| TPS | 9.4 tok/s | 34.5 tok/s |
| Speedup | baseline | 31x faster |

### Scheduler Routing
- Model-aware routing: qwen2.5:0.5b → Ollama K3S, Qwen2.5-7B → vLLM GPU
- Circuit breaker: functional (OPEN on timeout, HALF_OPEN on recovery)
- Health check: 10s interval, 3 failure threshold
