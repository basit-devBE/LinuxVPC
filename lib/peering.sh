#!/bin/bash

# peering.sh - VPC peering functions

# Peer two VPCs
peer_vpcs() {
    local vpc1=$1
    local vpc2=$2
    
    require_root
    
    if [[ -z "$vpc1" ]] || [[ -z "$vpc2" ]]; then
        log_error "Both VPC names are required"
        return 1
    fi
    
    if [[ "$vpc1" == "$vpc2" ]]; then
        log_error "Cannot peer a VPC with itself"
        return 1
    fi
    
    local bridge1="br-${vpc1}"
    local bridge2="br-${vpc2}"
    
    # Check if both VPCs exist
    if ! bridge_exists "$bridge1"; then
        log_error "VPC $vpc1 does not exist"
        return 1
    fi
    
    if ! bridge_exists "$bridge2"; then
        log_error "VPC $vpc2 does not exist"
        return 1
    fi
    
    log_info "Peering VPCs: $vpc1 <-> $vpc2"
    
    # Create veth pair to connect the bridges (use shorter names)
    local veth1="vp-${vpc1:0:6}"
    local veth2="vp-${vpc2:0:6}"
    
    # Check if peering already exists
    if ip link show "$veth1" &>/dev/null; then
        log_warn "Peering already exists between $vpc1 and $vpc2"
        return 0
    fi
    
    # Create veth pair
    ip link add "$veth1" type veth peer name "$veth2" || {
        log_error "Failed to create veth pair for peering"
        return 1
    }
    
    # Attach veth ends to respective bridges
    ip link set "$veth1" master "$bridge1" || {
        log_error "Failed to attach $veth1 to $bridge1"
        ip link delete "$veth1"
        return 1
    }
    
    ip link set "$veth2" master "$bridge2" || {
        log_error "Failed to attach $veth2 to $bridge2"
        ip link delete "$veth1"
        return 1
    }
    
    # Bring up both veth interfaces
    ip link set "$veth1" up
    ip link set "$veth2" up
    
    # Get CIDR blocks for both VPCs
    local vpc1_cidr=$(grep "^VPC:${vpc1}:" "${VPC_STATE_FILE}" 2>/dev/null | cut -d: -f3)
    local vpc2_cidr=$(grep "^VPC:${vpc2}:" "${VPC_STATE_FILE}" 2>/dev/null | cut -d: -f3)
    
    # Save peering state
    touch "${VPC_STATE_FILE}"
    echo "PEERING:${vpc1}:${vpc2}:${veth1}:${veth2}:$(date +%s)" >> "${VPC_STATE_FILE}"
    
    log_success "VPCs peered successfully"
    log_info "  $vpc1 ($vpc1_cidr) <-> $vpc2 ($vpc2_cidr)"
    log_info "  Veth pair: $veth1 <-> $veth2"
    
    return 0
}

# Unpeer two VPCs
unpeer_vpcs() {
    local vpc1=$1
    local vpc2=$2
    
    require_root
    
    if [[ -z "$vpc1" ]] || [[ -z "$vpc2" ]]; then
        log_error "Both VPC names are required"
        return 1
    fi
    
    log_info "Unpeering VPCs: $vpc1 <-> $vpc2"
    
    local veth1="vp-${vpc1:0:6}"
    local veth2="vp-${vpc2:0:6}"
    
    # Delete veth pair (this removes both ends)
    if ip link show "$veth1" &>/dev/null; then
        ip link delete "$veth1" || {
            log_error "Failed to delete veth pair"
            return 1
        }
    else
        log_warn "Peering does not exist between $vpc1 and $vpc2"
    fi
    
    # Remove peering state
    sed -i "/^PEERING:${vpc1}:${vpc2}:/d" "${VPC_STATE_FILE}" 2>/dev/null || true
    sed -i "/^PEERING:${vpc2}:${vpc1}:/d" "${VPC_STATE_FILE}" 2>/dev/null || true
    
    log_success "VPCs unpeered successfully"
    return 0
}

# List all peerings
list_peerings() {
    if [[ ! -f "${VPC_STATE_FILE}" ]] || ! grep -q "^PEERING:" "${VPC_STATE_FILE}" 2>/dev/null; then
        echo "No VPC peerings found"
        return
    fi
    
    grep "^PEERING:" "${VPC_STATE_FILE}" | while IFS=: read -r _ vpc1 vpc2 veth1 veth2 timestamp; do
        echo "Peering: $vpc1 <-> $vpc2"
        echo "  Veth pair: $veth1 <-> $veth2"
        echo "  Created: $(date -d @$timestamp '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $timestamp '+%Y-%m-%d %H:%M:%S')"
        echo ""
    done
}

# Command handlers
cmd_peer_vpcs() {
    local vpc1=""
    local vpc2=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vpc1)
                vpc1="$2"
                shift 2
                ;;
            --vpc2)
                vpc2="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    peer_vpcs "$vpc1" "$vpc2"
}

cmd_unpeer_vpcs() {
    local vpc1=""
    local vpc2=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vpc1)
                vpc1="$2"
                shift 2
                ;;
            --vpc2)
                vpc2="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    unpeer_vpcs "$vpc1" "$vpc2"
}

cmd_list_peerings() {
    list_peerings
}
