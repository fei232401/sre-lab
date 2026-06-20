// ============================================================
// k6 轻量压测脚本 - AI 推理平台
// ============================================================
// 适用场景: 快速验证 API 吞吐量、延迟基线
// 用法:     k6 run k6-script.js --env HOST=http://localhost:8080
// ============================================================

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

// ============================================================
// 自定义指标
// ============================================================
const TTPT = new Trend('ttpt', true);          // Time To First Token (ms)
const TPOT = new Trend('tpot', true);          // Time Per Output Token (ms)
const errorRate = new Rate('errors');
const totalTokens = new Counter('total_tokens');

// ============================================================
// 压测配置 (可通过环境变量覆盖)
// ============================================================
export const options = {
  // 阶梯式加压
  stages: [
    { duration: '30s', target: 5 },    // 预热: 5 VUs
    { duration: '1m',  target: 20 },   // 中等负载: 20 VUs
    { duration: '2m',  target: 20 },   // 稳态: 20 VUs
    { duration: '30s', target: 0 },    // 冷却
  ],

  // 阈值 (超过则标记为失败)
  thresholds: {
    http_req_duration: ['p(90)<10000', 'p(99)<20000'],   // 90% < 10s, 99% < 20s
    errors: ['rate<0.05'],                                  // 错误率 < 5%
  },
};

// ============================================================
// 默认配置
// ============================================================
const HOST = __ENV.HOST || 'http://localhost:8080';
const MODEL = __ENV.MODEL || 'qwen2.5:1.5b';

// 测试 Prompt 集
const LIGHT_PROMPTS = [
  '你好，请用一句话介绍自己。',
  'What is Kubernetes?',
  '解释一下云原生的概念。',
];

const MEDIUM_PROMPTS = [
  '请用300字介绍Kubernetes的核心组件。',
  '解释Docker和Podman的区别，列出至少5点。',
];

// ============================================================
// 测试初始化
// ============================================================
export function setup() {
  console.log(`🚀 k6 压测启动`);
  console.log(`   目标: ${HOST}`);
  console.log(`   模型: ${MODEL}`);

  // 健康检查
  const healthResp = http.get(`${HOST}/api/tags`);
  const healthCheck = check(healthResp, {
    'health_check_status_200': (r) => r.status === 200,
  });

  console.log(`   健康检查: ${healthCheck ? '✅ PASS' : '❌ FAIL'}`);
  return { healthCheck };
}

// ============================================================
// VU 主循环
// ============================================================
export default function () {
  group('AI 推理平台压测', () => {
    // 场景 1: 轻量推理 (70% 流量)
    if (Math.random() < 0.7) {
      lightInference();
    } else {
      // 场景 2: 中等推理 (30% 流量)
      mediumInference();
    }

    // 模拟用户思考间隔
    sleep(1 + Math.random() * 3);
  });
}

// ============================================================
// 轻量推理
// ============================================================
function lightInference() {
  const prompt = LIGHT_PROMPTS[Math.floor(Math.random() * LIGHT_PROMPTS.length)];

  const payload = JSON.stringify({
    model: MODEL,
    prompt: prompt,
    stream: false,  // k6 对 streaming 支持有限，使用非流式
    options: {
      num_predict: 50,
      temperature: 0.7,
    },
  });

  const params = {
    headers: { 'Content-Type': 'application/json' },
    timeout: '60s',
  };

  const startTime = Date.now();
  const resp = http.post(`${HOST}/api/generate`, payload, params);
  const totalTime = Date.now() - startTime;

  const success = check(resp, {
    'light_status_200': (r) => r.status === 200,
    'light_has_response': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.response && body.response.length > 0;
      } catch (e) {
        return false;
      }
    },
  });

  if (!success) {
    errorRate.add(1);
    return;
  }

  errorRate.add(0);

  try {
    const body = JSON.parse(resp.body);
    const evalCount = body.eval_count || 0;

    if (evalCount > 0) {
      // TTPT: k6无法精确测量流式TTPT，这里用总响应时间作为近似
      TTPT.add(totalTime / evalCount);  // 平均每 token 时间
      TPOT.add(totalTime / evalCount);
      totalTokens.add(evalCount);
    }
  } catch (e) {
    // ignore parse errors
  }
}

// ============================================================
// 中等推理
// ============================================================
function mediumInference() {
  const prompt = MEDIUM_PROMPTS[Math.floor(Math.random() * MEDIUM_PROMPTS.length)];

  const payload = JSON.stringify({
    model: MODEL,
    prompt: prompt,
    stream: false,
    options: {
      num_predict: 200,
      temperature: 0.7,
    },
  });

  const params = {
    headers: { 'Content-Type': 'application/json' },
    timeout: '120s',
  };

  const startTime = Date.now();
  const resp = http.post(`${HOST}/api/generate`, payload, params);
  const totalTime = Date.now() - startTime;

  const success = check(resp, {
    'medium_status_200': (r) => r.status === 200,
    'medium_has_response': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.response && body.response.length > 100;
      } catch (e) {
        return false;
      }
    },
  });

  if (!success) {
    errorRate.add(1);
    return;
  }

  errorRate.add(0);

  try {
    const body = JSON.parse(resp.body);
    const evalCount = body.eval_count || 0;

    if (evalCount > 0) {
      TTPT.add(totalTime / evalCount);
      TPOT.add(totalTime / evalCount);
      totalTokens.add(evalCount);
    }
  } catch (e) {
    // ignore
  }
}

// ============================================================
// 测试结束，输出摘要
// ============================================================
export function teardown(data) {
  console.log('\n📊 k6 压测完成');
  console.log('=' .repeat(50));
}