#!/bin/bash

# deploy-webservers.sh - Deploy web servers in VPC subnets for demonstration
# Dynamically deploys servers in all existing subnets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

CONFIG_DIR="${SCRIPT_DIR}/config"
VPC_STATE_FILE="${CONFIG_DIR}/vpc.conf"

echo "=== Deploying Web Servers in VPC Subnets ==="
echo ""

# Check if state file exists
if [[ ! -f "$VPC_STATE_FILE" ]]; then
    echo "Error: No VPCs found. Create a VPC and subnets first."
    exit 1
fi

# Check if there are any subnets
if ! grep -q "^SUBNET:" "$VPC_STATE_FILE" 2>/dev/null; then
    echo "Error: No subnets found. Create subnets first."
    exit 1
fi

deployed_count=0

# Read all subnets from state file and deploy servers
while IFS=: read -r prefix vpc_name subnet_name cidr type namespace timestamp; do
    if [[ "$prefix" != "SUBNET" ]]; then
        continue
    fi
    
    # Get IP address (assuming .10 is used)
    subnet_ip=$(echo "$cidr" | sed 's|0/24|10|')
    
    echo "Deploying web server in $namespace ($subnet_ip:8080)..."
    
    # Create unique temp directory for this subnet
    temp_dir="/tmp/webserver-${namespace}"
    
    # Deploy web server
    sudo ip netns exec "$namespace" bash -c "mkdir -p $temp_dir && cat > $temp_dir/index.html << EOF
<!DOCTYPE html>
<html>
<head><title>${namespace} Web Server</title></head>
<body>
<h1>Welcome to ${subnet_name} Subnet</h1>
<p><strong>VPC:</strong> ${vpc_name}</p>
<p><strong>Subnet:</strong> ${subnet_name} (${cidr})</p>
<p><strong>IP:</strong> ${subnet_ip}</p>
<p><strong>Type:</strong> ${type^} Subnet</p>
<p><strong>Namespace:</strong> ${namespace}</p>
</body>
</html>
EOF
"
    
    # Start web server in background
    sudo ip netns exec "$namespace" python3 -m http.server 8080 --directory "$temp_dir" > "/tmp/${namespace}-webserver.log" 2>&1 &
    server_pid=$!
    echo "  Started (PID: $server_pid)"
    
    deployed_count=$((deployed_count + 1))
    
done < "$VPC_STATE_FILE"

if [[ $deployed_count -eq 0 ]]; then
    echo "No subnets found to deploy servers."
    exit 1
fi

echo ""
echo "=== Web Servers Deployed ==="
echo ""
echo "Testing web servers..."
sleep 2

# Test all deployed servers
while IFS=: read -r prefix vpc_name subnet_name cidr type namespace timestamp; do
    if [[ "$prefix" != "SUBNET" ]]; then
        continue
    fi
    
    subnet_ip=$(echo "$cidr" | sed 's|0/24|10|')
    
    test_result=$(sudo ip netns exec "$namespace" curl -s http://127.0.0.1:8080 2>&1 | grep -o '<h1>.*</h1>' || echo 'FAILED')
    echo "  $namespace: $test_result"
    
done < "$VPC_STATE_FILE"

echo ""
echo "✓ All $deployed_count web server(s) are running!"
echo ""
echo "Access URLs (from within namespaces):"

# Show access URLs
while IFS=: read -r prefix vpc_name subnet_name cidr type namespace timestamp; do
    if [[ "$prefix" != "SUBNET" ]]; then
        continue
    fi
    
    subnet_ip=$(echo "$cidr" | sed 's|0/24|10|')
    echo "  - ${namespace}: http://${subnet_ip}:8080"
    
done < "$VPC_STATE_FILE"
