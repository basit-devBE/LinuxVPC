#!/bin/bash

LOG_FILE="${LOG_DIR}/vpcctl.log"

init_logging() {
    # Initialize logging system
    mkdir -p "${LOG_DIR}"
    touch "${LOG_FILE}"
    echo "Logging initialized at $(date)" >> "${LOG_FILE}"
}

log_info(){
    local msg="$1"
    echo "[INFO] $msg"  # Print to console
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $msg" >> "${LOG_FILE}"
}

log_warn(){
    local msg="$1"
    echo "[WARN] $msg"  # Print to console
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $msg" >> "${LOG_FILE}"
}

log_error(){
    local msg="$1"
    echo "[ERROR] $msg" >&2  # Print to console (stderr)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >> "${LOG_FILE}"
}

log_success(){
    local msg="$1"
    echo "[✓] $msg"  # Print to console
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $msg" >> "${LOG_FILE}"
}

require_root(){
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

command_exists(){
    command -v "$1" >/dev/null 2>&1
}

#Validate Ip Address or CIDR block formats
validate_cidr(){
     local cidr=$1
    if [[ ! $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Invalid CIDR format: $cidr"
        return 1
    fi
    return 0
}

get_gateway_ip(){
    local cidr=$1
    local ip_prefix
    local netmask
    ip_prefix=$(echo "$cidr" | cut -d'/' -f1 | cut -d'.' -f1-3)
    netmask=$(echo "$cidr" | cut -d'/' -f2)
    echo "${ip_prefix}.1/${netmask}"
}
get_host_ip(){
     local cidr=$1
    local host_num=$2
    local ip_prefix
    local netmask
    ip_prefix=$(echo "$cidr" | cut -d'/' -f1 | cut -d'.' -f1-3)
    netmask=$(echo "$cidr" | cut -d'/' -f2)
    echo "${ip_prefix}.${host_num}/${netmask}"
}


#check if bridge exists
bridge_exists(){
    local bridge_name=$1
    if ip link show "$bridge_name" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

#check if namespace exists
namespace_exists(){
    local ns_name=$1
    if ip netns list | grep -qw "$ns_name"; then
        return 0
    else
        return 1
    fi
}

get_internet_interface() {
    ip route | grep default | awk '{print $5}' | head -n1
}

save_vpc_state(){
    local vpc_name=$1
    local cidr=$2
    local bridge_name=$3

    touch "${VPC_STATE_FILE}"

    if grep -q "^VPC:${vpc_name}:" "${VPC_STATE_FILE}"; then
       log_warn "VPC $vpc_name already exists in state file"
       return 1
    fi

    echo "VPC:${vpc_name}:${cidr}:${bridge_name}:$(date +%s)" >> "${VPC_STATE_FILE}"
    log_info "Saved VPC $vpc_name state"
}

remove_vpc_state(){
    local vpc_name=$1

    if [[ ! -f "${VPC_STATE_FILE}" ]]; then
        log_warn "VPC state file does not exist"
        return 0
    fi

    # remove VPC entry from state file
    sed -i "/^VPC:${vpc_name}:/d" "${VPC_STATE_FILE}"
    sed -i "/^SUBNET:${vpc_name}:/d" "${VPC_STATE_FILE}"
    log_info "Removed VPC $vpc_name from state file"
}

save_subnet_state() {
    local vpc_name=$1
    local subnet_name=$2
    local cidr=$3
    local type=$4
    local namespace=$5
    
    touch "${VPC_STATE_FILE}"
    echo "SUBNET:${vpc_name}:${subnet_name}:${cidr}:${type}:${namespace}:$(date +%s)" >> "${VPC_STATE_FILE}"
    log_info "Subnet state saved: $subnet_name in $vpc_name"
}

list_all_vpcs(){
     if [[ ! -f "${VPC_STATE_FILE}" ]]; then
        echo "No VPCs found"
        return
    fi
    
    grep "^VPC:" "${VPC_STATE_FILE}" | while IFS=: read -r _ name cidr bridge timestamp; do
        echo "VPC: $name"
        echo "  CIDR: $cidr"
        echo "  Bridge: $bridge"
        echo "  Created: $(date -d @$timestamp '+%Y-%m-%d %H:%M:%S')"
        echo ""
    done

}

parse_args() {
     local options=$1
    shift
    
    if ! PARSED=$(getopt -o "" -l "$options" -n "vpcctl" -- "$@"); then
        return 1
    fi
    eval set -- "$PARSED"
    echo "$PARSED"
}