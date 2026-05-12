# Lightweight HTTP Bash Server with systemd-Based Service Management

## B26 System and Network Administration

The server consists of NetCat, Linux integration, and a systemctl server. 
It is designed to be a sort of simple Network Node designed to be interacted with via HTTP. Designed by team 41.
The server consists of 5 API endpoints:

```
/health
/logs 
/metrics
/download-list
/access-log
```

run
```
sudo ./bash-server.sh
```

to clear all previous runs and re-run
```
sudo fuser -k 8080/tcp 2>/dev/null; sudo pkill -f bash-server.sh; sudo ./bash-server.sh
```


/logs API endpoint usage
```
curl -i "http://localhost:8080/logs?name=syslog"
```

Expected output
```
HTTP/1.1 200 OK
Content-Type: text/plain
Content-Length: 3623
Connection: close

*lines of logs here, by default limit is first 20 lines for output*
```
