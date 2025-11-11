#!/bin/bash

# install.sh - Check dependencies and setup

set -euo pipefail

echo "=== VPC Control Tool - Setup ==="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Check required commands
REQUIRED_COMMANDS=("ip" "iptables" "bridge" "sysctl")
MISSING=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING+=("$cmd")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "Missing required commands: ${MISSING[*]}"
    echo ""
    echo "Install with:"
    echo "  Ubuntu/Debian: sudo apt install iproute2 iptables bridge-utils"
    echo "  Fedora/RHEL: sudo dnf install iproute iptables bridge-utils"
    exit 1
fi

echo "✓ All required commands found"
echo ""

# Enable IP forwarding permanently
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "Enabling IP forwarding permanently..."
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p >/dev/null
    echo "✓ IP forwarding enabled"
else
    echo "✓ IP forwarding already enabled"
fi

# Create directories
mkdir -p config logs demo/screenshots

# Make vpcctl executable
chmod +x vpcctl
chmod +x lib/*.sh 2>/dev/null || true
echo "✓ vpcctl made executable"

# Create empty state file
touch config/vpc.conf
echo "✓ State file created"

# Create default security groups JSON
if [[ ! -f config/security-groups.json ]]; then
    cat > config/security-groups.json << 'EOF'
{
  "policies": [
    {
      "subnet": "10.0.1.0/24",
      "description": "Example public subnet policy",
      "ingress": [
        {
          "port": 80,
          "protocol": "tcp",
          "source": "0.0.0.0/0",
          "action": "allow",
          "description": "Allow HTTP"
        },
        {
          "port": 443,
          "protocol": "tcp",
          "source": "0.0.0.0/0",
          "action": "allow",
          "description": "Allow HTTPS"
        },
        {
          "port": 22,
          "protocol": "tcp",
          "source": "10.0.0.0/16",
          "action": "allow",
          "description": "Allow SSH from VPC only"
        }
      ],
      "egress": [
        {
          "destination": "0.0.0.0/0",
          "action": "allow",
          "description": "Allow all outbound"
        }
      ]
    },
    {
      "subnet": "10.0.2.0/24",
      "description": "Example private subnet policy",
      "ingress": [
        {
          "port": 3306,
          "protocol": "tcp",
          "source": "10.0.1.0/24",
          "action": "allow",
          "description": "Allow MySQL from public subnet"
        },
        {
          "port": 22,
          "protocol": "tcp",
          "source": "10.0.1.0/24",
          "action": "allow",
          "description": "Allow SSH from public subnet"
        }
      ],
      "egress": [
        {
          "destination": "10.0.0.0/16",
          "action": "allow",
          "description": "Allow traffic within VPC"
        }
      ]
    }
  ]
}
EOF
    echo "✓ Default security groups config created"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "You can now use vpcctl:"
echo "  sudo ./vpcctl create-vpc --name myvpc --cidr 10.0.0.0/16"
echo "  sudo ./vpcctl add-subnet --vpc myvpc --name public --cidr 10.0.1.0/24 --type public"
echo "  sudo ./vpcctl list-vpcs"
echo ""
echo "For help, run:"
echo "  ./vpcctl --help"
echo ""