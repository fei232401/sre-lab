#!/bin/bash

logfile="$1"

#函数：检查服务
check_service(){
  local svc=$1
  if [ "$(systemctl is-active $svc)" = "active" ]; then
    echo "$svc OK"
  else
    echo "$svc FAILED"
  fi
}

#函数：日志分析
log_report(){
  local log=$1
  echo "=== ERROR COUNT ==="
  grep -c "500" "$log"
  echo "=== TOP IP ==="
  awk '{print $1}' "$log" | sort | uniq -c | sort -nr
  echo "=== TOP URL ==="
  awk '{print $3}' "$log" | sort | uniq -c | sort -nr
  echo "=== STATUS CODE ==="
  awk '{print $4}' "$log" | sort | uniq -c | sort -nr
}

#主流程
echo "---- Service Status ----"
for s in nginx ssh docker; do
  check_service "$s"
done

echo "---- Log Report ----"
if [ -z "$logfile" ]; then
  echo "Usage: $0 <logfile>"
  exit 1
fi
log_report "$logfile"
