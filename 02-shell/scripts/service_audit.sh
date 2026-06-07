#!/bin/bash

check_service(){
  status=$(systemctl is-active "$1")


  if [ "$status" = "active" ];then
    echo "$1 OK"
  else
    echo "$1 FAILED"
  fi
}

for service in nginx ssh docker
do
  check_service "$service"
done
