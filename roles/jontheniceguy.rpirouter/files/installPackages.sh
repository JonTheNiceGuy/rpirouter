#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
until apt update
do
  sleep 1
done
until apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $(cat /root/packages 2>/dev/null)
do
  sleep 1
done
rm -f /root/packages