#!/bin/bash

# test-firewall.sh - Test firewall rule enforcement

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

log_test() {
    echo -e "\n${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

test_port_access() {
    local namespace=$1
    local target_ip=$2
    local port=$3
    local expect=$4  # "allow" or "block"
    local description=$5
    
    log_test "Testing $description"
    
    # Use nc (netcat) with timeout to test port
    if sudo ip netns exec "$namespace" timeout 2 bash -c "echo '' | nc -w 1 $target_ip $port" &>/dev/null; then
        if [[ "$expect" == "allow" ]]; then
            log_pass "Port $port accessible (as expected)"
        else
            log_fail "Port $port accessible (should be blocked)"
        fi
    else
        if [[ "$expect" == "block" ]]; then
            log_pass "Port $port blocked (as expected)"
        else
            log_fail "Port $port blocked (should be accessible)"
        fi
    fi
}

test_http_access() {
    local namespace=$1
    local target_ip=$2
    local port=$3
    local expect=$4
    local description=$5
    
    log_test "Testing $description"
    
    if sudo ip netns exec "$namespace" timeout 2 curl -s "http://$target_ip:$port" > /dev/null 2>&1; then
        if [[ "$expect" == "allow" ]]; then
            log_pass "HTTP access successful (as expected)"
        else
            log_fail "HTTP access successful (should be blocked)"
        fi
    else
        if [[ "$expect" == "block" ]]; then
            log_pass "HTTP access blocked (as expected)"
        else
            log_fail "HTTP access blocked (should be allowed)"
        fi
    fi
}

echo "======================================"
echo "   FIREWALL ENFORCEMENT TESTS"
echo "======================================"

# Get IPs from namespaces
PUBLIC_IP=$(sudo ip netns exec TestVPC-public ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1)
PRIVATE_IP=$(sudo ip netns exec TestVPC-private ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1)
VPC2_IP=$(sudo ip netns exec VPC2-web ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1)

echo "Public Subnet IP: $PUBLIC_IP"
echo "Private Subnet IP: $PRIVATE_IP"
echo "VPC2 Subnet IP: $VPC2_IP"
echo ""

# Test 1: Web servers on port 8080 (currently running)
test_http_access "TestVPC-public" "$PUBLIC_IP" "8080" "allow" "Public subnet web server (port 8080)"
test_http_access "TestVPC-private" "$PRIVATE_IP" "8080" "allow" "Private subnet web server (port 8080)"

# Test 2: Cross-subnet communication (public to private)
test_http_access "TestVPC-public" "$PRIVATE_IP" "8080" "allow" "Public to private subnet (via peering)"

# Test 3: Cross-VPC communication (TestVPC to VPC2)
test_http_access "TestVPC-public" "$VPC2_IP" "8080" "allow" "TestVPC to VPC2 (via VPC peering)"

# Test 4: Internet access
log_test "Testing internet access from public subnet"
if sudo ip netns exec TestVPC-public timeout 3 ping -c 1 8.8.8.8 &>/dev/null; then
    log_pass "Public subnet has internet access (via NAT)"
else
    log_fail "Public subnet has no internet access"
fi

log_test "Testing internet access from private subnet"
if sudo ip netns exec TestVPC-private timeout 3 ping -c 1 8.8.8.8 &>/dev/null; then
    log_fail "Private subnet has internet access (should be isolated)"
else
    log_pass "Private subnet is isolated (no internet)"
fi

# Summary
echo ""
echo "======================================"
echo "         TEST SUMMARY"
echo "======================================"
echo -e "${GREEN}PASSED: $PASSED${NC}"
echo -e "${RED}FAILED: $FAILED${NC}"
echo "======================================"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
