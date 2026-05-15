#!/bin/bash

NAME="sna-web-server"
SERVICE_FILE="/etc/systemd/system/$NAME.service"
LOG_DIR="/var/log/sna-server"
INSTALL_DIR="/opt/sna_web_server"

echo "Removing $NAME..."

sudo systemctl stop "$NAME" 2>/dev/null
sudo systemctl disable "$NAME" 2>/dev/null

if [ -f "$SERVICE_FILE" ]; then
    sudo rm "$SERVICE_FILE"
    echo "Removed service file: $SERVICE_FILE"
fi

sudo systemctl daemon-reload

if [ -d "$LOG_DIR" ]; then
    sudo rm -rf "$LOG_DIR"
    echo "Removed logs: $LOG_DIR"
fi

if [ -d "$INSTALL_DIR" ]; then
    sudo rm -rf "$INSTALL_DIR"
    echo "Removed installation directory: $INSTALL_DIR"
fi

sudo userdel sna-server 2>/dev/null
sudo groupdel sna-server 2>/dev/null

echo "Cleanup complete."
