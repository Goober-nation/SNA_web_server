#!/bin/bash

# Lightweight HTTP Bash Server
# Team 41, SNA project
# This script intentionally uses only Bash + standard Linux utilities + netcat.

PORT="${PORT:-8080}"
LOG_DIR="${LOG_DIR:-/var/log/sna-server}"
SYSTEM_LOG_DIR="${SYSTEM_LOG_DIR:-/var/log}"
ACCESS_LOG="${ACCESS_LOG:-$LOG_DIR/access.log}"
AUTH_USER="${AUTH_USER:-}"
AUTH_PASS="${AUTH_PASS:-}"
SERVER_START_TIME=$(date +%s)
SERVER_PID=$$

PIPE=$(mktemp -u)
STATE_DIR=$(mktemp -d)
REQUEST_COUNT_FILE="$STATE_DIR/request_count"
DOWNLOAD_COUNT_FILE="$STATE_DIR/download_count"
LAST_REQUEST_FILE="$STATE_DIR/last_request"
RESOURCE_HISTORY_FILE="$STATE_DIR/resource_history.log"

mkfifo "$PIPE"

cleanup() {
    [ -n "$COLLECTOR_PID" ] && kill "$COLLECTOR_PID" 2>/dev/null
    rm -f "$PIPE"
    rm -rf "$STATE_DIR"
    exit
}
trap cleanup INT TERM EXIT

collect_resources() {
    while true; do
        local timestamp=$(date +%s)
        local cpu_load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
        local ram_usage=$(free 2>/dev/null | awk '/Mem:/ { printf("%.2f", $3/$2*100) }')
        printf "%s %s %s\n" "$timestamp" "${cpu_load:-0}" "${ram_usage:-0}" >> "$RESOURCE_HISTORY_FILE"
        sleep 60
    done
}

send_response() {

    local status="$1"
    local body="$2"
    local content_type="${3:-application/json}"
    local length

    length=$(printf "%s" "$body" | wc -c)
    printf "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" \
        "$status" "$content_type" "$length" "$body"
}

send_auth_challenge() {
    local body='{"error":"Unauthorized"}'
    local length=${#body}
    printf "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"SNA Server\"\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" \
        "$length" "$body"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
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

log_access() {
    local timestamp="$1"
    local method="$2"
    local route="$3"
    local status="$4"
    printf "[%s] %s %s %s\n" "$timestamp" "$method" "$route" "$status" >> "$ACCESS_LOG"
}

collect_resources &
COLLECTOR_PID=$!

while true; do
    nc -l -p "$PORT" < "$PIPE" | {
        read -r request_line
        request_line=$(echo "$request_line" | tr -d '\r')
        method=$(echo "$request_line" | awk '{print $1}')
        route=$(echo "$request_line" | awk '{print $2}')

        provided_credentials=""
        while read -r header; do
            header=$(echo "$header" | tr -d '\r')
            [ -z "$header" ] && break
            if [[ "$header" == "Authorization: Basic "* ]]; then
                provided_credentials="${header#Authorization: Basic }"
            fi
        done

        request_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        increment_counter "$REQUEST_COUNT_FILE"
        printf "%s %s %s" "$request_timestamp" "$method" "$route" > "$LAST_REQUEST_FILE"

        if [ -n "$AUTH_USER" ] && [ -n "$AUTH_PASS" ]; then
            expected_credentials=$(printf "%s:%s" "$AUTH_USER" "$AUTH_PASS" | base64 | tr -d '\n')
            if [ "$provided_credentials" != "$expected_credentials" ]; then
                log_access "$request_timestamp" "$method" "$route" "401 Unauthorized"
                send_auth_challenge
                exit
            fi
        fi

        response_status="404 Not Found"
        body='{"error":"Not Found","message":"Unknown endpoint."}'

        if [ "$method" = "GET" ] && [ "$route" = "/health" ]; then
            uptime_val=$(json_escape "$(uptime)")
            free_val=$(json_escape "$(free -h)")
            df_val=$(json_escape "$(df -h)")
            body="{\"uptime\":\"$uptime_val\",\"free\":\"$free_val\",\"df\":\"$df_val\"}"
            response_status="200 OK"

        elif [ "$method" = "GET" ] && [[ "$route" == /logs?name=* ]]; then
            log_name="${route#*name=}"

            if [ -z "$log_name" ]; then
                body='{"error":"Bad Request","message":"Log name is empty. Use /logs?name=<file>."}'
                response_status="400 Bad Request"
            elif [[ "$log_name" =~ (/|\.\.|%2F|%2f|%2E|%2e) ]]; then
                body='{"error":"Forbidden","message":"Security violation detected."}'
                response_status="403 Forbidden"
            else
                target_file="$SYSTEM_LOG_DIR/$log_name"

                if [ -f "$target_file" ]; then
                    content=$(json_escape "$(head -n 20 "$target_file")")
                    body="{\"file\":\"$log_name\",\"content\":\"$content\"}"
                    increment_counter "$DOWNLOAD_COUNT_FILE"
                    response_status="200 OK"
                else
                    body='{"error":"Not Found","message":"Requested log does not exist."}'
                    response_status="404 Not Found"
                fi
            fi

        elif [ "$method" = "GET" ] && [ "$route" = "/metrics" ]; then
            req_count=$(read_counter "$REQUEST_COUNT_FILE")
            dl_count=$(read_counter "$DOWNLOAD_COUNT_FILE")
            srv_uptime=$(json_escape "$(format_server_uptime)")
            last_req=$(json_escape "$(cat "$LAST_REQUEST_FILE" 2>/dev/null)")
            mem=$(json_escape "$(get_memory_usage)")
            body="{\"request_count\":$req_count,\"downloaded_files\":$dl_count,\"server_uptime\":\"$srv_uptime\",\"last_request\":\"$last_req\",\"memory_usage\":\"$mem\"}"
            response_status="200 OK"

        elif [ "$method" = "GET" ] && [ "$route" = "/info" ]; then
            hostname_val=$(json_escape "$(hostname)")
            kernel_val=$(json_escape "$(uname -r)")
            os_val=$(json_escape "$(get_os_info)")
            cpu_val=$(json_escape "$(get_cpu_info)")
            user_val=$(json_escape "$(whoami)")
            body="{\"hostname\":\"$hostname_val\",\"kernel\":\"$kernel_val\",\"os\":\"$os_val\",\"cpu\":\"$cpu_val\",\"user\":\"$user_val\"}"
            response_status="200 OK"

        elif [ "$method" = "GET" ] && [ "$route" = "/download-list" ]; then
            if [ ! -d "$SYSTEM_LOG_DIR" ] || [ ! -r "$SYSTEM_LOG_DIR" ]; then
                log_dir_escaped=$(json_escape "$SYSTEM_LOG_DIR")
                body="{\"error\":\"Log directory not accessible.\",\"log_dir\":\"$log_dir_escaped\"}"
                response_status="500 Internal Server Error"
            else
                files=$(find "$SYSTEM_LOG_DIR" -maxdepth 1 -type f -printf "%f\n" 2>/dev/null | sort)
                log_dir_escaped=$(json_escape "$SYSTEM_LOG_DIR")
                if [ -z "$files" ]; then
                    files_json="[]"
                else
                    files_json=$(printf '%s' "$files" | awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}')
                fi
                body="{\"log_dir\":\"$log_dir_escaped\",\"files\":$files_json}"
                response_status="200 OK"
            fi

        elif [ "$method" = "GET" ] && [[ "$route" == "/access-log"* ]]; then
            n=50
            if [[ "$route" == *"?n="* ]]; then
                n="${route#*?n=}"
                [[ "$n" =~ ^[0-9]+$ ]] || n=50
            fi

            if [ -f "$ACCESS_LOG" ]; then
                entries=$(tail -n "$n" "$ACCESS_LOG")
                if [ -z "$entries" ]; then
                    entries_json="[]"
                else
                    entries_json=$(printf '%s' "$entries" | awk 'BEGIN{printf "["} NR>1{printf ","} {gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "\"%s\"", $0} END{printf "]"}')
                fi
                body="{\"requested\":$n,\"entries\":$entries_json}"
            else
                body='{"error":"Access log not found."}'
            fi
            response_status="200 OK"

        elif [ "$method" = "GET" ] && [ "$route" = "/status" ]; then
            uptime_val=$(json_escape "$(uptime)")
            free_val=$(json_escape "$(free -h)")
            df_val=$(json_escape "$(df -h)")
            req_count=$(read_counter "$REQUEST_COUNT_FILE")
            dl_count=$(read_counter "$DOWNLOAD_COUNT_FILE")
            srv_uptime=$(json_escape "$(format_server_uptime)")
            last_req=$(json_escape "$(cat "$LAST_REQUEST_FILE" 2>/dev/null)")
            mem=$(json_escape "$(get_memory_usage)")
            hostname_val=$(json_escape "$(hostname)")
            kernel_val=$(json_escape "$(uname -r)")
            os_val=$(json_escape "$(get_os_info)")
            cpu_val=$(json_escape "$(get_cpu_info)")
            user_val=$(json_escape "$(whoami)")
            ts=$(json_escape "$request_timestamp")
            body="{\"timestamp\":\"$ts\",\"health\":{\"uptime\":\"$uptime_val\",\"free\":\"$free_val\",\"df\":\"$df_val\"},\"metrics\":{\"request_count\":$req_count,\"downloaded_files\":$dl_count,\"server_uptime\":\"$srv_uptime\",\"last_request\":\"$last_req\",\"memory_usage\":\"$mem\"},\"info\":{\"hostname\":\"$hostname_val\",\"kernel\":\"$kernel_val\",\"os\":\"$os_val\",\"cpu\":\"$cpu_val\",\"user\":\"$user_val\"}}"
            response_status="200 OK"

        elif [ "$method" = "GET" ] && [ "$route" = "/stats" ]; then
            now=$(date +%s)
            hour_ago=$((now - 3600))
            stats=$(awk -v start="$hour_ago" '$1 >= start { 
                cpu_sum+=$2; cpu_max=($2>cpu_max?$2:cpu_max); 
                ram_sum+=$3; ram_max=($3>ram_max?$3:ram_max); 
                count++ 
            } END { 
                if (count > 0) 
                    printf "%.2f %.2f %.2f %.2f", cpu_sum/count, cpu_max, ram_sum/count, ram_max; 
                else 
                    printf "0 0 0 0" 
            }' "$RESOURCE_HISTORY_FILE" 2>/dev/null)
            
            read -r c_avg c_max r_avg r_max <<< "$stats"
            body="{\"cpu_avg\":${c_avg:-0},\"cpu_max\":${c_max:-0},\"ram_avg\":${r_avg:-0},\"ram_max\":${r_max:-0}}"
            response_status="200 OK"

        elif [ "$method" = "GET" ] && [ "$route" = "/top" ]; then
            cpu_load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
            ram_usage=$(free 2>/dev/null | awk '/Mem:/ { printf("%.2f", $3/$2*100) }')
            proc_json=$(ps -eo pid,comm,%cpu,%mem --sort=-%cpu | awk 'NR>1 && NR<=6 {
                printf "{\"pid\":%s,\"comm\":\"%s\",\"cpu\":%s,\"mem\":%s}", $1, $2, $3, $4
            }' | awk 'BEGIN {printf "["} {if (NR>1) printf ","; printf "%s", $0} END {printf "]"}')
            body="{\"cpu_load\":${cpu_load:-0},\"ram_usage\":${ram_usage:-0},\"top_processes\":$proc_json}"
            response_status="200 OK"
        fi

        log_access "$request_timestamp" "$method" "$route" "$response_status"
        send_response "$response_status" "$body"
    } > "$PIPE"
done
