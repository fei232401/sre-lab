#!/bin/bash

logfile="$2"

show_banner(){

  echo "====================="
  echo "  SRE HEALTH CHECK"
  echo "====================="
}

check_service(){

  status=$(systemctl is-active "$1")

  if [ "$status" = "active" ]; then
    echo "$1 OK"
  else
    echo "$1 FAILED"
  fi
}

service_report(){

  echo
  echo "===== SERVICE REPORT ====="

  for service in nginx ssh docker
  do
    check_service "$service"
  done

}

log_report(){
  if [ -z "$logfile" ]; then
    echo "Log file not specified"
    exit 1
  fi

  echo
  echo "==== ERROR COUNT ===="
  grep -c "500" "$logfile"

  echo
  echo "==== TOP IP ===="
  awk '{print $1}' "$logfile" | sort | uniq -c | sort -nr

  echo
  echo "==== TOP URL ===="
  awk '{print $3}' "$logfile" | sort | uniq -c | sort -nr

  echo
  echo "==== STATUS CODE ===="
  awk '{print $4}' "$logfile" | sort | uniq -c | sort -nr

}

usage(){
  echo "Usage:"
  echo "./ sre_health_check.sh service"
  echo "./ sre_health_check.sh log <logfile>"
  echo "./ sre_health_check.sh full <logfile>"

}

show_banner

case "$1" in

service)
  service_report
  ;;

log)
  log_report
  ;;

full)
  service_report
  log_report
  ;;

*)
  usage
  ;;

esac
