#!/bin/bash

log=$1


if [ -z "$log" ];then
  echo "Usage: bash log_report.sh <logfile>"
  exit 1
fi

echo "=== ERROR COUNT ==="
grep -c "500" $log

echo "=== TOP IP ==="
awk '{print $1}' $log | sort | uniq -c | sort -nr

