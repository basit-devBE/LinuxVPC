#!/bin/bash

# cleanup.sh - Comprehensive VPC infrastructure cleanup script
# Removes all VPC resources: namespaces, bridges, veth pairs, iptables rules, processes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
VPC_STATE_FILE="${CONFIG_DIR}/vpc.conf"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

cleanup_processes() {
    log_info "Cleaning up web server processes..."
    
    # Kill Python HTTP servers
    if pkill -f "python3 -m http.server" 2>/dev/null; then
        log_success "Stopped web server processes"
    else
        log_info "No web server processes found"
    fi
    
    # Clean up temporary web directories
    rm -rf /tmp/*-web 2>/dev/null || true
    rm -rf /tmp/*-webserver.log 2>/dev/null || true
}

cleanup_namespaces() {
    log_info "Cleaning up network namespaces..."
    
    local count=0
    
    # Get list of all namespaces
    for ns in $(ip netns list 2>/dev/null | awk '{print $1}'); do
        log_info "  Deleting namespace: $ns"
        
        # Clear iptables rules first
        ip netns exec "$ns" iptables -F 2>/dev/null || true
        ip netns exec "$ns" iptables -X 2>/dev/null || true
        ip netns exec "$ns" iptables -t nat -F 2>/dev/null || true
        ip netns exec "$ns" iptables -t nat -X 2>/dev/null || true
        
        # Delete the namespace (this also removes veth pairs)
        ip netns delete "$ns" 2>/dev/null || true
        ((count++))
    done
    
    if [[ $count -gt 0 ]]; then
        log_success "Deleted $count namespace(s)"
    else
        log_info "No namespaces found"
    fi
}

cleanup_bridges() {
    log_info "Cleaning up bridge interfaces..."
    
    local count=0
    
    # Find all bridges starting with br-
    for bridge in $(ip link show type bridge 2>/dev/null | grep "^[0-9]" | grep "br-" | awk '{print $2}' | tr -d ':'); do
        log_info "  Deleting bridge: $bridge"
        
        # Bring down the bridge
        ip link set "$bridge" down 2>/dev/null || true
        
        # Delete the bridge
        ip link delete "$bridge" type bridge 2>/dev/null || true
        ((count++))
    done
    
    if [[ $count -gt 0 ]]; then
        log_success "Deleted $count bridge(s)"
    else
        log_info "No VPC bridges found"
    fi
}

cleanup_veth_pairs() {
    log_info "Cleaning up standalone veth pairs..."
    
    local count=0
    
    # Find veth pairs (peering connections)
    for veth in $(ip link show type veth 2>/dev/null | grep "^[0-9]" | grep -E "vp-|veth-" | awk '{print $2}' | tr -d ':' | cut -d'@' -f1); do
        log_info "  Deleting veth: $veth"
        ip link delete "$veth" 2>/dev/null || true
        ((count++))
    done
    
    if [[ $count -gt 0 ]]; then
        log_success "Deleted $count veth pair(s)"
    else
        log_info "No standalone veth pairs found"
    fi
}

cleanup_iptables() {
    log_info "Cleaning up host iptables NAT rules..."
    
    # Flush NAT table
    iptables -t nat -F 2>/dev/null || true
    
    # Remove MASQUERADE rules for VPC CIDRs
    iptables -t nat -D POSTROUTING -s 10.0.0.0/16 -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s 192.168.0.0/16 -j MASQUERADE 2>/dev/null || true
    
    log_success "Cleaned up iptables NAT rules"
}

cleanup_state_file() {
    log_info "Cleaning up state file..."
    
    if [[ -f "$VPC_STATE_FILE" ]]; then
        # Backup the state file
        cp "$VPC_STATE_FILE" "${VPC_STATE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "  Backed up state file"
        
        # Clear the state file
        true > "$VPC_STATE_FILE"
        log_success "Cleared state file"
    else
        log_info "No state file found"
    fi
}

cleanup_log_files() {
    log_info "Cleaning up log files..."
    
    if [[ -d "${SCRIPT_DIR}/logs" ]]; then
        rm -f "${SCRIPT_DIR}"/logs/*.log 2>/dev/null || true
        log_success "Cleaned up log files"
    else
        log_info "No log directory found"
    fi
}

show_remaining_resources() {
    log_info "Checking for remaining resources..."
    
    local remaining=0
    
    echo ""
    echo "Namespaces:"
    if ip netns list 2>/dev/null | grep -q .; then
        ip netns list
        remaining=1
    else
        echo "  None"
    fi
    
    echo ""
    echo "Bridges:"
    if ip link show type bridge 2>/dev/null | grep -q "br-"; then
        ip link show type bridge | grep "br-"
        remaining=1
    else
        echo "  None"
    fi
    
    echo ""
    echo "Veth pairs:"
    if ip link show type veth 2>/dev/null | grep -qE "vp-|veth-"; then
        ip link show type veth | grep -E "vp-|veth-"
        remaining=1
    else
        echo "  None"
    fi
    
    if [[ $remaining -eq 0 ]]; then
        log_success "All VPC resources cleaned up successfully!"
    else
        log_warn "Some resources may still exist (shown above)"
    fi
}

# Main cleanup process
main() {
    echo "======================================"
    echo "   VPC INFRASTRUCTURE CLEANUP"
    echo "======================================"
    echo ""
    
    read -p "This will delete ALL VPC resources. Continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Cleanup cancelled"
        exit 0
    fi
    
    echo ""
    log_info "Starting cleanup process..."
    echo ""
    
    # Run cleanup steps in order
    cleanup_processes
    echo ""
    
    cleanup_namespaces
    echo ""
    
    cleanup_bridges
    echo ""
    
    cleanup_veth_pairs
    echo ""
    
    cleanup_iptables
    echo ""
    
    cleanup_state_file
    echo ""
    
    cleanup_log_files
    echo ""
    
    echo "======================================"
    echo "        CLEANUP COMPLETE"
    echo "======================================"
    echo ""
    
    show_remaining_resources
}

# Run main function
main "$@"
