#!/bin/bash

# demo-scenario.sh - Complete VPC demonstration scenario
# Shows all features: VPC creation, subnets, routing, peering, firewall

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPCCTL="${SCRIPT_DIR}/../vpcctl"

# Demo configuration
DEMO_VPC="DemoVPC"
DEMO_VPC_CIDR="10.0.0.0/16"
DEMO_VPC2="Partner VPC"
DEMO_VPC2_CIDR="192.168.0.0/16"

pause() {
    echo ""
    echo -e "${CYAN}Press Enter to continue...${NC}"
    read -r
}

section_header() {
    echo ""
    echo "======================================"
    echo -e "${MAGENTA}$1${NC}"
    echo "======================================"
    echo ""
}

demo_step() {
    echo -e "${YELLOW}▶${NC} $1"
}

demo_command() {
    echo -e "${GREEN}$ ${NC}$1"
    sleep 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This demo must be run as root (use sudo)${NC}"
    exit 1
fi

# Welcome
clear
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║                                                        ║"
echo "║          VPC Control Tool - Live Demonstration        ║"
echo "║                                                        ║"
echo "║  Recreating AWS VPC functionality with Linux          ║"
echo "║                                                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo -e "${CYAN}This demo will showcase:${NC}"
echo "  ✓ VPC creation and management"
echo "  ✓ Public and private subnets"
echo "  ✓ NAT gateway for internet access"
echo "  ✓ Network isolation"
echo "  ✓ VPC peering"
echo "  ✓ Security groups/firewall"
echo "  ✓ Web application deployment"
echo ""
pause

# Step 1: Create VPC
section_header "STEP 1: Create Virtual Private Cloud (VPC)"

demo_step "Creating a VPC with CIDR block $DEMO_VPC_CIDR"
demo_command "sudo ./vpcctl create-vpc --name \"$DEMO_VPC\" --cidr $DEMO_VPC_CIDR"
"$VPCCTL" create-vpc --name "$DEMO_VPC" --cidr "$DEMO_VPC_CIDR"

echo ""
demo_step "What just happened?"
echo "  • Created a Linux bridge (br-DemoVPC) as the VPC router"
echo "  • Assigned gateway IP 10.0.0.1/16 to the bridge"
echo "  • Enabled IP forwarding for routing"
echo ""

demo_step "Listing all VPCs:"
demo_command "sudo ./vpcctl list-vpcs"
"$VPCCTL" list-vpcs

pause

# Step 2: Create Public Subnet
section_header "STEP 2: Create Public Subnet (with Internet Access)"

demo_step "Creating a public subnet for web servers"
demo_command "sudo ./vpcctl create-subnet --vpc \"$DEMO_VPC\" --name web --cidr 10.0.1.0/24 --type public"
"$VPCCTL" create-subnet --vpc "$DEMO_VPC" --name web --cidr 10.0.1.0/24 --type public

echo ""
demo_step "What just happened?"
echo "  • Created network namespace 'DemoVPC-web'"
echo "  • Created veth pair connecting namespace to bridge"
echo "  • Assigned IP 10.0.1.10/24 to the subnet"
echo "  • Configured routing via gateway (10.0.0.1)"
echo "  • Added NAT rule for internet access"
echo ""

pause

# Step 3: Create Private Subnet
section_header "STEP 3: Create Private Subnet (No Internet)"

demo_step "Creating a private subnet for databases"
demo_command "sudo ./vpcctl create-subnet --vpc \"$DEMO_VPC\" --name database --cidr 10.0.2.0/24 --type private"
"$VPCCTL" create-subnet --vpc "$DEMO_VPC" --name database --cidr 10.0.2.0/24 --type private

echo ""
demo_step "What just happened?"
echo "  • Created network namespace 'DemoVPC-database'"
echo "  • Connected to bridge via veth pair"
echo "  • Assigned IP 10.0.2.10/24"
echo "  • NO NAT rule (no internet access)"
echo ""

demo_step "Listing all subnets:"
demo_command "sudo ./vpcctl list-subnets"
"$VPCCTL" list-subnets

pause

# Step 4: Test Internet Connectivity
section_header "STEP 4: Test Internet Connectivity"

demo_step "Testing internet from PUBLIC subnet (should work):"
demo_command "sudo ip netns exec DemoVPC-web ping -c 3 8.8.8.8"
if ip netns exec DemoVPC-web ping -c 3 8.8.8.8 2>&1; then
    echo -e "${GREEN}✓ Public subnet has internet access via NAT${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

echo ""
demo_step "Testing internet from PRIVATE subnet (should fail):"
demo_command "sudo ip netns exec DemoVPC-database timeout 3 ping -c 2 8.8.8.8 || echo 'No internet (as expected)'"
if ip netns exec DemoVPC-database timeout 3 ping -c 2 8.8.8.8 2>/dev/null; then
    echo -e "${RED}✗ Private subnet has internet (shouldn't!)${NC}"
else
    echo -e "${GREEN}✓ Private subnet is isolated (as expected)${NC}"
fi

pause

# Step 5: Test Intra-VPC Communication
section_header "STEP 5: Test Intra-VPC Communication"

demo_step "Testing connectivity from public to private subnet:"
demo_command "sudo ip netns exec DemoVPC-web ping -c 3 10.0.2.10"
if ip netns exec DemoVPC-web ping -c 3 10.0.2.10 2>&1; then
    echo -e "${GREEN}✓ Subnets can communicate within VPC${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

pause

# Step 6: Create Second VPC and Peer
section_header "STEP 6: VPC Peering"

demo_step "Creating a second VPC to demonstrate peering"
demo_command "sudo ./vpcctl create-vpc --name \"$DEMO_VPC2\" --cidr $DEMO_VPC2_CIDR"
"$VPCCTL" create-vpc --name "$DEMO_VPC2" --cidr "$DEMO_VPC2_CIDR"

demo_step "Creating a subnet in the second VPC"
demo_command "sudo ./vpcctl create-subnet --vpc \"$DEMO_VPC2\" --name api --cidr 192.168.1.0/24 --type public"
"$VPCCTL" create-subnet --vpc "$DEMO_VPC2" --name api --cidr 192.168.1.0/24 --type public

echo ""
demo_step "Now connecting the two VPCs via peering"
demo_command "sudo ./vpcctl peer-vpcs --vpc1 \"$DEMO_VPC\" --vpc2 \"$DEMO_VPC2\""
"$VPCCTL" peer-vpcs --vpc1 "$DEMO_VPC" --vpc2 "$DEMO_VPC2"

echo ""
demo_step "Listing peering connections:"
demo_command "sudo ./vpcctl list-peerings"
"$VPCCTL" list-peerings

pause

# Step 7: Test Cross-VPC Communication
section_header "STEP 7: Test Cross-VPC Communication"

demo_step "Testing connectivity from DemoVPC to PartnerVPC via peering:"
demo_command "sudo ip netns exec DemoVPC-web ping -c 3 192.168.1.10"
if ip netns exec DemoVPC-web ping -c 3 192.168.1.10 2>&1; then
    echo -e "${GREEN}✓ VPC peering works! Cross-VPC communication successful${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

pause

# Step 8: Deploy Web Applications
section_header "STEP 8: Deploy Web Applications"

demo_step "Deploying Python HTTP servers in each subnet for testing"
demo_command "sudo ./demo/deploy-webservers.sh"
"${SCRIPT_DIR}/deploy-webservers.sh"

pause

# Step 9: Apply Security Policies
section_header "STEP 9: Apply Security Policies (Firewall)"

demo_step "Viewing current security policy:"
demo_command "cat config/security-groups.json | jq '.'"
cat "${SCRIPT_DIR}/../config/security-groups.json" | jq '.' | head -30

echo ""
demo_step "Applying firewall in STRICT mode (default DROP)"
demo_command "sudo ./vpcctl apply-firewall --strict"
"$VPCCTL" apply-firewall --strict

echo ""
demo_step "Firewall rules now active:"
echo "  • Public subnet: Allow HTTP(80), HTTPS(443), SSH(22 from VPC)"
echo "  • Private subnet: Allow MySQL(3306), SSH(22 from public subnet)"
echo "  • Default policy: DROP (block all other traffic)"

pause

# Step 10: Network Topology
section_header "STEP 10: Network Topology Overview"

echo -e "${CYAN}Current Network Architecture:${NC}"
echo ""
echo "                    ┌─────────────┐"
echo "                    │  Internet   │"
echo "                    └──────┬──────┘"
echo "                           │ NAT"
echo "      ┌────────────────────┴────────────────────┐"
echo "      │       DemoVPC (10.0.0.0/16)            │"
echo "      │         Bridge: br-DemoVPC              │"
echo "      ├──────────────┬────────────────────────  │"
echo "      │              │                          │"
echo " ┌────▼──────┐  ┌────▼──────────┐              │"
echo " │ web       │  │ database      │              │"
echo " │ 10.0.1.10 │  │ 10.0.2.10     │              │"
echo " │ PUBLIC    │  │ PRIVATE       │              │"
echo " │ ✓ NAT     │  │ ✗ No Internet │              │"
echo " └───────────┘  └───────────────┘              │"
echo "      │                                         │"
echo "      │  Peering                                │"
echo "      └──────────┐                              │"
echo "                 │                              │"
echo "      ┌──────────▼──────────────────────────────┘"
echo "      │   PartnerVPC (192.168.0.0/16)          │"
echo "      │      Bridge: br-PartnerVPC              │"
echo "      ├──────────────┐                          │"
echo "      │              │                          │"
echo " ┌────▼──────┐                                  │"
echo " │ api       │                                  │"
echo " │ 192.168.1.10                                 │"
echo " │ PUBLIC    │                                  │"
echo " └───────────┘                                  │"
echo ""

pause

# Summary
section_header "DEMONSTRATION SUMMARY"

echo -e "${GREEN}✓ Successfully demonstrated:${NC}"
echo ""
echo "  1. VPC creation with Linux bridges"
echo "  2. Public subnet with NAT gateway (internet access)"
echo "  3. Private subnet without internet (isolated)"
echo "  4. Intra-VPC communication (public ↔ private)"
echo "  5. VPC peering connection"
echo "  6. Cross-VPC communication"
echo "  7. Web application deployment"
echo "  8. Security group enforcement (iptables firewall)"
echo ""
echo -e "${CYAN}Resources created:${NC}"
echo "  • 2 VPCs (DemoVPC, PartnerVPC)"
echo "  • 3 Subnets (web, database, api)"
echo "  • 1 VPC peering connection"
echo "  • 3 Web servers (port 8080)"
echo "  • Firewall policies (strict mode)"
echo ""
echo -e "${YELLOW}Implementation Details:${NC}"
echo "  • Network Namespaces: Subnet isolation"
echo "  • Linux Bridges: VPC routers"
echo "  • veth Pairs: Virtual network cables"
echo "  • iptables: NAT and firewall rules"
echo "  • Bash: Automation and CLI"
echo ""

pause

# Cleanup option
section_header "CLEANUP"

echo -e "${YELLOW}Would you like to clean up the demo infrastructure?${NC}"
read -p "Remove all resources? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    demo_command "sudo ./cleanup.sh"
    "${SCRIPT_DIR}/../cleanup.sh" <<< "y"
else
    echo ""
    echo -e "${GREEN}Resources preserved.${NC}"
    echo "To clean up later, run: ${CYAN}sudo ./cleanup.sh${NC}"
fi

echo ""
echo "======================================"
echo -e "${GREEN}     DEMO COMPLETE!${NC}"
echo "======================================"
echo ""
echo "Thank you for watching!"
echo ""
