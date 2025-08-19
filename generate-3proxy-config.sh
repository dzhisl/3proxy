#!/bin/bash

# Script to generate 3proxy config with auto-detected IPs
CONFIG_FILE="/etc/3proxy/3proxy.cfg"
TEMP_CONFIG="/tmp/3proxy_temp.cfg"
PROXY_LIST_FILE="/proxy.txt"   # <— NEW

# Get all non-loopback IPv4 addresses
IPS=($(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1))

echo "Detected IPs: ${IPS[@]}"

# Start a fresh proxy list file
: > "$PROXY_LIST_FILE"         # <— NEW (truncate/create)

# Generate the base config
cat > "$TEMP_CONFIG" << 'EOF'
# Specify valid name servers
nserver 8.8.8.8
nserver 8.8.4.4
nserver 1.1.1.1
nserver 1.0.0.1

# DNS cache and timeouts
nscache 65536
timeouts 1 5 30 60 180 1800 15 60

# User authentication
users $/etc/3proxy/.proxyauth

# Daemon mode and logging
daemon
log /var/log/3proxy/3proxy.log
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
archiver gz /usr/bin/gzip %F
rotate 1
authcache user 60

EOF

# Generate proxy services for each IP
HTTP_PORT=9999
SOCKS_PORT=8088

for i in "${!IPS[@]}"; do
    IP="${IPS[$i]}"
    
    cat >> "$TEMP_CONFIG" << EOF
# Proxy services for IP: $IP
flush
auth strong cache
deny * * 127.0.0.0/8,192.168.1.1
allow * * * 80-88,8080-8088 HTTP
allow * * * 443,8443 HTTPS
proxy -n -p$HTTP_PORT -i$IP -e$IP -a

flush
auth strong cache
socks -p$SOCKS_PORT -i$IP -e$IP

EOF
    # Record both HTTP and SOCKS endpoints as ip:port lines  <— NEW
    echo "${IP}:${HTTP_PORT}" >> "$PROXY_LIST_FILE"
    echo "Generated proxy for $IP - HTTP:$HTTP_PORT, SOCKS:$SOCKS_PORT"
    HTTP_PORT=$((HTTP_PORT + 1))
    SOCKS_PORT=$((SOCKS_PORT + 1))
done

# Add admin interface
cat >> "$TEMP_CONFIG" << 'EOF'
# Admin interface
flush
auth iponly strong cache
allow * * 127.0.0.0/8
allow admin * 10.0.0.0/8
admin -p2525
EOF

# Move temp config to final location
mv "$TEMP_CONFIG" "$CONFIG_FILE"

# Make the proxy list readable
chmod 644 "$PROXY_LIST_FILE"     # <— optional nicety

echo "\nGenerated config file: $CONFIG_FILE"
echo "Saved proxy list to: $PROXY_LIST_FILE"
echo "\n\nAvailable proxy endpoints:"
HTTP_PORT=9999
SOCKS_PORT=8088
for IP in "${IPS[@]}"; do
    echo "  IP $IP: HTTP proxy on port $HTTP_PORT, SOCKS proxy on port $SOCKS_PORT"
    HTTP_PORT=$((HTTP_PORT + 1))
    SOCKS_PORT=$((SOCKS_PORT + 1))
done