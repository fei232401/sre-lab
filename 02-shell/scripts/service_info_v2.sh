#!/bin/bash

show_service(){
  echo "Checking $1"

  systemctl is-active "$1"
}
show_service ssh
show_service nginx
