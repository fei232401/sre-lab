#!/bin/bash

# =====================================================================
# 🌐 云原生集群全景深度体检脚本 (Cluster Health Check v3.1)
# 适用环境: K3s + ArgoCD + Monitoring + PLG + AI-Platform
# v3.1: 修复所有 numeric 比较中的 whitespace/carriage-return bug
# =====================================================================

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

TOTAL_CHECKS=0
PASS_CHECKS=0
WARN_CHECKS=0
FAIL_CHECKS=0
INFO_COUNT=0

declare -a FAIL_ITEMS
declare -a WARN_ITEMS
declare -a INFO_ITEMS

# Sanitize any numeric value: strip all whitespace/newlines/carriage returns
san() { echo "$1" | tr -d '[:space:]'; }

separator() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

check_status() {
  local description=$1
  local condition=$2
  
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  
  if [ "$condition" = "PASS" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} | $description"
    PASS_CHECKS=$((PASS_CHECKS + 1))
  elif [ "$condition" = "WARN" ]; then
    echo -e "  ${YELLOW}⚠️  WARN${NC} | $description"
    WARN_CHECKS=$((WARN_CHECKS + 1))
    WARN_ITEMS+=("$description")
  elif [ "$condition" = "INFO" ]; then
    echo -e "  ${BLUE}ℹ️  INFO${NC} | $description"
    INFO_COUNT=$((INFO_COUNT + 1))
    INFO_ITEMS+=("$description")
  else
    echo -e "  ${RED}❌ FAIL${NC} | $description"
    FAIL_CHECKS=$((FAIL_CHECKS + 1))
    FAIL_ITEMS+=("$description")
  fi
}

clear
echo -e "${BLUE}"
echo "  ╔═══════════════════════════════════════════════════════════════╗"
echo "  ║       🌐 云原生 AI 平台集群全景深度体检报告 v3.1            ║"
echo "  ║       Cluster Health Check & Architecture Audit             ║"
echo "  ╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  当前用户: $(whoami) | 集群上下文: $(kubectl config current-context 2>/dev/null || echo 'Unknown')"
separator

# =====================================================================
# 1. 基础设施与节点层
# =====================================================================
echo -e "\n${CYAN}🔍 [1/8] 基础设施与节点状态 (Infrastructure & Nodes)${NC}"
separator

# 1.1 节点 Ready 状态
NODE_READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | grep -c "Ready" || echo 0)
NODE_READY_COUNT=$(san "$NODE_READY_COUNT")
NODE_TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
NODE_TOTAL=$(san "$NODE_TOTAL")
NOT_READY=$((NODE_TOTAL - NODE_READY_COUNT))
if [ "$NOT_READY" -eq 0 ] && [ "$NODE_TOTAL" -gt 0 ]; then
  check_status "所有 K8s 节点状态均为 Ready (共 $NODE_TOTAL 个)" "PASS"
else
  BAD_NODES=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"{print $1"("$2")"}' | tr '\n' ' ')
  check_status "K8s 节点状态异常: $NOT_READY/$NODE_TOTAL NotReady: $BAD_NODES" "FAIL"
fi

# 1.2 节点资源使用率
if kubectl top nodes >/dev/null 2>&1; then
  # kubectl top nodes 列: NAME CPU(cores) CPU% MEMORY(bytes) MEMORY%
  MEM_OVER_85=$(kubectl top nodes --no-headers 2>/dev/null | awk '{gsub(/%/,""); if($5+0 > 85) print $1" "$5"%"}' | tr '\n' ' ')
  CPU_OVER_85=$(kubectl top nodes --no-headers 2>/dev/null | awk '{gsub(/%/,""); if($3+0 > 85) print $1" "$3"%"}' | tr '\n' ' ')
  MEM_OVER_85=$(san "$MEM_OVER_85")
  CPU_OVER_85=$(san "$CPU_OVER_85")
  if [ -z "$MEM_OVER_85" ]; then
    check_status "所有节点内存使用率健康 (< 85%)" "PASS"
  else
    check_status "节点内存压力过高 (> 85%): $MEM_OVER_85" "WARN"
  fi
  if [ -z "$CPU_OVER_85" ]; then
    check_status "所有节点 CPU 使用率健康 (< 85%)" "PASS"
  else
    check_status "节点 CPU 压力过高 (> 85%): $CPU_OVER_85" "WARN"
  fi
else
  check_status "metrics-server 不可用, 无法检查资源使用率" "WARN"
fi

# 1.3 kube-system Pod 状态
SYS_TOTAL=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l)
SYS_TOTAL=$(san "$SYS_TOTAL")
SYS_BAD=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
SYS_BAD=$(san "$SYS_BAD")
if [ "$SYS_BAD" -eq 0 ]; then
  check_status "kube-system 核心组件全部正常 ($SYS_TOTAL 个)" "PASS"
else
  SYS_BAD_LIST=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" | awk '{print $1"("$3")"}' | tr '\n' ' ')
  check_status "kube-system 存在异常 Pod: $SYS_BAD_LIST" "WARN"
fi

# 1.4 kube-system 重启计数
HIGH_RESTART=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | awk '{if($4+0 > 5) print $1" 重启"$4"次"}' | tr '\n' ' ')
if [ -z "$HIGH_RESTART" ]; then
  check_status "kube-system 无频繁重启 Pod (重启 > 5 次)" "PASS"
else
  check_status "kube-system 存在频繁重启 Pod: $HIGH_RESTART" "WARN"
fi

# =====================================================================
# 2. 存储与持久化层
# =====================================================================
echo -e "\n${CYAN}🔍 [2/8] 存储与持久化层 (PV/PVC/Storage)${NC}"
separator

# 2.1 PVC
PVC_TOTAL=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)
PVC_TOTAL=$(san "$PVC_TOTAL")
PVC_PENDING=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep "Pending" | wc -l)
PVC_PENDING=$(san "$PVC_PENDING")
if [ "$PVC_PENDING" -eq 0 ]; then
  check_status "所有 PVC 状态正常 (共 $PVC_TOTAL 个, 无 Pending)" "PASS"
else
  PENDING_PVC_LIST=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep "Pending" | awk '{print $1"/"$2"("$6")"}' | tr '\n' ' ')
  check_status "存在 Pending 状态的 PVC: $PENDING_PVC_LIST" "FAIL"
fi

# 2.2 PV
PV_TOTAL=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
PV_TOTAL=$(san "$PV_TOTAL")
PV_BOUND=$(kubectl get pv --no-headers 2>/dev/null | grep "Bound" | wc -l)
PV_BOUND=$(san "$PV_BOUND")
PV_AVAIL=$(kubectl get pv --no-headers 2>/dev/null | grep "Available" | wc -l)
PV_AVAIL=$(san "$PV_AVAIL")
PV_GOOD=$((PV_BOUND + PV_AVAIL))
PV_FAILED=$((PV_TOTAL - PV_GOOD))
if [ "$PV_FAILED" -le 0 ]; then
  check_status "所有 PV 状态正常 (共 $PV_TOTAL 个)" "PASS"
else
  PV_FAILED_LIST=$(kubectl get pv --no-headers 2>/dev/null | grep -v "Bound\|Available" | awk '{print $1"("$5")"}' | tr '\n' ' ')
  check_status "存在异常 PV ($PV_FAILED 个): $PV_FAILED_LIST" "WARN"
fi

# 2.3 磁盘
DISK_USE=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')
DISK_USE=$(san "$DISK_USE")
if [ -n "$DISK_USE" ] && [ "$DISK_USE" -ge 0 ] 2>/dev/null; then
  if [ "$DISK_USE" -lt 80 ]; then
    check_status "根分区磁盘使用率健康 (${DISK_USE}%)" "PASS"
  elif [ "$DISK_USE" -lt 90 ]; then
    check_status "根分区磁盘使用率偏高 (${DISK_USE}%), 建议关注" "WARN"
  else
    check_status "根分区磁盘使用率过高 (${DISK_USE}%), 需立即清理" "FAIL"
  fi
else
  check_status "无法获取磁盘使用率" "WARN"
fi

# =====================================================================
# 3. GitOps 交付层 (ArgoCD)
# =====================================================================
echo -e "\n${CYAN}🔍 [3/8] GitOps 自动化交付层 (ArgoCD)${NC}"
separator

if kubectl get namespace argocd >/dev/null 2>&1; then
  check_status "ArgoCD 命名空间存在" "PASS"
  
  ARGO_TOTAL=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
  ARGO_TOTAL=$(san "$ARGO_TOTAL")
  ARGO_BAD=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
  ARGO_BAD=$(san "$ARGO_BAD")
  
  if [ "$ARGO_BAD" -eq 0 ]; then
    check_status "ArgoCD 核心组件全部正常运行 ($ARGO_TOTAL 个)" "PASS"
  else
    ARGO_BAD_LIST=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -v "Running\|Completed" | awk '{print $1"("$3")"}' | tr '\n' ' ')
    check_status "ArgoCD 存在异常 Pod ($ARGO_BAD 个): $ARGO_BAD_LIST" "FAIL"
    
    for pod in $(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -v "Running\|Completed" | awk '{print $1}'); do
      EVENTS=$(kubectl describe pod -n argocd "$pod" 2>/dev/null | grep -A2 "Events:" | tail -5 | grep -i "Warning\|Failed\|Error" | head -2 | sed 's/^[[:space:]]*/    /')
      if [ -n "$EVENTS" ]; then
        echo -e "  ${MAGENTA}  └─ $pod 事件详情:${NC}"
        echo -e "${RED}$EVENTS${NC}"
      fi
    done
  fi

  if kubectl get applications -n argocd >/dev/null 2>&1; then
    APP_TOTAL=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
    APP_TOTAL=$(san "$APP_TOTAL")
    OUT_OF_SYNC=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$2!="Synced"' | wc -l)
    OUT_OF_SYNC=$(san "$OUT_OF_SYNC")
    DEGRADED=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$3!="Healthy"' | wc -l)
    DEGRADED=$(san "$DEGRADED")
    
    if [ "$OUT_OF_SYNC" -eq 0 ]; then
      check_status "所有 ArgoCD Applications 均为 Synced ($APP_TOTAL 个)" "PASS"
    else
      OUT_LIST=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$2!="Synced"{print $1"("$2")"}' | tr '\n' ' ')
      check_status "存在未同步 Applications ($OUT_OF_SYNC 个): $OUT_LIST" "FAIL"
    fi
    
    if [ "$DEGRADED" -eq 0 ]; then
      check_status "所有 ArgoCD Applications 均为 Healthy" "PASS"
    else
      DEG_LIST=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$3!="Healthy"{print $1"("$3")"}' | tr '\n' ' ')
      check_status "存在不健康 Applications ($DEGRADED 个): $DEG_LIST" "FAIL"
    fi
  fi
else
  check_status "ArgoCD 命名空间不存在" "FAIL"
fi

# =====================================================================
# 4. 监控与告警层
# =====================================================================
echo -e "\n${CYAN}🔍 [4/8] 全链路监控与告警层 (Monitoring)${NC}"
separator

MON_TOTAL=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
MON_TOTAL=$(san "$MON_TOTAL")
MON_CORE_BAD=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -E "prometheus|alertmanager|grafana" | grep -v "Running" | wc -l)
MON_CORE_BAD=$(san "$MON_CORE_BAD")
if [ "$MON_CORE_BAD" -eq 0 ]; then
  check_status "Prometheus / Alertmanager / Grafana 核心组件运行正常" "PASS"
else
  MON_CORE_LIST=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -E "prometheus|alertmanager|grafana" | grep -v "Running" | awk '{print $1}' | tr '\n' ' ')
  check_status "监控核心组件存在异常: $MON_CORE_LIST" "FAIL"
fi

MON_ALL_BAD=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
MON_ALL_BAD=$(san "$MON_ALL_BAD")
if [ "$MON_ALL_BAD" -eq 0 ]; then
  check_status "监控命名空间所有 Pod 运行正常 ($MON_TOTAL 个)" "PASS"
else
  MON_BAD_LIST=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -v "Running\|Completed" | awk '{print $1"("$3")"}' | tr '\n' ' ')
  check_status "监控命名空间存在异常 Pod ($MON_ALL_BAD 个): $MON_BAD_LIST" "WARN"
fi

PROM_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PROM_POD" ]; then
  TARGETS_JSON=$(kubectl exec -n monitoring "$PROM_POD" -c prometheus -- /bin/sh -c "command -v curl >/dev/null && curl -s http://localhost:9090/api/v1/targets || command -v wget >/dev/null && wget -qO- http://localhost:9090/api/v1/targets" 2>/dev/null || echo "")
  DOWN_TARGETS=$(echo "$TARGETS_JSON" | grep -o '"health":"down"' | wc -l)
  DOWN_TARGETS=$(san "$DOWN_TARGETS")
  UP_TARGETS=$(echo "$TARGETS_JSON" | grep -o '"health":"up"' | wc -l)
  UP_TARGETS=$(san "$UP_TARGETS")
  if [ -z "$TARGETS_JSON" ]; then
    check_status "Prometheus API 不可达 (容器内无 curl/wget, 或网络问题)" "WARN"
  fi
  if [ "$DOWN_TARGETS" -eq 0 ]; then
    check_status "Prometheus 所有抓取目标均为 UP (共 $UP_TARGETS 个)" "PASS"
  else
    check_status "Prometheus 存在 DOWN 目标 ($DOWN_TARGETS 个), UP: $UP_TARGETS" "WARN"
  fi
else
  check_status "未找到 Prometheus Pod" "WARN"
fi

SM_COUNT=$(kubectl get servicemonitor --all-namespaces --no-headers 2>/dev/null | wc -l)
SM_COUNT=$(san "$SM_COUNT")
if [ "$SM_COUNT" -gt 3 ]; then
  check_status "ServiceMonitor 发现正常 (当前 $SM_COUNT 个)" "PASS"
else
  check_status "ServiceMonitor 数量偏少 ($SM_COUNT 个), 可能发现失败" "WARN"
fi

# =====================================================================
# 5. 日志中枢层
# =====================================================================
echo -e "\n${CYAN}🔍 [5/8] 轻量级日志中枢层 (PLG Stack)${NC}"
separator

if kubectl get namespace logging >/dev/null 2>&1; then
  LOKI_POD=$(kubectl get pods -n logging -l app=loki -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$LOKI_POD" ]; then
    LOKI_READY=$(kubectl exec -n logging "$LOKI_POD" -- wget -qO- http://localhost:3100/ready 2>/dev/null || echo "")
    if [[ "$LOKI_READY" == *"ready"* ]]; then
      check_status "Loki 服务状态正常 (Ready)" "PASS"
    else
      check_status "Loki 服务未就绪 (Not Ready)" "FAIL"
    fi
  else
    check_status "未找到 Loki Pod" "FAIL"
  fi

  PROMTAIL_DESIRED=$(kubectl get daemonset promtail -n logging -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
  PROMTAIL_READY=$(kubectl get daemonset promtail -n logging -o jsonpath='{.status.numberReady}' 2>/dev/null)
  PROMTAIL_DESIRED=$(san "$PROMTAIL_DESIRED")
  PROMTAIL_READY=$(san "$PROMTAIL_READY")
  if [ "$PROMTAIL_DESIRED" = "$PROMTAIL_READY" ] && [ -n "$PROMTAIL_DESIRED" ] && [ "$PROMTAIL_DESIRED" -gt 0 ]; then
    check_status "Promtail DaemonSet 全部就绪 ($PROMTAIL_READY/$PROMTAIL_DESIRED)" "PASS"
  else
    check_status "Promtail DaemonSet 未完全就绪 ($PROMTAIL_READY/$PROMTAIL_DESIRED)" "FAIL"
  fi

  PROMTAIL_POD=$(kubectl get pods -n logging -l app=promtail -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$PROMTAIL_POD" ]; then
    PROMTAIL_READY_STATUS=$(kubectl get pod -n logging "$PROMTAIL_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    PROMTAIL_RESTARTS=$(kubectl get pod -n logging "$PROMTAIL_POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    PROMTAIL_RESTARTS=$(san "$PROMTAIL_RESTARTS")
    if [ "$PROMTAIL_READY_STATUS" = "true" ]; then
      LINES_SENT=$(kubectl logs -n logging "$PROMTAIL_POD" --tail=20 2>/dev/null | grep -ci "successfully sent\|component=file_pipeline\|msg=\"send" 2>/dev/null || echo 0)
      LINES_SENT=$(san "$LINES_SENT")
      if [ "$LINES_SENT" -gt 0 ]; then
        check_status "Promtail 日志推送正常 (检测到成功发送日志)" "PASS"
      else
        check_status "Promtail 运行中但未检测到日志推送, 请检查配置" "WARN"
      fi
    else
      check_status "Promtail 容器未就绪 (重启 $PROMTAIL_RESTARTS 次)" "FAIL"
    fi
  else
    check_status "未找到 Promtail Pod" "WARN"
  fi
else
  check_status "logging 命名空间不存在, PLG Stack 未部署" "INFO"
fi

# =====================================================================
# 6. 业务应用层
# =====================================================================
echo -e "\n${CYAN}🔍 [6/8] 业务应用层 (AI-Platform & Other Apps)${NC}"
separator

# AI-Platform
AI_TOTAL=$(kubectl get pods -n ai-platform --no-headers 2>/dev/null | wc -l)
AI_TOTAL=$(san "$AI_TOTAL")
AI_BAD=$(kubectl get pods -n ai-platform --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
AI_BAD=$(san "$AI_BAD")
if [ "$AI_BAD" -eq 0 ]; then
  check_status "AI-Platform (Ollama/Open-WebUI) 所有 Pod 正常 ($AI_TOTAL 个)" "PASS"
else
  AI_BAD_LIST=$(kubectl get pods -n ai-platform --no-headers 2>/dev/null | grep -v "Running\|Completed" | awk '{print $1"("$2"/"$3")"}' | tr '\n' ' ')
  check_status "AI-Platform 存在异常 Pod: $AI_BAD_LIST" "FAIL"
fi

AI_RESTART_HIGH=$(kubectl get pods -n ai-platform --no-headers 2>/dev/null | awk '{if($4+0 > 5) print $1" 重启"$4"次"}' | tr '\n' ' ')
if [ -z "$AI_RESTART_HIGH" ]; then
  check_status "AI-Platform 无频繁重启 Pod" "PASS"
else
  check_status "AI-Platform 存在频繁重启 Pod: $AI_RESTART_HIGH" "WARN"
fi

# Nginx-Demo
NGINX_TOTAL=$(kubectl get pods -n nginx-demo --no-headers 2>/dev/null | wc -l)
NGINX_TOTAL=$(san "$NGINX_TOTAL")
NGINX_BAD=$(kubectl get pods -n nginx-demo --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
NGINX_BAD=$(san "$NGINX_BAD")
if [ "$NGINX_BAD" -eq 0 ]; then
  check_status "Nginx-Demo 测试应用运行正常 ($NGINX_TOTAL 个)" "PASS"
else
  NGINX_BAD_LIST=$(kubectl get pods -n nginx-demo --no-headers 2>/dev/null | grep -v "Running\|Completed" | awk '{print $1"("$3")"}' | tr '\n' ' ')
  check_status "Nginx-Demo 存在异常 Pod: $NGINX_BAD_LIST" "WARN"
fi

# =====================================================================
# 7. 网络与路由层
# =====================================================================
echo -e "\n${CYAN}🔍 [7/8] 网络与路由层 (Traefik Ingress)${NC}"
separator

TRAEFIK_TOTAL=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers 2>/dev/null | wc -l)
TRAEFIK_TOTAL=$(san "$TRAEFIK_TOTAL")
TRAEFIK_RUNNING=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers 2>/dev/null | grep "Running" | wc -l)
TRAEFIK_RUNNING=$(san "$TRAEFIK_RUNNING")
if [ "$TRAEFIK_TOTAL" -gt 0 ] && [ "$TRAEFIK_RUNNING" = "$TRAEFIK_TOTAL" ]; then
  check_status "Traefik Ingress Controller 运行正常 ($TRAEFIK_TOTAL 个)" "PASS"
elif [ "$TRAEFIK_TOTAL" -eq 0 ]; then
  check_status "未找到 Traefik Pod, 请检查 Ingress Controller 部署" "WARN"
else
  TRAEFIK_BAD=$((TRAEFIK_TOTAL - TRAEFIK_RUNNING))
  check_status "Traefik Ingress Controller 异常 ($TRAEFIK_BAD/$TRAEFIK_TOTAL)" "FAIL"
fi

# Ingress 地址分配 (修复: 原脚本误用 $3 CLASS 列)
INGRESS_COUNT=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l)
INGRESS_COUNT=$(san "$INGRESS_COUNT")
# ADDRESS 是第5列 (NAMESPACE NAME CLASS HOSTS ADDRESS PORTS AGE)
INGRESS_NO_ADDR=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | awk '{if($5=="<none>" || $5=="") print}' | wc -l)
INGRESS_NO_ADDR=$(san "$INGRESS_NO_ADDR")
if [ "$INGRESS_NO_ADDR" -eq 0 ]; then
  check_status "所有 Ingress 均已成功分配地址 ($INGRESS_COUNT 个)" "PASS"
else
  NO_ADDR_LIST=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | awk '{if($5=="<none>" || $5=="") print $1"/"$2}' | tr '\n' ' ')
  check_status "存在未分配地址的 Ingress ($INGRESS_NO_ADDR 个): $NO_ADDR_LIST" "WARN"
fi

INGRESS_NO_CLASS=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | awk '{if($3=="<none>" || $3=="") print}' | wc -l)
INGRESS_NO_CLASS=$(san "$INGRESS_NO_CLASS")
if [ "$INGRESS_NO_CLASS" -eq 0 ]; then
  check_status "所有 Ingress 均已指定 IngressClass" "PASS"
else
  NO_CLASS_LIST=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | awk '{if($3=="<none>" || $3=="") print $1"/"$2}' | tr '\n' ' ')
  check_status "存在未指定 IngressClass 的 Ingress ($INGRESS_NO_CLASS 个): $NO_CLASS_LIST (可能依赖默认 IngressClass)" "INFO"
fi

# =====================================================================
# 8. 集群事件与安全审计
# =====================================================================
echo -e "\n${CYAN}🔍 [8/8] 集群事件与安全审计 (Events & Security)${NC}"
separator

WARNING_COUNT=$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers 2>/dev/null | wc -l)
WARNING_COUNT=$(san "$WARNING_COUNT")
if [ "$WARNING_COUNT" -eq 0 ]; then
  check_status "集群无 Warning 级别事件" "PASS"
elif [ "$WARNING_COUNT" -le 10 ]; then
  check_status "集群存在少量 Warning 事件 ($WARNING_COUNT 个)" "WARN"
else
  check_status "集群存在大量 Warning 事件 ($WARNING_COUNT 个), 需排查" "WARN"
fi

if [ "$WARNING_COUNT" -gt 0 ]; then
  RECENT_WARNINGS=$(kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -5 | awk '{printf "%-12s %-3s: %s\n", $1, $5, $7}' | sed 's/^/    /')
  echo -e "  ${YELLOW}最近 Warning 事件:${NC}"
  echo -e "${YELLOW}$RECENT_WARNINGS${NC}"
fi

PENDING_COUNT=$(kubectl get pods --all-namespaces --field-selector status.phase=Pending --no-headers 2>/dev/null | wc -l)
PENDING_COUNT=$(san "$PENDING_COUNT")
if [ "$PENDING_COUNT" -eq 0 ]; then
  check_status "无 Pending 状态的 Pod" "PASS"
else
  PENDING_LIST=$(kubectl get pods --all-namespaces --field-selector status.phase=Pending --no-headers 2>/dev/null | awk '{print $1"/"$2}' | tr '\n' ' ')
  check_status "存在 Pending 状态的 Pod ($PENDING_COUNT 个): $PENDING_LIST" "FAIL"
fi

IMAGE_PULL_FAIL=$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers 2>/dev/null | grep -ci "FailedToPull\|ErrImagePull\|ImagePullBackOff" 2>/dev/null || echo 0)
IMAGE_PULL_FAIL=$(san "$IMAGE_PULL_FAIL")
if [ "$IMAGE_PULL_FAIL" -eq 0 ]; then
  check_status "无镜像拉取失败事件" "PASS"
else
  check_status "存在镜像拉取失败事件 ($IMAGE_PULL_FAIL 次)" "FAIL"
fi

# =====================================================================
# 📊 最终汇总报告
# =====================================================================
separator
echo -e "\n${BLUE}📊 集群健康度综合评估报告 (Executive Summary)${NC}"
separator

if [ $TOTAL_CHECKS -gt 0 ]; then
  SCORE=$(( (PASS_CHECKS * 100) / TOTAL_CHECKS ))
else
  SCORE=0
fi

if [ $SCORE -ge 90 ]; then
  GRADE="A (卓越)"; GRADE_COLOR=$GREEN
elif [ $SCORE -ge 75 ]; then
  GRADE="B (良好)"; GRADE_COLOR=$YELLOW
elif [ $SCORE -ge 60 ]; then
  GRADE="C (及格)"; GRADE_COLOR=$YELLOW
else
  GRADE="D (需干预)"; GRADE_COLOR=$RED
fi

echo -e "  总检查项: ${TOTAL_CHECKS}"
echo -e "  ${GREEN}✅ 通过: ${PASS_CHECKS}${NC}  |  ${YELLOW}⚠️ 警告: ${WARN_CHECKS}${NC}  |  ${RED}❌ 失败: ${FAIL_CHECKS}${NC}  |  ${BLUE}ℹ️  信息: ${INFO_COUNT}${NC}"
echo -e ""
echo -e "  🏆 综合健康评分: ${GRADE_COLOR}${SCORE} 分 (评级: ${GRADE})${NC}"
separator

if [ ${#FAIL_ITEMS[@]} -gt 0 ]; then
  echo -e "\n${RED}🚨 关键失败项 (需立即修复):${NC}"
  for item in "${FAIL_ITEMS[@]}"; do
    echo -e "  ${RED}❌${NC} $item"
  done
fi

if [ ${#WARN_ITEMS[@]} -gt 0 ]; then
  echo -e "\n${YELLOW}⚠️ 警告项 (建议关注):${NC}"
  for item in "${WARN_ITEMS[@]}"; do
    echo -e "  ${YELLOW}⚠️${NC} $item"
  done
fi

if [ ${#INFO_ITEMS[@]} -gt 0 ]; then
  echo -e "\n${BLUE}ℹ️  信息项:${NC}"
  for item in "${INFO_ITEMS[@]}"; do
    echo -e "  ${BLUE}ℹ️${NC} $item"
  done
fi

echo -e "\n${CYAN}💡 架构师建议:${NC}"
if [ $FAIL_CHECKS -eq 0 ] && [ $WARN_CHECKS -eq 0 ]; then
  echo -e "  🎉 集群核心架构运行完美！您可以放心进行下一步的压测或业务部署。"
elif [ $FAIL_CHECKS -eq 0 ]; then
  echo -e "  👀 集群运行正常, 但存在若干告警项, 重点关注:"
  for item in "${WARN_ITEMS[@]}"; do
    echo -e "    - $item"
  done
else
  echo -e "  🔧 集群存在关键组件异常, 请优先解决 FAIL 项。常见排查命令:"
  echo -e "     - kubectl describe pod <pod-name> -n <namespace>"
  echo -e "     - kubectl logs <pod-name> -n <namespace>"
  echo -e "     - kubectl get events --all-namespaces --field-selector type=Warning"
fi
separator
echo ""