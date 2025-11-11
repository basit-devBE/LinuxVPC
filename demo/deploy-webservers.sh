#!/bin/bash

# deploy-webservers.sh - Deploy web servers in VPC subnets for demonstration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "=== Deploying Web Servers in VPC Subnets ==="
echo ""

# Deploy in TestVPC-public
echo "Deploying web server in TestVPC-public (10.0.1.10:8080)..."
sudo ip netns exec TestVPC-public bash -c 'mkdir -p /tmp/public-webserver && cat > /tmp/public-webserver/index.html << EOF
<!DOCTYPE html>
<html>
<head><title>Public Subnet Web Server</title></head>
<body>
<h1>Welcome to Public Subnet</h1>
<p>VPC: TestVPC</p>
<p>Subnet: public (10.0.1.0/24)</p>
<p>IP: 10.0.1.10</p>
<p>Type: Public Subnet with Internet Access</p>
</body>
</html>
EOF
'

sudo ip netns exec TestVPC-public python3 -m http.server 8080 --directory /tmp/public-webserver > /tmp/public-webserver.log 2>&1 &
PUBLIC_PID=$!
echo "  Started (PID: $PUBLIC_PID)"

# Deploy in TestVPC-private
echo "Deploying web server in TestVPC-private (10.0.2.10:8080)..."
sudo ip netns exec TestVPC-private bash -c 'mkdir -p /tmp/private-webserver && cat > /tmp/private-webserver/index.html << EOF
<!DOCTYPE html>
<html>
<head><title>Private Subnet Web Server</title></head>
<body>
<h1>Welcome to Private Subnet</h1>
<p>VPC: TestVPC</p>
<p>Subnet: private (10.0.2.0/24)</p>
<p>IP: 10.0.2.10</p>
<p>Type: Private Subnet (No Internet Access)</p>
</body>
</html>
EOF
'

sudo ip netns exec TestVPC-private python3 -m http.server 8080 --directory /tmp/private-webserver > /tmp/private-webserver.log 2>&1 &
PRIVATE_PID=$!
echo "  Started (PID: $PRIVATE_PID)"

# Deploy in VPC2-web (if it exists)
if sudo ip netns list | grep -q "VPC2-web"; then
    echo "Deploying web server in VPC2-web (192.168.1.10:8080)..."
    sudo ip netns exec VPC2-web bash -c 'mkdir -p /tmp/vpc2-webserver && cat > /tmp/vpc2-webserver/index.html << EOF
<!DOCTYPE html>
<html>
<head><title>VPC2 Web Server</title></head>
<body>
<h1>Welcome to VPC2</h1>
<p>VPC: VPC2</p>
<p>Subnet: web (192.168.1.0/24)</p>
<p>IP: 192.168.1.10</p>
<p>Type: Public Subnet in Different VPC</p>
</body>
</html>
EOF
'

    sudo ip netns exec VPC2-web python3 -m http.server 8080 --directory /tmp/vpc2-webserver > /tmp/vpc2-webserver.log 2>&1 &
    VPC2_PID=$!
    echo "  Started (PID: $VPC2_PID)"
fi

echo ""
echo "=== Web Servers Deployed ==="
echo ""
echo "Testing web servers..."
sleep 2

echo "  TestVPC-public: $(sudo ip netns exec TestVPC-public curl -s http://127.0.0.1:8080 2>&1 | grep -o '<h1>.*</h1>' || echo 'FAILED')"
echo "  TestVPC-private: $(sudo ip netns exec TestVPC-private curl -s http://127.0.0.1:8080 2>&1 | grep -o '<h1>.*</h1>' || echo 'FAILED')"
if sudo ip netns list | grep -q "VPC2-web"; then
    echo "  VPC2-web: $(sudo ip netns exec VPC2-web curl -s http://127.0.0.1:8080 2>&1 | grep -o '<h1>.*</h1>' || echo 'FAILED')"
fi

echo ""
echo "✓ All web servers are running!"
echo ""
echo "Access URLs (from within namespaces):"
echo "  - Public:  http://10.0.1.10:8080"
echo "  - Private: http://10.0.2.10:8080"
if sudo ip netns list | grep -q "VPC2-web"; then
    echo "  - VPC2:    http://192.168.1.10:8080"
fi
