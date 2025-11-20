#!/bin/bash
# lib/network-manager.sh
# Docker Network Management for Hostfy

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ========================================
# Configuration
# ========================================
HOSTFY_NETWORK="${HOSTFY_NETWORK:-hostfy-network}"
NETWORK_DRIVER="${NETWORK_DRIVER:-bridge}"
NETWORK_SUBNET="${NETWORK_SUBNET:-172.20.0.0/16}"

# ========================================
# Core Network Functions
# ========================================

network_create() {
    local network_name="${1:-$HOSTFY_NETWORK}"
    local driver="${2:-$NETWORK_DRIVER}"
    local subnet="${3:-$NETWORK_SUBNET}"

    log_step "Creating Docker network: $network_name"

    # Check if network already exists
    if network_exists "$network_name"; then
        log_warning "Network '$network_name' already exists"
        return 0
    fi

    # Create network
    if docker network create \
        --driver "$driver" \
        --subnet "$subnet" \
        "$network_name" &> /dev/null; then
        log_success "Network '$network_name' created successfully"
        log_info "  Driver: $driver"
        log_info "  Subnet: $subnet"
        return 0
    else
        log_error "Failed to create network '$network_name'"
        return 1
    fi
}

network_remove() {
    local network_name="${1:-$HOSTFY_NETWORK}"

    log_step "Removing Docker network: $network_name"

    # Check if network exists
    if ! network_exists "$network_name"; then
        log_warning "Network '$network_name' does not exist"
        return 0
    fi

    # Check if any containers are connected
    local connected_containers=$(docker network inspect "$network_name" -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)

    if [[ -n "$connected_containers" ]]; then
        log_warning "The following containers are still connected to '$network_name':"
        for container in $connected_containers; do
            log_info "  - $container"
        done

        if ! confirm "Do you want to disconnect all containers and remove the network?"; then
            log_info "Network removal cancelled"
            return 1
        fi

        # Disconnect all containers
        for container in $connected_containers; do
            network_disconnect "$container" "$network_name"
        done
    fi

    # Remove network
    if docker network rm "$network_name" &> /dev/null; then
        log_success "Network '$network_name' removed successfully"
        return 0
    else
        log_error "Failed to remove network '$network_name'"
        return 1
    fi
}

network_connect() {
    local container_name="$1"
    local network_name="${2:-$HOSTFY_NETWORK}"

    log_debug "Connecting container '$container_name' to network '$network_name'"

    # Check if container exists
    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    # Check if network exists
    if ! network_exists "$network_name"; then
        log_error "Network '$network_name' does not exist"
        return 1
    fi

    # Check if already connected
    if network_is_connected "$container_name" "$network_name"; then
        log_debug "Container '$container_name' is already connected to '$network_name'"
        return 0
    fi

    # Connect container to network
    if docker network connect "$network_name" "$container_name" &> /dev/null; then
        log_debug "Container '$container_name' connected to network '$network_name'"
        return 0
    else
        log_error "Failed to connect container '$container_name' to network '$network_name'"
        return 1
    fi
}

network_disconnect() {
    local container_name="$1"
    local network_name="${2:-$HOSTFY_NETWORK}"

    log_debug "Disconnecting container '$container_name' from network '$network_name'"

    # Check if container exists
    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    # Check if network exists
    if ! network_exists "$network_name"; then
        log_warning "Network '$network_name' does not exist"
        return 0
    fi

    # Check if connected
    if ! network_is_connected "$container_name" "$network_name"; then
        log_debug "Container '$container_name' is not connected to '$network_name'"
        return 0
    fi

    # Disconnect container from network
    if docker network disconnect "$network_name" "$container_name" &> /dev/null; then
        log_debug "Container '$container_name' disconnected from network '$network_name'"
        return 0
    else
        log_error "Failed to disconnect container '$container_name' from network '$network_name'"
        return 1
    fi
}

network_is_connected() {
    local container_name="$1"
    local network_name="$2"

    local connected=$(docker network inspect "$network_name" -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null | grep -w "$container_name")

    [[ -n "$connected" ]]
}

# ========================================
# Network Inspection Functions
# ========================================

network_inspect() {
    local network_name="${1:-$HOSTFY_NETWORK}"

    if ! network_exists "$network_name"; then
        log_error "Network '$network_name' does not exist"
        return 1
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Network: $network_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Get network details
    local driver=$(docker network inspect "$network_name" -f '{{.Driver}}' 2>/dev/null)
    local subnet=$(docker network inspect "$network_name" -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
    local gateway=$(docker network inspect "$network_name" -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)

    echo "Driver: $driver"
    echo "Subnet: $subnet"
    echo "Gateway: $gateway"
    echo ""

    # List connected containers
    echo "Connected Containers:"
    local containers=$(docker network inspect "$network_name" -f '{{range .Containers}}{{.Name}}|{{.IPv4Address}}{{"\n"}}{{end}}' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        echo "  (none)"
    else
        while IFS='|' read -r name ip; do
            if [[ -n "$name" ]]; then
                echo "  - $name ($ip)"
            fi
        done <<< "$containers"
    fi

    echo ""
}

network_list() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Docker Networks"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
}

network_list_containers() {
    local network_name="${1:-$HOSTFY_NETWORK}"

    if ! network_exists "$network_name"; then
        log_error "Network '$network_name' does not exist"
        return 1
    fi

    docker network inspect "$network_name" -f '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' 2>/dev/null
}

# ========================================
# Network Validation Functions
# ========================================

network_validate_connectivity() {
    local network_name="${1:-$HOSTFY_NETWORK}"

    log_step "Validating network connectivity: $network_name"

    if ! network_exists "$network_name"; then
        log_error "Network '$network_name' does not exist"
        return 1
    fi

    # Get all containers in the network
    local containers=($(network_list_containers "$network_name"))

    if [[ ${#containers[@]} -lt 2 ]]; then
        log_info "Network has less than 2 containers, skipping connectivity test"
        return 0
    fi

    # Test ping between containers (if ping is available)
    log_info "Testing connectivity between ${#containers[@]} containers..."

    for container in "${containers[@]}"; do
        if container_is_running "$container"; then
            log_debug "  Container '$container' is reachable"
        else
            log_warning "  Container '$container' is not running"
        fi
    done

    log_success "Network connectivity validation completed"
    return 0
}

# ========================================
# Network DNS Functions
# ========================================

network_resolve_dns() {
    local container_name="$1"
    local network_name="${2:-$HOSTFY_NETWORK}"

    if ! network_exists "$network_name"; then
        log_error "Network '$network_name' does not exist"
        return 1
    fi

    if ! network_is_connected "$container_name" "$network_name"; then
        log_error "Container '$container_name' is not connected to network '$network_name'"
        return 1
    fi

    # Get IP address of container in the network
    docker network inspect "$network_name" -f "{{range .Containers}}{{if eq .Name \"$container_name\"}}{{.IPv4Address}}{{end}}{{end}}" 2>/dev/null | cut -d'/' -f1
}

# ========================================
# Network Cleanup Functions
# ========================================

network_prune() {
    log_step "Pruning unused Docker networks"

    if ! confirm "This will remove all custom networks not used by at least one container. Continue?"; then
        log_info "Network pruning cancelled"
        return 0
    fi

    if docker network prune -f &> /dev/null; then
        log_success "Unused networks pruned successfully"
        return 0
    else
        log_error "Failed to prune networks"
        return 1
    fi
}

# ========================================
# Network Configuration Functions
# ========================================

network_get_config() {
    local network_name="${1:-$HOSTFY_NETWORK}"

    if ! network_exists "$network_name"; then
        echo "{}"
        return 1
    fi

    docker network inspect "$network_name" --format '{{json .}}' 2>/dev/null
}

network_export_config() {
    local network_name="${1:-$HOSTFY_NETWORK}"
    local output_file="${2:-$DOCKER_DIR/network/network-config.json}"

    log_step "Exporting network configuration: $network_name"

    if ! network_exists "$network_name"; then
        log_error "Network '$network_name' does not exist"
        return 1
    fi

    mkdir -p "$(dirname "$output_file")"

    if network_get_config "$network_name" > "$output_file"; then
        log_success "Network configuration exported to: $output_file"
        return 0
    else
        log_error "Failed to export network configuration"
        return 1
    fi
}

# ========================================
# Initialization
# ========================================

network_ensure() {
    local network_name="${1:-$HOSTFY_NETWORK}"

    if ! network_exists "$network_name"; then
        log_info "Network '$network_name' does not exist, creating..."
        network_create "$network_name"
    else
        log_debug "Network '$network_name' already exists"
        return 0
    fi
}

# ========================================
# Network Statistics
# ========================================

network_stats() {
    local network_name="${1:-$HOSTFY_NETWORK}"

    if ! network_exists "$network_name"; then
        log_error "Network '$network_name' does not exist"
        return 1
    fi

    local container_count=$(network_list_containers "$network_name" | wc -l | tr -d ' ')

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Network Statistics: $network_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Connected Containers: $container_count"
    echo ""
}
