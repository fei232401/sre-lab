#!/bin/bash

check_service() {
  systemctl is-active nginx
}

check_service
