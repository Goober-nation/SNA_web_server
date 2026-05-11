#!/bin/bash

PORT=8080
PIPE=$(mktemp -u)
mkfifo "$PIPE"
trap 'rm -f "$PIPE"; exit' INT TERM EXIT

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
            length=$(echo -n "$body" | wc -c)
            echo -ne "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: $length\r\nConnection: close\r\n\r\n$body"
        else
            echo -ne "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        fi
    } > "$PIPE"
done
