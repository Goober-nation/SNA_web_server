#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
NAME="sna-web-server"
SERVICE_FILE="/etc/systemd/system/$NAME.service"
INSTALL_DIR="/opt/sna_web_server"
LOG_DIR="/var/log/sna-server"
USER="sna-server"

echo "Installing $NAME..."

if ! id -u "$USER" >/dev/null 2>&1; then
    echo "Creating user $USER..."
    sudo groupadd -r "$USER"
    sudo useradd -r -g "$USER" -d "$INSTALL_DIR" -s /sbin/nologin "$USER"
fi

echo "Preparing installation directory $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
sudo cp "$DIR/bash-server.sh" "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/bash-server.sh"
sudo chown -R "$USER:$USER" "$INSTALL_DIR"

echo "Preparing log directory $LOG_DIR..."
sudo mkdir -p "$LOG_DIR"
sudo chown -R "$USER:$USER" "$LOG_DIR"
sudo chmod 750 "$LOG_DIR"

echo "Installing systemd service..."
sudo cp "$DIR/$NAME.service" "$SERVICE_FILE"

sudo systemctl daemon-reload
sudo systemctl enable --now "$NAME"

sudo systemctl status "$NAME" --no-pager
