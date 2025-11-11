#!/bin/bash

# firewall.sh - Security group and firewall rule management

# Apply firewall rules from JSON policy
apply_firewall_policy() {
    local policy_file=$1
    local enforce_mode=${2:-permissive}  # permissive or strict
    
    require_root
    
    if [[ ! -f "$policy_file" ]]; then
        log_error "Policy file not found: $policy_file"
        return 1
    fi
    
    log_info "Applying firewall policy from: $policy_file (mode: $enforce_mode)"
    
    # Check if jq is installed
    if ! command_exists jq; then
        log_error "jq is required for JSON parsing. Install with: sudo apt install jq"
        return 1
    fi
    
    # Parse JSON and apply rules
    local num_policies=$(jq '.policies | length' "$policy_file")
    
    for ((i=0; i<num_policies; i++)); do
        local subnet=$(jq -r ".policies[$i].subnet" "$policy_file")
        local description=$(jq -r ".policies[$i].description" "$policy_file")
        
        log_info "Applying policy for subnet $subnet: $description"
        
        # Find the namespace for this subnet
        local namespace=$(grep "^SUBNET:" "${VPC_STATE_FILE}" | grep ":${subnet}:" | cut -d: -f6)
        
        if [[ -z "$namespace" ]]; then
            log_warn "No namespace found for subnet $subnet, skipping"
            continue
        fi
        
        # In strict mode, set default policies to DROP
        if [[ "$enforce_mode" == "strict" ]]; then
            log_info "Setting strict firewall policy (default DROP)"
            ip netns exec "$namespace" iptables -P INPUT DROP 2>/dev/null || true
            ip netns exec "$namespace" iptables -P FORWARD DROP 2>/dev/null || true
            # Keep OUTPUT as ACCEPT by default unless egress rules say otherwise
            ip netns exec "$namespace" iptables -P OUTPUT ACCEPT 2>/dev/null || true
            
            # Allow established connections
            ip netns exec "$namespace" iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
            ip netns exec "$namespace" iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
            
            # Allow loopback
            ip netns exec "$namespace" iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
            ip netns exec "$namespace" iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
        fi
        
        # Apply ingress rules
        local num_ingress=$(jq ".policies[$i].ingress | length" "$policy_file")
        for ((j=0; j<num_ingress; j++)); do
            local port=$(jq -r ".policies[$i].ingress[$j].port // empty" "$policy_file")
            local protocol=$(jq -r ".policies[$i].ingress[$j].protocol // \"tcp\"" "$policy_file")
            local source=$(jq -r ".policies[$i].ingress[$j].source // \"0.0.0.0/0\"" "$policy_file")
            local action=$(jq -r ".policies[$i].ingress[$j].action // \"allow\"" "$policy_file")
            local rule_desc=$(jq -r ".policies[$i].ingress[$j].description // \"\"" "$policy_file")
            
            apply_ingress_rule "$namespace" "$port" "$protocol" "$source" "$action" "$rule_desc"
        done
        
        # Apply egress rules
        local num_egress=$(jq ".policies[$i].egress | length" "$policy_file")
        for ((j=0; j<num_egress; j++)); do
            local destination=$(jq -r ".policies[$i].egress[$j].destination // \"0.0.0.0/0\"" "$policy_file")
            local action=$(jq -r ".policies[$i].egress[$j].action // \"allow\"" "$policy_file")
            local rule_desc=$(jq -r ".policies[$i].egress[$j].description // \"\"" "$policy_file")
            
            apply_egress_rule "$namespace" "$destination" "$action" "$rule_desc"
        done
    done
    
    log_success "Firewall policy applied"
    return 0
}

# Apply a single ingress rule
apply_ingress_rule() {
    local namespace=$1
    local port=$2
    local protocol=$3
    local source=$4
    local action=$5
    local description=$6
    
    local iptables_action
    if [[ "$action" == "allow" ]]; then
        iptables_action="ACCEPT"
    else
        iptables_action="DROP"
    fi
    
    if [[ -n "$port" ]]; then
        log_info "  Ingress: $action $protocol/$port from $source - $description"
        ip netns exec "$namespace" iptables -A INPUT -p "$protocol" --dport "$port" -s "$source" -j "$iptables_action" 2>/dev/null || {
            log_warn "Failed to apply ingress rule for port $port"
        }
    fi
}

# Apply a single egress rule  
apply_egress_rule() {
    local namespace=$1
    local destination=$2
    local action=$3
    local description=$4
    
    local iptables_action
    if [[ "$action" == "allow" ]]; then
        iptables_action="ACCEPT"
    else
        iptables_action="DROP"
    fi
    
    log_info "  Egress: $action to $destination - $description"
    ip netns exec "$namespace" iptables -A OUTPUT -d "$destination" -j "$iptables_action" 2>/dev/null || {
        log_warn "Failed to apply egress rule for $destination"
    }
}

# Clear all firewall rules for a subnet
clear_firewall_rules() {
    local subnet_cidr=$1
    
    # Find namespace for this subnet
    local namespace=$(grep "^SUBNET:" "${VPC_STATE_FILE}" | grep ":${subnet_cidr}:" | cut -d: -f6)
    
    if [[ -z "$namespace" ]]; then
        log_warn "No namespace found for subnet $subnet_cidr"
        return 1
    fi
    
    log_info "Clearing firewall rules for subnet $subnet_cidr (namespace: $namespace)"
    
    # Flush all iptables rules in namespace
    ip netns exec "$namespace" iptables -F 2>/dev/null || true
    ip netns exec "$namespace" iptables -X 2>/dev/null || true
    
    log_success "Firewall rules cleared"
}

# Command handlers
cmd_apply_firewall() {
    local policy_file="${CONFIG_DIR}/security-groups.json"
    local enforce_mode="permissive"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --policy)
                policy_file="$2"
                shift 2
                ;;
            --strict)
                enforce_mode="strict"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    apply_firewall_policy "$policy_file" "$enforce_mode"
}

cmd_clear_firewall() {
    local subnet=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --subnet)
                subnet="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    clear_firewall_rules "$subnet"
}
