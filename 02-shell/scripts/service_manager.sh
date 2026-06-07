#!/bin/bash
case "$1" in

start)
  echo "Starting service"
  ;;

stop)
  echo "Stoping service"
  ;;

status)
  echo "Checking service"
  ;;

*)
  echo "Usage:start|stop|status"
  ;;

esac
