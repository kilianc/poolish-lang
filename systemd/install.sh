#!/bin/sh

set -e

binary_name="poolish"

sudo mkdir -p /usr/local/etc/${binary_name}

sudo mv /home/ubuntu/${binary_name}/${binary_name}-linux-amd64 /usr/local/bin/${binary_name}
sudo mv /home/ubuntu/${binary_name}/${binary_name}.env         /usr/local/etc/${binary_name}/
sudo mv /home/ubuntu/${binary_name}/${binary_name}.service     /etc/systemd/system/
sudo mv /home/ubuntu/${binary_name}/${binary_name}.timer       /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable ${binary_name}.timer
sudo systemctl restart ${binary_name}.timer

sudo rm -rf /home/ubuntu/${binary_name}
