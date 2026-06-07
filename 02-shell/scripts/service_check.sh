#!/bin/bash

service="ssh"

systemctl is-active --quiet $service

if [ $? -eq 0 ]; then
  echo "$service is running"
else
  echo "$service is DOWN"
fi
