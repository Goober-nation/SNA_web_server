# Lightweight HTTP Bash Server with systemd-Based Service Management

## B26 System and Network Administration

The server consists of NetCat, Linux integration, and a systemctl service. 
It is designed to be a sort of simple Network Node designed to be interacted with via HTTP. Designed by team 41.
The server consists of 9 API endpoints. All responses are `application/json`.

```
/health        — system uptime, memory, disk usage
/logs          — read a log file (path traversal protected)
/metrics       — request counters, server uptime, server memory usage (%)
/info          — hostname, kernel, OS, CPU, current user
/download-list — list available files in log directory
/access-log    — last N entries from the access log
/status        — aggregate snapshot of all metrics (health + metrics + info)
/stats         — hourly average and max CPU load (1m avg) and RAM usage (%)
/top           — current CPU load (1m avg), RAM usage (%), and top 5 processes (% CPU/RAM)
```


### Service Installation

To install and run as a systemd service:
```bash
sudo ./install.sh
```

Manage the service:
```bash
sudo systemctl status sna-web-server
sudo systemctl restart sna-web-server
sudo systemctl stop sna-web-server
```

To uninstall the service and clean up the traces:
```bash
sudo ./uninstall.sh
```

### Basic Authentication (optional)

Set `AUTH_USER` and `AUTH_PASS` environment variables to enable Basic Auth on all endpoints:

```bash
sudo AUTH_USER=admin AUTH_PASS=secret ./bash-server.sh
```

```bash
curl -u admin:secret http://localhost:8080/status
```

### Endpoint examples

```bash
# Read a log file (first 20 lines)
curl "http://localhost:8080/logs?name=syslog"

# Last 100 access log entries
curl "http://localhost:8080/access-log?n=100"

# Full status snapshot
curl "http://localhost:8080/status"
```

Expected output format:
```
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: ...
Connection: close

{"uptime":"...","free":"...","df":"..."}
```
