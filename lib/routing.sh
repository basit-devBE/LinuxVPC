#!/bin/bash

# routing.sh - Routing and NAT gateway configuration

# Most routing is handled automatically in subnet.sh during subnet creation
# This file contains advanced routing functions

# Show routing table for a subnet
show_subnet_routes() {
    local vpc_name=$1
    local subnet_name=$2
    
    if [[ -z "$vpc_name" ]] || [[ -z "$subnet_name" ]]; then
        log_error "VPC name and subnet name are required"
        return 1
    fi
    
    local namespace="${vpc_name}-${subnet_name}"
    
    if ! namespace_exists "$namespace"; then
        log_error "Subnet $subnet_name does not exist in VPC $vpc_name"
        return 1
    fi
    
    echo "=== Routing table for ${vpc_name}/${subnet_name} ==="
    ip netns exec "$namespace" ip route
    echo ""
    echo "=== IP addresses ==="
    ip netns exec "$namespace" ip addr show
}

# Add custom route to a subnet
add_custom_route() {
    local vpc_name=$1
    local subnet_name=$2
    local destination=$3
    local via=$4
    
    require_root
    
    if [[ -z "$vpc_name" ]] || [[ -z "$subnet_name" ]] || [[ -z "$destination" ]] || [[ -z "$via" ]]; then
        log_error "Usage: add_custom_route <vpc> <subnet> <destination> <gateway>"
        return 1
    fi
    
    local namespace="${vpc_name}-${subnet_name}"
    
    if ! namespace_exists "$namespace"; then
        log_error "Subnet $subnet_name does not exist in VPC $vpc_name"
        return 1
    fi
    
    log_info "Adding route to $destination via $via in ${vpc_name}/${subnet_name}"
    
    ip netns exec "$namespace" ip route add "$destination" via "$via" || {
        log_error "Failed to add route"
        return 1
    }
    
    log_success "Route added successfully"
}

# Delete custom route from a subnet
delete_custom_route() {
    local vpc_name=$1
    local subnet_name=$2
    local destination=$3
    
    require_root
    
    local namespace="${vpc_name}-${subnet_name}"
    
    if ! namespace_exists "$namespace"; then
        log_error "Subnet $subnet_name does not exist in VPC $vpc_name"
        return 1
    fi
    
    log_info "Deleting route to $destination from ${vpc_name}/${subnet_name}"
    
    ip netns exec "$namespace" ip route del "$destination" || {
        log_error "Failed to delete route"
        return 1
    }
    
    log_success "Route deleted successfully"
}

# Show NAT rules
show_nat_rules() {
    require_root
    
    echo "=== NAT Rules (POSTROUTING) ==="
    iptables -t nat -L POSTROUTING -n -v --line-numbers
    echo ""
    echo "=== Forward Rules ==="
    iptables -L FORWARD -n -v --line-numbers
}

# Test connectivity from a subnet
test_connectivity() {
    local vpc_name=$1
    local subnet_name=$2
    local target=${3:-8.8.8.8}
    
    if [[ -z "$vpc_name" ]] || [[ -z "$subnet_name" ]]; then
        log_error "VPC name and subnet name are required"
        return 1
    fi
    
    local namespace="${vpc_name}-${subnet_name}"
    
    if ! namespace_exists "$namespace"; then
        log_error "Subnet $subnet_name does not exist in VPC $vpc_name"
        return 1
    fi
    
    echo "Testing connectivity from ${vpc_name}/${subnet_name} to $target..."
    
    if ip netns exec "$namespace" ping -c 3 -W 2 "$target"; then
        echo "✓ Connectivity to $target: SUCCESS"
        return 0
    else
        echo "✗ Connectivity to $target: FAILED"
        return 1
    fi
}

# Command handlers
cmd_show_routes() {
    local vpc_name=""
    local subnet_name=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vpc)
                vpc_name="$2"
                shift 2
                ;;
            --subnet)
                subnet_name="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    show_subnet_routes "$vpc_name" "$subnet_name"
}

cmd_show_nat() {
    show_nat_rules
}

cmd_test_connectivity() {
    local vpc_name=""
    local subnet_name=""
    local target="8.8.8.8"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vpc)
                vpc_name="$2"
                shift 2
                ;;
            --subnet)
                subnet_name="$2"
                shift 2
                ;;
            --target)
                target="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    test_connectivity "$vpc_name" "$subnet_name" "$target"
}
