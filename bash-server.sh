#!/bin/bash

PORT=8080
LOG_DIR="/var/log"
PIPE=$(mktemp -u)
mkfifo "$PIPE"
trap 'rm -f "$PIPE"; exit' INT TERM EXIT

mkdir -p "$LOG_DIR"

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

        if [ "$method" = "GET" ] && [ "$route" = "/health" ]; then
            body="UPTIME:
$(uptime)

FREE:
$(free -h)

DF:
$(df -h)"
            length=$(printf "%s" "$body" | wc -c)
            printf "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" "$length" "$body"
        
        elif [ "$method" = "GET" ] && [[ "$route" == /logs?name=* ]]; then
            log_name="${route#*name=}"
            
            if [[ "$log_name" =~ (/|\.\.|%2F|%2f|%2E|%2e) ]]; then
                body="403 Forbidden: Security violation detected."
                length=$(printf "%s\n" "$body" | wc -c)
                printf "HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s\n" "$length" "$body"
            else
                target_file="$LOG_DIR/$log_name"
                
                if [ -f "$target_file" ]; then
                    TMP_LOG=$(mktemp)
                    head -n 20 "$target_file" > "$TMP_LOG"
                    length=$(stat -c%s "$TMP_LOG")
                    printf "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" "$length"
                    cat "$TMP_LOG"
                    rm -f "$TMP_LOG"
                else
                    body="404 Not Found: Requested log does not exist."
                    length=$(printf "%s\n" "$body" | wc -c)
                    printf "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s\n" "$length" "$body"
                fi
            fi

        else
            printf "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        fi
    } > "$PIPE"
done
