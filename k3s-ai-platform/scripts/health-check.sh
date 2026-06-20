#!/bin/bash
#===============================================================================
# K3S AI Platform 健康检查脚本
# 版本: v4.0.0
# 更新: 2026-06-20
#===============================================================================

set -o pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 统计变量
TOTAL_CHECKS=0
PASS_CHECKS=0
WARN_CHECKS=0
FAIL_CHECKS=0
INFO_COUNT=0

declare -a FAIL_ITEMS
declare -a WARN_ITEMS
declare -a INFO_ITEMS

# 工具函数
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

# 打印标题
clear
echo -e "${BLUE}"
echo "  ╔═══════════════════════════════════════════════════════════════╗"
echo "  ║       🌐 K3S AI Platform 全景深度体检报告 v4.0.0             ║"
echo "  ║       K3S-AI-PLATFORM Health Check & Architecture Audit     ║"
echo "  ╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  当前用户: $(whoami) | 集群上下文: $(kubectl config current-context 2>/dev/null || echo 'Unknown')"
separator

#===============================================================================
# 1. 基础设施与节点层
#===============================================================================
echo -e "\n${CYAN}🔍 [1/9] 基础设施与节点状态 (Infrastructure & Nodes)${NC}"
separator

# 1.1 节点状态
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

# 1.2 节点资源
if kubectl top nodes >/dev/null 2>&1; then
  MEM_OVER_85=$(kubectl top nodes --no-headers 2>/dev/null | awk '{gsub(/%/,""); if($5+0 > 85) print $1" "$5"%"}' | tr '\n' ' ')
  CPU_OVER_85=$(kubectl top nodes --no-headers 2>/dev/null | awk '{gsub(/%/,""); if($3+0 > 85) print $1" "$3"%"}' | tr '\n' ' ')
  MEM_OVER_85=$(san "$MEM_OVER_85")
  CPU_OVER_85=$(san "$CPU_OVER_85")
  [ -z "$MEM_OVER_85" ] && check_status "所有节点内存使用率健康 (< 85%)" "PASS" || check_status "节点内存压力过高 (> 85%): $MEM_OVER_85" "WARN"
  [ -z "$CPU_OVER_85" ] && check_status "所有节点 CPU 使用率健康 (< 85%)" "PASS" || check_status "节点 CPU 压力过高 (> 85%): $CPU_OVER_85" "WARN"
else
  check_status "metrics-server 不可用, 无法检查资源使用率" "WARN"
fi

# 1.3 kube-system组件
SYS_BAD=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
SYS_BAD=$(san "$SYS_BAD")
[ "$SYS_BAD" -eq 0 ] && check_status "kube-system 核心组件全部正常" "PASS" || check_status "kube-system 存在异常 Pod: $(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" | awk '{print $1}' | tr '\n' ' ')" "WARN"

HIGH_RESTART=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | awk '{if($4+0 > 5) print $1" 重启"$4"次"}' | tr '\n' ' ')
[ -z "$HIGH_RESTART" ] && check_status "kube-system 无频繁重启 Pod (重启 > 5 次)" "PASS" || check_status "kube-system 存在频繁重启 Pod: $HIGH_RESTART" "WARN"

#===============================================================================
# 2. 存储与持久化层
#===============================================================================
echo -e "\n${CYAN}🔍 [2/9] 存储与持久化层 (PV/PVC/Storage)${NC}"
separator

PVC_PENDING=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep "Pending" | wc -l)
PVC_PENDING=$(san "$PVC_PENDING")
PVC_TOTAL=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)
PVC_TOTAL=$(san "$PVC_TOTAL")
[ "$PVC_PENDING" -eq 0 ] && check_status "所有 PVC 状态正常 (共 $PVC_TOTAL 个, 无 Pending)" "PASS" || check_status "存在 Pending 状态的 PVC: $(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep "Pending" | awk '{print $1"/"$2}' | tr '\n' ' ')" "FAIL"

PV_FAILED=$(( $(kubectl get pv --no-headers 2>/dev/null | wc -l) - $(kubectl get pv --no-headers 2>/dev/null | grep "Bound\|Available" | wc -l) ))
PV_FAILED=$(san "$PV_FAILED")
[ "$PV_FAILED" -le 0 ] && check_status "所有 PV 状态正常" "PASS" || check_status "存在异常 PV ($PV_FAILED 个)" "WARN"

DISK_USE=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')
DISK_USE=$(san "$DISK_USE")
if [ -n "$DISK_USE" ] && [ "$DISK_USE" -lt 80 ]; then
  check_status "根分区磁盘使用率健康 (${DISK_USE}%)" "PASS"
elif [ -n "$DISK_USE" ] && [ "$DISK_USE" -lt 90 ]; then
  check_status "根分区磁盘使用率偏高 (${DISK_USE}%), 建议关注" "WARN"
else
  [ -n "$DISK_USE" ] && check_status "根分区磁盘使用率过高 (${DISK_USE}%), 需立即清理" "FAIL" || check_status "无法获取磁盘使用率" "WARN"
fi

#===============================================================================
# 3. GitOps 交付层 (ArgoCD)
#===============================================================================
echo -e "\n${CYAN}🔍 [3/9] GitOps 自动化交付层 (ArgoCD)${NC}"
separator

if kubectl get namespace argocd >/dev/null 2>&1; then
  check_status "ArgoCD 命名空间存在" "PASS"

  ARGO_BAD=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
  ARGO_BAD=$(san "$ARGO_BAD")
  ARGO_TOTAL=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
  ARGO_TOTAL=$(san "$ARGO_TOTAL")
  [ "$ARGO_BAD" -eq 0 ] && check_status "ArgoCD 核心组件全部正常运行 ($ARGO_TOTAL 个)" "PASS" || check_status "ArgoCD 存在异常 Pod ($ARGO_BAD 个): $(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -v "Running\|Completed" | awk '{print $1}' | tr '\n' ' ')" "FAIL"

  if kubectl get applications -n argocd >/dev/null 2>&1; then
    APP_TOTAL=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
    OUT_OF_SYNC=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$2!="Synced"' | wc -l)
    DEGRADED=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$3!="Healthy"' | wc -l)
    APP_TOTAL=$(san "$APP_TOTAL")
    OUT_OF_SYNC=$(san "$OUT_OF_SYNC")
    DEGRADED=$(san "$DEGRADED")
    [ "$OUT_OF_SYNC" -eq 0 ] && check_status "所有 ArgoCD Applications 均为 Synced ($APP_TOTAL 个)" "PASS" || check_status "存在未同步 Applications ($OUT_OF_SYNC 个)" "FAIL"
    [ "$DEGRADED" -eq 0 ] && check_status "所有 ArgoCD Applications 均为 Healthy" "PASS" || check_status "存在不健康 Applications ($DEGRADED 个)" "FAIL"
  fi
else
  check_status "ArgoCD 命名空间不存在" "FAIL"
fi

#===============================================================================
# 4. 监控与告警层
#===============================================================================
echo -e "\n${CYAN}🔍 [4/9] 全链路监控与告警层 (Monitoring)${NC}"
separator

MON_CORE_BAD=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -E "prometheus|alertmanager|grafana" | grep -v "Running" | wc -l)
MON_CORE_BAD=$(san "$MON_CORE_BAD")
[ "$MON_CORE_BAD" -eq 0 ] && check_status "Prometheus / Alertmanager / Grafana 核心组件运行正常" "PASS" || check_status "监控核心组件存在异常" "FAIL"

MON_ALL_BAD=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
MON_ALL_BAD=$(san "$MON_ALL_BAD")
MON_TOTAL=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
MON_TOTAL=$(san "$MON_TOTAL")
[ "$MON_ALL_BAD" -eq 0 ] && check_status "监控命名空间所有 Pod 运行正常 ($MON_TOTAL 个)" "PASS" || check_status "监控命名空间存在异常 Pod ($MON_ALL_BAD 个)" "WARN"

SM_COUNT=$(kubectl get servicemonitor --all-namespaces --no-headers 2>/dev/null | wc -l)
SM_COUNT=$(san "$SM_COUNT")
[ "$SM_COUNT" -gt 3 ] && check_status "ServiceMonitor 发现正常 (当前 $SM_COUNT 个)" "PASS" || check_status "ServiceMonitor 数量偏少 ($SM_COUNT 个)" "WARN"

WECHAT_POD=$(kubectl get pods -n monitoring -l app=wechat-adapter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$WECHAT_POD" ] && check_status "WeChat Adapter 告警推送组件运行正常" "PASS" || check_status "未部署 WeChat Adapter" "INFO"

SEAL_POD=$(kubectl get pods -n kube-system -l name=sealed-secrets-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$SEAL_POD" ] && check_status "Sealed Secrets 控制器运行正常" "PASS" || check_status "未部署 Sealed Secrets" "INFO"

#===============================================================================
# 5. 日志中枢层
#===============================================================================
echo -e "\n${CYAN}🔍 [5/9] 轻量级日志中枢层 (PLG Stack)${NC}"
separator

if kubectl get namespace logging >/dev/null 2>&1; then
  LOKI_POD=$(kubectl get pods -n logging -l app=loki -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$LOKI_POD" ]; then
    LOKI_READY=$(kubectl exec -n logging "$LOKI_POD" -- wget -qO- http://localhost:3100/ready 2>/dev/null || echo "")
    [[ "$LOKI_READY" == *"ready"* ]] && check_status "Loki 服务状态正常" "PASS" || check_status "Loki 服务未就绪" "FAIL"
  else
    check_status "未找到 Loki Pod" "FAIL"
  fi

  PROMTAIL_DESIRED=$(kubectl get daemonset promtail -n logging -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
  PROMTAIL_READY=$(kubectl get daemonset promtail -n logging -o jsonpath='{.status.numberReady}' 2>/dev/null)
  [ "$PROMTAIL_DESIRED" = "$PROMTAIL_READY" ] && check_status "Promtail DaemonSet 全部就绪 ($PROMTAIL_READY/$PROMTAIL_DESIRED)" "PASS" || check_status "Promtail DaemonSet 未完全就绪 ($PROMTAIL_READY/$PROMTAIL_DESIRED)" "FAIL"
else
  check_status "logging 命名空间不存在" "INFO"
fi

#===============================================================================
# 6. 业务应用层
#===============================================================================
echo -e "\n${CYAN}🔍 [6/9] 业务应用层 (AI-Platform & Other Apps)${NC}"
separator

AI_BAD=$(kubectl get pods -n ai-platform --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
AI_BAD=$(san "$AI_BAD")
AI_TOTAL=$(kubectl get pods -n ai-platform --no-headers 2>/dev/null | wc -l)
AI_TOTAL=$(san "$AI_TOTAL")
[ "$AI_BAD" -eq 0 ] && check_status "AI-Platform (Ollama/Open-WebUI) 所有 Pod 正常 ($AI_TOTAL 个)" "PASS" || check_status "AI-Platform 存在异常 Pod" "FAIL"

HPA_TOTAL=$(kubectl get hpa --all-namespaces --no-headers 2>/dev/null | wc -l)
HPA_TOTAL=$(san "$HPA_TOTAL")
[ "$HPA_TOTAL" -gt 0 ] && check_status "HPA 自动扩缩容已部署 ($HPA_TOTAL 个)" "PASS" || check_status "未部署 HPA" "INFO"

PDB_TOTAL=$(kubectl get pdb --all-namespaces --no-headers 2>/dev/null | wc -l)
PDB_TOTAL=$(san "$PDB_TOTAL")
[ "$PDB_TOTAL" -gt 0 ] && check_status "PDB 优雅终止保护已部署 ($PDB_TOTAL 个)" "PASS" || check_status "未部署 PDB" "INFO"

EXPORTER_POD=$(kubectl get pods -n ai-platform -l app=ollama-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$EXPORTER_POD" ] && check_status "Ollama Exporter 运行正常" "PASS" || check_status "未部署 Ollama Exporter" "INFO"

NGINX_BAD=$(kubectl get pods -n nginx-demo --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
NGINX_BAD=$(san "$NGINX_BAD")
[ "$NGINX_BAD" -eq 0 ] && check_status "Nginx-Demo 测试应用运行正常" "PASS" || check_status "Nginx-Demo 存在异常 Pod" "WARN"

#===============================================================================
# 7. 网络与路由层
#===============================================================================
echo -e "\n${CYAN}🔍 [7/9] 网络与路由层 (Traefik Ingress)${NC}"
separator

TRAEFIK_RUNNING=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers 2>/dev/null | grep "Running" | wc -l)
TRAEFIK_TOTAL=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers 2>/dev/null | wc -l)
[ "$TRAEFIK_TOTAL" -gt 0 ] && [ "$TRAEFIK_RUNNING" = "$TRAEFIK_TOTAL" ] && check_status "Traefik Ingress Controller 运行正常 ($TRAEFIK_TOTAL 个)" "PASS" || check_status "Traefik Ingress Controller 异常" "FAIL"

INGRESS_COUNT=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l)
INGRESS_NO_ADDR=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | awk '{if($5=="<none>" || $5=="") print}' | wc -l)
[ "$INGRESS_NO_ADDR" -eq 0 ] && check_status "所有 Ingress 均已成功分配地址 ($INGRESS_COUNT 个)" "PASS" || check_status "存在未分配地址的 Ingress ($INGRESS_NO_ADDR 个)" "WARN"

#===============================================================================
# 8. 集群事件与安全审计
#===============================================================================
echo -e "\n${CYAN}🔍 [8/9] 集群事件与安全审计 (Events & Security)${NC}"
separator

WARNING_COUNT=$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers 2>/dev/null | wc -l)
WARNING_COUNT=$(san "$WARNING_COUNT")
[ "$WARNING_COUNT" -eq 0 ] && check_status "集群无 Warning 级别事件" "PASS" || [ "$WARNING_COUNT" -le 10 ] && check_status "集群存在少量 Warning 事件 ($WARNING_COUNT 个)" "WARN" || check_status "集群存在大量 Warning 事件 ($WARNING_COUNT 个), 需排查" "WARN"

PENDING_PODS=$(kubectl get pods --all-namespaces --field-selector status.phase=Pending --no-headers 2>/dev/null | wc -l)
PENDING_PODS=$(san "$PENDING_PODS")
[ "$PENDING_PODS" -eq 0 ] && check_status "无 Pending 状态的 Pod" "PASS" || check_status "存在 Pending 状态的 Pod ($PENDING_PODS 个)" "FAIL"

IMAGE_FAIL=$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers 2>/dev/null | grep -ci "FailedToPull\|ErrImagePull\|ImagePullBackOff" 2>/dev/null || echo 0)
IMAGE_FAIL=$(san "$IMAGE_FAIL")
[ "$IMAGE_FAIL" -eq 0 ] && check_status "无镜像拉取失败事件" "PASS" || check_status "存在镜像拉取失败事件 ($IMAGE_FAIL 次)" "FAIL"

#===============================================================================
# 9. 项目结构与文档
#===============================================================================
echo -e "\n${CYAN}🔍 [9/9] 项目结构与文档 (Project Structure)${NC}"
separator

PROJECT_ROOT="/root/sre-lab/k3s-ai-platform"
[ -d "$PROJECT_ROOT" ] && check_status "K3S-AI-PLATFORM 项目目录存在" "PASS" || check_status "未找到 K3S-AI-PLATFORM 项目" "WARN"
[ -f "$PROJECT_ROOT/README.md" ] && check_status "项目 README.md 存在" "PASS" || check_status "缺少 README.md" "WARN"
[ -f "$PROJECT_ROOT/docs/architecture-design.md" ] && check_status "架构设计文档存在" "PASS" || check_status "缺少架构设计文档" "WARN"
[ -d "$PROJECT_ROOT/environments" ] && check_status "环境配置目录存在" "PASS" || check_status "缺少环境配置目录" "WARN"

#===============================================================================
# 最终报告
#===============================================================================
separator
echo -e "\n${BLUE}📊 K3S AI Platform 健康度综合评估报告 (Executive Summary)${NC}"
separator

if [ $TOTAL_CHECKS -gt 0 ]; then
  SCORE=$(( (PASS_CHECKS * 100) / TOTAL_CHECKS ))
else
  SCORE=0
fi

[ $SCORE -ge 90 ] && GRADE="A (卓越)" || [ $SCORE -ge 75 ] && GRADE="B (良好)" || [ $SCORE -ge 60 ] && GRADE="C (及格)" || GRADE="D (需干预)"

echo -e "  总检查项: ${TOTAL_CHECKS}"
echo -e "  ${GREEN}✅ 通过: ${PASS_CHECKS}${NC}  |  ${YELLOW}⚠️ 警告: ${WARN_CHECKS}${NC}  |  ${RED}❌ 失败: ${FAIL_CHECKS}${NC}  |  ${BLUE}ℹ️  信息: ${INFO_COUNT}${NC}"
echo -e ""
echo -e "  🏆 综合健康评分: ${SCORE} 分 (评级: ${GRADE})${NC}"
separator

[ ${#FAIL_ITEMS[@]} -gt 0 ] && echo -e "\n${RED}🚨 关键失败项 (需立即修复):${NC}" && for item in "${FAIL_ITEMS[@]}"; do echo -e "  ${RED}❌${NC} $item"; done
[ ${#WARN_ITEMS[@]} -gt 0 ] && echo -e "\n${YELLOW}⚠️ 警告项 (建议关注):${NC}" && for item in "${WARN_ITEMS[@]}"; do echo -e "  ${YELLOW}⚠️${NC} $item"; done
[ ${#INFO_ITEMS[@]} -gt 0 ] && echo -e "\n${BLUE}ℹ️  信息项:${NC}" && for item in "${INFO_ITEMS[@]}"; do echo -e "  ${BLUE}ℹ️${NC} $item"; done

echo -e "\n${CYAN}💡 架构师建议:${NC}"
if [ $FAIL_CHECKS -eq 0 ] && [ $WARN_CHECKS -eq 0 ]; then
  echo -e "  🎉 集群核心架构运行完美！您可以放心进行下一步的压测或业务部署。"
elif [ $FAIL_CHECKS -eq 0 ]; then
  echo -e "  👀 集群运行正常, 但存在若干告警项。"
else
  echo -e "  🔧 集群存在关键组件异常, 请优先解决 FAIL 项。"
fi
separator
echo ""
