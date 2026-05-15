#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
NAME="sna-web-server"
SERVICE_FILE="/etc/systemd/system/$NAME.service"

chmod +x "$DIR/bash-server.sh"

sudo cp "$DIR/$NAME.service" "$SERVICE_FILE"

sudo systemctl daemon-reload

sudo systemctl enable --now "$NAME"

sudo systemctl status "$NAME" --no-pager
