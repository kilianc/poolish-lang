#!/bin/sh

set -e

binary_name="poolish"

sudo systemctl disable ${binary_name}.timer || true
sudo systemctl stop ${binary_name}.timer || true
sudo systemctl daemon-reload || true

sudo rm -rf /usr/local/etc/${binary_name}/ || true

sudo rm /usr/local/bin/${binary_name}  || true
sudo rm /etc/systemd/system/${binary_name}.service || true
sudo rm /etc/systemd/system/${binary_name}.timer || true
