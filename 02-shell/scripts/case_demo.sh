#!/bin/bash

case "$1" in

start)
  echo "Starting..."
  ;;

stop)
  echo "Stopping..."
  ;;

status)
  echo "Checking..."
  ;;

*)
  echo "Unknown command"
  ;;

esac
