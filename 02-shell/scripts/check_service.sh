#!/bin/bash

service=$1

systemctl is-active --quiet $service

if [ $? -eq 0 ]; then
  echo "$service is running"
else
  echo "$service is down"
fi

