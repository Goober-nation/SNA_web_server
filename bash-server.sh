#!/bin/bash

# Lightweight HTTP Bash Server
# Team 41, SNA project
# This script intentionally uses only Bash + standard Linux utilities + netcat.

PORT="${PORT:-8080}"
LOG_DIR="${LOG_DIR:-/var/log}"
SERVER_START_TIME=$(date +%s)
SERVER_PID=$$

PIPE=$(mktemp -u)
STATE_DIR=$(mktemp -d)
REQUEST_COUNT_FILE="$STATE_DIR/request_count"
DOWNLOAD_COUNT_FILE="$STATE_DIR/download_count"
LAST_REQUEST_FILE="$STATE_DIR/last_request"

mkfifo "$PIPE"

cleanup() {
    rm -f "$PIPE"
    rm -rf "$STATE_DIR"
    exit
}
trap cleanup INT TERM EXIT

mkdir -p "$LOG_DIR" 2>/dev/null || {
    echo "Cannot create or access log directory: $LOG_DIR" >&2
    exit 1
}

printf "0" > "$REQUEST_COUNT_FILE"
printf "0" > "$DOWNLOAD_COUNT_FILE"
printf "No requests yet" > "$LAST_REQUEST_FILE"

send_response() {
    local status="$1"
    local body="$2"
    local length

    length=$(printf "%s" "$body" | wc -c)
    printf "HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" \
        "$status" "$length" "$body"
}

read_counter() {
    local file="$1"
    local value

    value=$(cat "$file" 2>/dev/null)
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf "%s" "$value"
    else
        printf "0"
    fi
}

increment_counter() {
    local file="$1"
    local value

    value=$(read_counter "$file")
    printf "%d" $((value + 1)) > "$file"
}

format_server_uptime() {
    local now
    local seconds
    local days
    local hours
    local minutes

    now=$(date +%s)
    seconds=$((now - SERVER_START_TIME))
    days=$((seconds / 86400))
    seconds=$((seconds % 86400))
    hours=$((seconds / 3600))
    seconds=$((seconds % 3600))
    minutes=$((seconds / 60))
    seconds=$((seconds % 60))

    printf "%dd %02dh %02dm %02ds" "$days" "$hours" "$minutes" "$seconds"
}

get_os_info() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf "%s" "${PRETTY_NAME:-Unknown Linux distribution}"
    else
        uname -s
    fi
}

get_cpu_info() {
    local cpu

    cpu=$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
    if [ -n "$cpu" ] && [ "$cpu" != "unknown" ]; then
        printf "%s" "$cpu"
    else
        uname -m
    fi
}

get_memory_usage() {
    ps -o pid,ppid,%mem,%cpu,rss,comm -p "$SERVER_PID" 2>/dev/null || \
        printf "Memory information is not available for PID %s" "$SERVER_PID"
}

build_download_list_body() {
    local files

    if [ ! -d "$LOG_DIR" ]; then
        printf "Log directory does not exist: %s" "$LOG_DIR"
        return
    fi

    if [ ! -r "$LOG_DIR" ]; then
        printf "Log directory is not readable: %s" "$LOG_DIR"
        return
    fi

    files=$(find "$LOG_DIR" -maxdepth 1 -type f -printf "%f\n" 2>/dev/null | sort)

    if [ -z "$files" ]; then
        printf "No regular log files found in %s." "$LOG_DIR"
    else
        printf "Available log files in %s:\n%s" "$LOG_DIR" "$files"
    fi
}

while true; do
    nc -l -p "$PORT" < "$PIPE" | {
        read -r request_line
        request_line=$(echo "$request_line" | tr -d '\r')
        method=$(echo "$request_line" | awk '{print $1}')
        route=$(echo "$request_line" | awk '{print $2}')

        while read -r header; do
            header=$(echo "$header" | tr -d '\r')
            [ -z "$header" ] && break
        done

        request_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        increment_counter "$REQUEST_COUNT_FILE"
        printf "%s %s %s" "$request_timestamp" "$method" "$route" > "$LAST_REQUEST_FILE"

        if [ "$method" = "GET" ] && [ "$route" = "/health" ]; then
            body="UPTIME:
$(uptime)

FREE:
$(free -h)

DF:
$(df -h)"
            send_response "200 OK" "$body"

        elif [ "$method" = "GET" ] && [[ "$route" == /logs?name=* ]]; then
            log_name="${route#*name=}"

            if [ -z "$log_name" ]; then
                body="400 Bad Request: Log name is empty. Use /logs?name=<file>."
                send_response "400 Bad Request" "$body"
            elif [[ "$log_name" =~ (/|\.\.|%2F|%2f|%2E|%2e) ]]; then
                body="403 Forbidden: Security violation detected."
                send_response "403 Forbidden" "$body"
            else
                target_file="$LOG_DIR/$log_name"

                if [ -f "$target_file" ]; then
                    body=$(head -n 20 "$target_file")
                    increment_counter "$DOWNLOAD_COUNT_FILE"
                    send_response "200 OK" "$body"
                else
                    body="404 Not Found: Requested log does not exist."
                    send_response "404 Not Found" "$body"
                fi
            fi

        elif [ "$method" = "GET" ] && [ "$route" = "/metrics" ]; then
            body="SERVER METRICS:
Request counter: $(read_counter "$REQUEST_COUNT_FILE")
Downloaded files: $(read_counter "$DOWNLOAD_COUNT_FILE")
Server uptime: $(format_server_uptime)
Last request: $(cat "$LAST_REQUEST_FILE" 2>/dev/null)

Bash process memory usage:
$(get_memory_usage)"
            send_response "200 OK" "$body"

        elif [ "$method" = "GET" ] && [ "$route" = "/info" ]; then
            body="SYSTEM INFO:
Hostname: $(hostname)
Kernel: $(uname -r)
OS: $(get_os_info)
CPU: $(get_cpu_info)
Current user: $(whoami)"
            send_response "200 OK" "$body"

        elif [ "$method" = "GET" ] && [ "$route" = "/download-list" ]; then
            body=$(build_download_list_body)
            send_response "200 OK" "$body"

        else
            body="404 Not Found: Unknown endpoint."
            send_response "404 Not Found" "$body"
        fi
    } > "$PIPE"
done
