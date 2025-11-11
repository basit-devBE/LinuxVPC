#!/bin/bash

# subnet.sh - Subnet creation and management functions

# Create a subnet (network namespace) in a VPC
create_subnet() {
    local vpc_name=$1
    local subnet_name=$2
    local cidr=$3
    local type=$4  # "public" or "private"
    
    require_root
    
    # Validate inputs
    if [[ -z "$vpc_name" ]] || [[ -z "$subnet_name" ]] || [[ -z "$cidr" ]] || [[ -z "$type" ]]; then
        log_error "VPC name, subnet name, CIDR, and type are required"
        return 1
    fi
    
    if [[ "$type" != "public" ]] && [[ "$type" != "private" ]]; then
        log_error "Subnet type must be 'public' or 'private'"
        return 1
    fi
    
    validate_cidr "$cidr" || return 1
    
    local bridge="br-${vpc_name}"
    local namespace="${vpc_name}-${subnet_name}"
    local veth_ns="veth-${subnet_name}"
    local veth_br="veth-${subnet_name}-br"
    
    # Check if VPC exists
    if ! bridge_exists "$bridge"; then
        log_error "VPC $vpc_name does not exist (bridge $bridge not found)"
        return 1
    fi
    
    # Check if subnet already exists
    if namespace_exists "$namespace"; then
        log_error "Subnet $subnet_name already exists in VPC $vpc_name"
        return 1
    fi
    
    log_info "Creating ${type} subnet: $subnet_name in VPC: $vpc_name"
    log_info "  CIDR: $cidr"
    log_info "  Namespace: $namespace"
    
    # Create network namespace
    ip netns add "$namespace" || {
        log_error "Failed to create namespace $namespace"
        return 1
    }
    
    # Create veth pair
    ip link add "$veth_ns" type veth peer name "$veth_br" || {
        log_error "Failed to create veth pair"
        ip netns delete "$namespace"
        return 1
    }
    
    # Move one end into namespace
    ip link set "$veth_ns" netns "$namespace" || {
        log_error "Failed to move veth into namespace"
        ip link delete "$veth_br"
        ip netns delete "$namespace"
        return 1
    }
    
    # Attach other end to bridge
    ip link set "$veth_br" master "$bridge" || {
        log_error "Failed to attach veth to bridge"
        ip link delete "$veth_br"
        ip netns delete "$namespace"
        return 1
    }
    
    # Bring up bridge-side interface
    ip link set "$veth_br" up || {
        log_error "Failed to bring up bridge-side veth"
        ip link delete "$veth_br"
        ip netns delete "$namespace"
        return 1
    }
    
    # Configure namespace interface
    local host_ip=$(get_host_ip "$cidr" 10)
    ip netns exec "$namespace" ip link set lo up
    ip netns exec "$namespace" ip link set "$veth_ns" up || {
        log_error "Failed to bring up namespace veth"
        ip link delete "$veth_br"
        ip netns delete "$namespace"
        return 1
    }
    ip netns exec "$namespace" ip addr add "$host_ip" dev "$veth_ns" || {
        log_error "Failed to assign IP to namespace interface"
        ip link delete "$veth_br"
        ip netns delete "$namespace"
        return 1
    }
    
    # Add default route pointing to VPC gateway
    local vpc_cidr=$(grep "^VPC:${vpc_name}:" "${VPC_STATE_FILE}" 2>/dev/null | cut -d: -f3)
    if [[ -z "$vpc_cidr" ]]; then
        log_error "Could not find VPC $vpc_name in state file"
        ip link delete "$veth_br"
        ip netns delete "$namespace"
        return 1
    fi
    
    local gateway_ip=$(get_gateway_ip "$vpc_cidr")
    local gateway_ip_only=$(echo "$gateway_ip" | cut -d'/' -f1)
    
    # Add route to VPC network first (so gateway is reachable)
    ip netns exec "$namespace" ip route add "$vpc_cidr" dev "$veth_ns" || {
        log_error "Failed to add route to VPC network"
        ip link delete "$veth_br"
        ip netns delete "$namespace"
        return 1
    }
    
    # Then add default route via gateway
    ip netns exec "$namespace" ip route add default via "$gateway_ip_only" || {
        log_error "Failed to add default route"
        ip link delete "$veth_br"
        ip netns delete "$namespace"
        return 1
    }
    
    # If public subnet, enable NAT and DNS
    if [[ "$type" == "public" ]]; then
        enable_nat_for_subnet "$cidr"
        
        # Configure DNS for namespace (use Google DNS)
        mkdir -p /etc/netns/"$namespace"
        cat > /etc/netns/"$namespace"/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    fi
    
    # Save subnet state
    save_subnet_state "$vpc_name" "$subnet_name" "$cidr" "$type" "$namespace"
    
    log_success "Subnet $subnet_name created successfully"
    log_info "  Type: $type"
    log_info "  Host IP: $host_ip"
    log_info "  Gateway: $gateway_ip_only"
    
    return 0
}

# Delete a subnet
delete_subnet() {
    local vpc_name=$1
    local subnet_name=$2
    
    require_root
    
    local namespace="${vpc_name}-${subnet_name}"
    local veth_br="veth-${subnet_name}-br"
    
    if ! namespace_exists "$namespace"; then
        log_warn "Subnet $subnet_name does not exist in VPC $vpc_name"
        return 0
    fi
    
    log_info "Deleting subnet: $subnet_name from VPC: $vpc_name"
    
    # Delete veth interface (this also removes it from bridge and namespace)
    ip link delete "$veth_br" 2>/dev/null || true
    
    # Delete namespace
    ip netns delete "$namespace" || {
        log_error "Failed to delete namespace $namespace"
        return 1
    }
    
    # Remove subnet state
    sed -i "/^SUBNET:${vpc_name}:${subnet_name}:/d" "${VPC_STATE_FILE}"
    
    log_success "Subnet $subnet_name deleted successfully"
    return 0
}

# Enable NAT for a subnet
enable_nat_for_subnet() {
    local subnet_cidr=$1
    local internet_iface=$(get_internet_interface)
    
    if [[ -z "$internet_iface" ]]; then
        log_error "Could not determine internet interface"
        return 1
    fi
    
    log_info "Enabling NAT for subnet $subnet_cidr via $internet_iface"
    
    # Add NAT rule
    iptables -t nat -A POSTROUTING -s "$subnet_cidr" -o "$internet_iface" -j MASQUERADE || {
        log_error "Failed to add NAT rule"
        return 1
    }
    
    # Allow forwarding
    iptables -A FORWARD -s "$subnet_cidr" -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -d "$subnet_cidr" -j ACCEPT 2>/dev/null || true
    
    return 0
}

# Command handlers
cmd_add_subnet() {
    local vpc_name=""
    local subnet_name=""
    local cidr=""
    local type=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vpc)
                vpc_name="$2"
                shift 2
                ;;
            --name)
                subnet_name="$2"
                shift 2
                ;;
            --cidr)
                cidr="$2"
                shift 2
                ;;
            --type)
                type="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    create_subnet "$vpc_name" "$subnet_name" "$cidr" "$type"
}

cmd_delete_subnet() {
    local vpc_name=""
    local subnet_name=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vpc)
                vpc_name="$2"
                shift 2
                ;;
            --name)
                subnet_name="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    delete_subnet "$vpc_name" "$subnet_name"
}

cmd_list_subnets() {
    local vpc_name="$1"
    
    if [[ ! -f "${VPC_STATE_FILE}" ]]; then
        echo "No subnets found"
        return
    fi
    
    if [[ -n "$vpc_name" ]]; then
        grep "^SUBNET:${vpc_name}:" "${VPC_STATE_FILE}" | while IFS=: read -r _ vpc subnet cidr type namespace timestamp; do
            echo "Subnet: $subnet"
            echo "  VPC: $vpc"
            echo "  CIDR: $cidr"
            echo "  Type: $type"
            echo "  Namespace: $namespace"
            echo "  Created: $(date -d @$timestamp '+%Y-%m-%d %H:%M:%S')"
            echo ""
        done
    else
        grep "^SUBNET:" "${VPC_STATE_FILE}" | while IFS=: read -r _ vpc subnet cidr type namespace timestamp; do
            echo "Subnet: $subnet"
            echo "  VPC: $vpc"
            echo "  CIDR: $cidr"
            echo "  Type: $type"
            echo "  Namespace: $namespace"
            echo "  Created: $(date -d @$timestamp '+%Y-%m-%d %H:%M:%S')"
            echo ""
        done
    fi
}