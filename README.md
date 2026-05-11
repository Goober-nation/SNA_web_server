# Lightweight HTTP Bash Server with systemd-Based Service Management

## B26 System and Network Administration

The server consists of NetCat, Linux integration, and a systemctl server. 
It is designed to be a sort of simple Network Node designed to be interacted with via HTTP. 
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
