#!/bin/bash

create_vpc(){
    local vpc_name=$1
    local cidr=$2

    require_root

    #validation of inouts
    if [[ -z $vpc_name || -z $cidr ]]; then
        log_error "VPC name and CIDR block are required"
        return 1
    fi

    validate_cidr "$cidr" || return 1

    local bridge="br-${vpc_name}"

    if bridge_exists "$bridge"; then
        log_error "VPC $vpc_name already exists (bridge $bridge found)"
        return 1
    fi

    log_info "Creating VPC '$vpc_name' with CIDR '$cidr'"

    #Create the Bridge now
    ip link add "$bridge" type bridge || {
        log_error "Failed to create bridge $bridge"
        return 1
    }

    #Bring the Bridge up
    ip link set "$bridge" up || {
        log_error "Failed to bring bridge $bridge up"
        ip link delete "$bridge" || true
        return 1
    }

    #Assign an IP to the bridge (using the first IP in the CIDR as gateway)
    ip addr add "$(get_gateway_ip "$cidr")" dev "$bridge" || {
        log_error "Failed to assign IP to bridge $bridge"
        ip link delete "$bridge" || true
        return 1
    }

    #Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    save_vpc_state "$vpc_name" "$cidr" "$bridge"

    log_success "VPC $vpc_name created successfully"
    log_info "Bridge: $bridge, CIDR: $cidr"
    log_info "Gateway IP: $(get_gateway_ip "$cidr")"

    return 0
}
# Creation of VPC command handler
cmd_create_vpc() {
    local vpc_name=""
    local cidr=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                vpc_name="$2"
                shift 2
                ;;
            --cidr)
                cidr="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    create_vpc "$vpc_name" "$cidr"
}

delete_vpc() {
    local vpc_name=$1
    
    require_root
    
    if [[ -z "$vpc_name" ]]; then
        log_error "VPC name is required"
        return 1
    fi
    
    local bridge="br-${vpc_name}"
    
    if ! bridge_exists "$bridge"; then
        log_warn "VPC $vpc_name does not exist (bridge $bridge not found)"
        remove_vpc_state "$vpc_name"
        return 0
    fi
    
    log_info "Deleting VPC: $vpc_name"
    
    # Delete all subnets first (if delete_subnet function exists)
    if [[ -f "${VPC_STATE_FILE}" ]]; then
        if declare -f delete_subnet >/dev/null 2>&1; then
            grep "^SUBNET:${vpc_name}:" "${VPC_STATE_FILE}" 2>/dev/null | while IFS=: read -r _ _ subnet_name _; do
                log_info "Deleting subnet: $subnet_name"
                delete_subnet "$vpc_name" "$subnet_name" 2>/dev/null || true
            done
        else
            # Just remove subnet entries from state file if function doesn't exist
            sed -i "/^SUBNET:${vpc_name}:/d" "${VPC_STATE_FILE}" 2>/dev/null || true
        fi
    fi
    
    # Remove NAT rules for this VPC
    local cidr
    cidr=$(grep "^VPC:${vpc_name}:" "${VPC_STATE_FILE}" 2>/dev/null | cut -d: -f3)
    if [[ -n "$cidr" ]]; then
        local internet_iface
        internet_iface=$(get_internet_interface)
        iptables -t nat -D POSTROUTING -s "$cidr" -o "$internet_iface" -j MASQUERADE 2>/dev/null || true
    fi
    
    # Remove bridge
    ip link delete "$bridge" || {
        log_error "Failed to delete bridge $bridge"
        return 1
    }
    
    # Remove VPC state
    remove_vpc_state "$vpc_name"
    
    log_success "VPC $vpc_name deleted successfully"
    return 0
}

cmd_delete_vpc() {
    local vpc_name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                vpc_name="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    delete_vpc "$vpc_name"
}

cmd_list_vpcs() {
    list_all_vpcs
}

cmd_show_status() {
    require_root
    
    echo "=== VPC Status ==="
    echo ""
    
    # List all bridges
    echo "Bridges:"
    ip -br link show type bridge
    echo ""
    
    # List all namespaces
    echo "Network Namespaces:"
    ip netns list
    echo ""
    
    # Show state file
    echo "=== Configured VPCs ==="
    list_all_vpcs
}