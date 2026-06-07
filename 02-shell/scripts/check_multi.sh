#!/bin/bash

for service in "$@"
do
  systemctl is-active --quiet $service
  if [ $? -eq 0 ];then
    echo "service ok"
  else
    echo "service fail"
  fi
done
