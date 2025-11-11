# VPC Control Tool (vpcctl)

A Linux-based Virtual Private Cloud (VPC) implementation that recreates AWS VPC functionality using native Linux networking primitives. Built for the HNG Internship Stage 4 DevOps challenge.

## 🎯 Project Overview

This project demonstrates how to build a production-grade network isolation and routing system using:
- **Linux Network Namespaces** for subnet isolation
- **Linux Bridges** as VPC routers
- **veth Pairs** for virtual network connections
- **iptables** for NAT, routing, and firewall rules
- **Bash** for automation and CLI tooling

### Architecture

```
                          ┌─────────────┐
                          │  Internet   │
                          └──────┬──────┘
                                 │ NAT (MASQUERADE)
        ┌────────────────────────┴────────────────────────┐
        │          TestVPC (10.0.0.0/16)                  │
        │            Bridge: br-TestVPC                   │
        │             Gateway: 10.0.0.1                   │
        ├──────────────────┬──────────────────────────────┤
        │                  │                              │
 ┌──────▼──────────┐  ┌───▼────────────┐         ┌───────────┐
 │ Public Subnet   │  │ Private Subnet │◄────────┤  Peering  │
 │  10.0.1.0/24    │  │  10.0.2.0/24   │         │  Connection│
 │                 │  │                │         └─────┬─────┘
 │ ✓ NAT Gateway   │  │ ✗ No Internet  │               │
 │ ✓ HTTP/HTTPS    │  │ ✓ MySQL (3306) │               │
 │ ✓ SSH (VPC)     │  │ ✓ SSH (Public) │               │
 └─────────────────┘  └────────────────┘               │
                                                        │
        ┌───────────────────────────────────────────────┘
        │
        │          VPC2 (192.168.0.0/16)
        │            Bridge: br-VPC2
        │
        └──────────► 192.168.1.0/24 (web subnet)
```

## ✨ Features

- ✅ **VPC Management**: Create/delete isolated virtual networks
- ✅ **Subnet Management**: Public and private subnets with proper routing
- ✅ **NAT Gateway**: Internet access for public subnets
- ✅ **Network Isolation**: Private subnets without internet access
- ✅ **VPC Peering**: Connect multiple VPCs
- ✅ **Security Groups**: JSON-based firewall policies (permissive/strict modes)
- ✅ **State Management**: Track VPCs, subnets, and peering connections
- ✅ **Logging**: Comprehensive logging to console and file
- ✅ **Testing Suite**: Automated connectivity and isolation tests

## 📋 Prerequisites

### System Requirements
- Linux operating system (Ubuntu 20.04+ recommended)
- Root/sudo access
- Kernel with namespace support (3.8+)

### Required Packages
```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y \
    iproute2 \
    iptables \
    bridge-utils \
    jq \
    netcat \
    curl \
    python3

# Or use the install script
sudo ./install.sh
```

## 🚀 Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd stage4
```

2. Run the installation script:
```bash
sudo ./install.sh
```

3. Verify installation:
```bash
./vpcctl --help
```

## 📖 Usage

### Basic Commands

#### Create a VPC
```bash
sudo ./vpcctl create-vpc --name MyVPC --cidr 10.0.0.0/16
```

#### Create Subnets
```bash
# Public subnet (with NAT gateway)
sudo ./vpcctl create-subnet \
    --vpc MyVPC \
    --name public \
    --cidr 10.0.1.0/24 \
    --type public

# Private subnet (no internet)
sudo ./vpcctl create-subnet \
    --vpc MyVPC \
    --name private \
    --cidr 10.0.2.0/24 \
    --type private
```

#### List Resources
```bash
# List all VPCs
sudo ./vpcctl list-vpcs

# List all subnets
sudo ./vpcctl list-subnets
```

#### VPC Peering
```bash
# Create peering connection between two VPCs
sudo ./vpcctl peer-vpcs --vpc1 VPC1 --vpc2 VPC2

# List peering connections
sudo ./vpcctl list-peerings
```

#### Firewall Management
```bash
# Apply security policies (permissive mode)
sudo ./vpcctl apply-firewall

# Apply security policies (strict mode - default DROP)
sudo ./vpcctl apply-firewall --strict

# Clear firewall rules
sudo ./vpcctl clear-firewall --subnet 10.0.1.0/24
```

#### Delete Resources
```bash
# Delete a VPC (and all its subnets)
sudo ./vpcctl delete-vpc --name MyVPC

# Delete a peering connection
sudo ./vpcctl unpeer-vpcs --vpc1 VPC1 --vpc2 VPC2
```

### Advanced Examples

#### Full VPC Setup
```bash
# Create VPC
sudo ./vpcctl create-vpc --name Production --cidr 10.0.0.0/16

# Create public subnet with web servers
sudo ./vpcctl create-subnet \
    --vpc Production \
    --name web \
    --cidr 10.0.1.0/24 \
    --type public

# Create private subnet for database
sudo ./vpcctl create-subnet \
    --vpc Production \
    --name database \
    --cidr 10.0.2.0/24 \
    --type private

# Apply firewall policies
sudo ./vpcctl apply-firewall --strict

# Test connectivity
sudo ip netns exec Production-web ping -c 3 10.0.2.10
```

#### Multi-VPC with Peering
```bash
# Create first VPC
sudo ./vpcctl create-vpc --name VPC-App --cidr 10.0.0.0/16
sudo ./vpcctl create-subnet --vpc VPC-App --name app --cidr 10.0.1.0/24 --type public

# Create second VPC
sudo ./vpcctl create-vpc --name VPC-Data --cidr 192.168.0.0/16
sudo ./vpcctl create-subnet --vpc VPC-Data --name data --cidr 192.168.1.0/24 --type private

# Connect them
sudo ./vpcctl peer-vpcs --vpc1 VPC-App --vpc2 VPC-Data
```

## 🔐 Security Groups

Security policies are defined in `config/security-groups.json`:

```json
{
  "policies": [
    {
      "subnet": "10.0.1.0/24",
      "description": "Public subnet - web server rules",
      "ingress": [
        {
          "port": 80,
          "protocol": "tcp",
          "source": "0.0.0.0/0",
          "action": "allow",
          "description": "Allow HTTP from anywhere"
        },
        {
          "port": 443,
          "protocol": "tcp",
          "source": "0.0.0.0/0",
          "action": "allow",
          "description": "Allow HTTPS from anywhere"
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
          "description": "Allow all outbound traffic"
        }
      ]
    }
  ]
}
```

## 🧪 Testing

### Run All Tests
```bash
# Connectivity tests
./tests/test-connectivity.sh

# Isolation tests
./tests/test-isolation.sh

# Firewall tests
./tests/test-firewall.sh
```

### Manual Testing

Test from within a namespace:
```bash
# Execute commands in a namespace
sudo ip netns exec MyVPC-public bash

# Inside the namespace:
ip addr show        # View IP address
ip route show       # View routing table
ping 8.8.8.8       # Test internet connectivity
curl http://10.0.2.10:8080  # Test internal connectivity
```

## 📁 Project Structure

```
stage4/
├── vpcctl                      # Main CLI entry point
├── cleanup.sh                  # Infrastructure cleanup script
├── install.sh                  # Dependency installer
├── README.md                   # This file
│
├── lib/                        # Core functionality
│   ├── common.sh              # Shared utilities
│   ├── vpc.sh                 # VPC management
│   ├── subnet.sh              # Subnet management
│   ├── peering.sh             # VPC peering
│   ├── firewall.sh            # Security groups/firewall
│   └── routing.sh             # Routing utilities
│
├── config/                     # Configuration files
│   ├── vpc.conf               # VPC state (auto-generated)
│   └── security-groups.json   # Firewall policies
│
├── demo/                       # Demonstration scripts
│   ├── deploy-webservers.sh   # Deploy test web servers
│   └── demo-scenario.sh       # Full demo walkthrough
│
├── tests/                      # Test suite
│   ├── test-connectivity.sh   # Connectivity tests
│   ├── test-isolation.sh      # Isolation tests
│   └── test-firewall.sh       # Firewall enforcement tests
│
└── logs/                       # Log files (auto-generated)
    └── vpcctl.log
```

## 🔧 How It Works

### Network Namespaces (Subnets)
Each subnet is implemented as a Linux network namespace, providing complete network isolation:
```bash
# Create namespace
ip netns add MyVPC-public

# Execute commands in namespace
ip netns exec MyVPC-public <command>
```

### Linux Bridges (VPC Router)
Each VPC is a Linux bridge that acts as a virtual router:
```bash
# Create bridge
ip link add br-MyVPC type bridge

# Assign gateway IP
ip addr add 10.0.0.1/16 dev br-MyVPC
```

### veth Pairs (Virtual Cables)
Connect namespaces to bridges using virtual ethernet pairs:
```bash
# Create veth pair
ip link add veth-host type veth peer name veth-ns

# Move one end to namespace
ip link set veth-ns netns MyVPC-public

# Attach other end to bridge
ip link set veth-host master br-MyVPC
```

### NAT Gateway (iptables)
Enable internet access for public subnets:
```bash
# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Add MASQUERADE rule
iptables -t nat -A POSTROUTING -s 10.0.0.0/16 -j MASQUERADE
```

### Firewall (iptables)
Implement security groups using iptables:
```bash
# Strict mode - default DROP
ip netns exec MyVPC-public iptables -P INPUT DROP

# Allow specific ports
ip netns exec MyVPC-public iptables -A INPUT -p tcp --dport 80 -j ACCEPT
```

## 🧹 Cleanup

To remove all VPC infrastructure:
```bash
sudo ./cleanup.sh
```

This will:
- Stop all web server processes
- Delete all network namespaces
- Remove all bridge interfaces
- Delete all veth pairs
- Clear iptables NAT rules
- Clean up state files and logs

## 📊 State Management

VPC state is tracked in `config/vpc.conf`:

```
VPC:TestVPC:10.0.0.0/16:br-TestVPC:2024-01-15_14:30:22
SUBNET:TestVPC:public:10.0.1.0/24:public:TestVPC-public:2024-01-15_14:31:45
SUBNET:TestVPC:private:10.0.2.0/24:private:TestVPC-private:2024-01-15_14:32:10
PEERING:TestVPC:VPC2:vp-TestVP:vp-VPC2:2024-01-15_14:35:55
```

## 🐛 Troubleshooting

### Common Issues

**"RTNETLINK answers: File exists"**
- Resource already exists. Delete existing resources first.

**"Cannot find device"**
- Namespace or interface doesn't exist. Check with `ip netns list`.

**"Permission denied"**
- Must run with sudo/root privileges.

**Routing not working**
- Check routes: `sudo ip netns exec <namespace> ip route show`
- Verify IP forwarding: `sysctl net.ipv4.ip_forward`

**No internet access in public subnet**
- Check NAT rules: `sudo iptables -t nat -L -n -v`
- Verify MASQUERADE rule exists for VPC CIDR

### Debug Commands

```bash
# List all namespaces
ip netns list

# List all bridges
ip link show type bridge

# Show namespace routing
sudo ip netns exec <namespace> ip route show

# Show iptables NAT rules
sudo iptables -t nat -L -n -v

# Show firewall rules in namespace
sudo ip netns exec <namespace> iptables -L -n -v

# Check logs
tail -f logs/vpcctl.log
```

## 📝 Configuration Files

### vpc.conf
Auto-generated state file tracking all VPC resources.

### security-groups.json
JSON-formatted firewall policies defining ingress/egress rules.

## 🎓 Learning Resources

- [Linux Network Namespaces](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- [Linux Bridge](https://wiki.linuxfoundation.org/networking/bridge)
- [iptables Tutorial](https://www.netfilter.org/documentation/HOWTO/packet-filtering-HOWTO.html)
- [veth Pairs](https://man7.org/linux/man-pages/man4/veth.4.html)

## 👨‍💻 Author

Built for HNG Internship Stage 4 DevOps Challenge

## 📄 License

This project is for educational purposes.

## 🙏 Acknowledgments

- HNG Internship Program
- Linux kernel networking subsystem
- AWS VPC documentation (for reference architecture)

---

**Project Status**: ✅ Complete  
**Last Updated**: 2024

For questions or issues, please refer to the troubleshooting section or check the logs at `logs/vpcctl.log`.
