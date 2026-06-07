#!/bin/bash

log=$1

if [ -z "$log" ]; then
  echo "Usage: bash access_report.sh <logfile>"
  exit 1
fi

echo "==== ERROR COUNT ====="
grep -c "500" "$log"

echo
echo "==== TOP IP ===="
awk '{print $1}' "$log" | sort | uniq -c | sort -nr

echo
echo "==== TOP URL ===="
awk '{print $3}' "$log" | sort | uniq -c | sort -nr

echo
echo "==== STATUS CODE ===="
awk '{print$4}' "$log" | sort | uniq -c | sort -nr
