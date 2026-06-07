#!/bin/bash

logfile=$1

echo "Checking error in $logfile"

errors=$(grep -c 500 $logfile)

echo "Total 500 errors: $errors"

