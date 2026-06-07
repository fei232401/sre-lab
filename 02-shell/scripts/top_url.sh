#!/bin/bash

log=$1

if [-z "$log" ];then
  echo "Usage: bash top_url.sh <logfile>"
  exit 1
fi

awk '{print $3}' "$log" | sort |uniq -c | sort -nr

