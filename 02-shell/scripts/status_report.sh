#!/bin/bash

log=$1

if [ -z "$log" ]; then
  echo "Usage: bash status_report.sh <logfile>"
  exit 1
fi


echo "=== STATUS CODE==="

awk '{print $4}' "$log" | sort | uniq -c

