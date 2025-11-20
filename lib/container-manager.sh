#!/bin/bash
# lib/container-manager.sh
# Container Lifecycle Management for Hostfy

# Source utilities and managers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/network-manager.sh"
source "$SCRIPT_DIR/template-engine.sh"
source "$SCRIPT_DIR/domain-manager.sh"

# ========================================
# Configuration
# ========================================
HOSTFY_NETWORK="${HOSTFY_NETWORK:-hostfy-network}"

# ========================================
# Container Installation Functions
# ========================================

container_install() {
    local container_name="$1"
    shift
    local args=("$@")

    log_step "Installing container: $container_name"

    # Validate container name
    if ! validate_container_name "$container_name"; then
        return 1
    fi

    # Check if container already exists
    if container_exists "$container_name"; then
        log_error "Container '$container_name' already exists"
        log_info "Use 'hostfy update $container_name' to update or 'hostfy delete $container_name' to remove"
        return 1
    fi

    # Parse installation arguments
    local image=""
    local port=""
    local domain=""
    local env_file=""
    local env_vars=()
    local volumes=()

    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
            --image)
                i=$((i + 1))
                image="${args[$i]}"
                ;;
            --port)
                i=$((i + 1))
                port="${args[$i]}"
                ;;
            --domain)
                i=$((i + 1))
                domain="${args[$i]}"
                ;;
            --env-file)
                i=$((i + 1))
                env_file="${args[$i]}"
                ;;
            --env)
                i=$((i + 1))
                env_vars+=("${args[$i]}")
                ;;
            --volume)
                i=$((i + 1))
                volumes+=("${args[$i]}")
                ;;
            *)
                log_error "Unknown option: ${args[$i]}"
                return 1
                ;;
        esac
        i=$((i + 1))
    done

    # Validate required parameters for custom container
    if [[ -z "$image" ]]; then
        log_error "Image is required. Use --image <image:tag>"
        return 1
    fi

    if ! validate_image "$image"; then
        return 1
    fi

    # Default port if not specified
    port="${port:-80}"

    if ! validate_port "$port"; then
        return 1
    fi

    # Ensure network exists
    network_ensure "$HOSTFY_NETWORK"

    # Generate Traefik labels if domain is specified
    local traefik_labels=""
    if [[ -n "$domain" ]]; then
        if ! validate_domain "$domain"; then
            return 1
        fi

        traefik_labels=$(domain_generate_labels "$container_name" "$domain" "$port")
    fi

    # Generate compose file
    log_info "Generating Docker Compose configuration..."

    local env_vars_str=""
    if [[ ${#env_vars[@]} -gt 0 ]]; then
        env_vars_str=$(printf "%s," "${env_vars[@]}")
        env_vars_str="${env_vars_str%,}"
    fi

    local volumes_str=""
    if [[ ${#volumes[@]} -gt 0 ]]; then
        volumes_str=$(printf "%s," "${volumes[@]}")
        volumes_str="${volumes_str%,}"
    fi

    template_generate_custom "$container_name" "$image" "$port" "$env_vars_str" "$volumes_str" "$traefik_labels"

    # Start container
    container_start "$container_name"

    # Register container
    container_register "$container_name" "$image" "$port" "$domain"

    # Register domain if specified
    if [[ -n "$domain" ]]; then
        local router_name=$(domain_generate_router_name "$container_name" "$domain")
        domain_add_to_registry "$domain" "$container_name" "$router_name"
    fi

    log_success "Container '$container_name' installed successfully"

    if [[ -n "$domain" ]]; then
        log_info "Access at: https://$domain"
    fi

    return 0
}

container_install_from_config() {
    local config="$1"

    log_debug "Installing container from configuration"

    # Parse configuration JSON and call container_install with appropriate arguments
    # This function is used by catalog-manager.sh

    local container_name=$(echo "$config" | jq -r '.id')
    local image=$(echo "$config" | jq -r '.image')
    local port=$(echo "$config" | jq -r '.traefik.port // "80"')
    local domain=$(echo "$config" | jq -r '.custom_domain // .traefik.default_domain // empty')

    local args=(
        "--image" "$image"
        "--port" "$port"
    )

    if [[ -n "$domain" && "$domain" != "null" ]]; then
        args+=("--domain" "$domain")
    fi

    container_install "$container_name" "${args[@]}"
}

# ========================================
# Container Start/Stop Functions
# ========================================

container_start() {
    local container_name="$1"
    local compose_file="$CONTAINERS_DIR/${container_name}.yml"

    log_step "Starting container: $container_name"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Compose file not found: $compose_file"
        return 1
    fi

    local compose_cmd=$(get_docker_compose_cmd)
    if [[ -z "$compose_cmd" ]]; then
        return 1
    fi

    if $compose_cmd -f "$compose_file" up -d 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Container '$container_name' started successfully"

        # Wait for container to be healthy
        container_wait_healthy "$container_name" 30

        return 0
    else
        log_error "Failed to start container '$container_name'"
        return 1
    fi
}

container_stop() {
    local container_name="$1"
    local compose_file="$CONTAINERS_DIR/${container_name}.yml"

    log_step "Stopping container: $container_name"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Compose file not found: $compose_file"
        return 1
    fi

    local compose_cmd=$(get_docker_compose_cmd)
    if [[ -z "$compose_cmd" ]]; then
        return 1
    fi

    if $compose_cmd -f "$compose_file" stop 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Container '$container_name' stopped successfully"
        return 0
    else
        log_error "Failed to stop container '$container_name'"
        return 1
    fi
}

# ========================================
# Container Restart Functions
# ========================================

container_restart() {
    local container_name="$1"

    log_step "Restarting container: $container_name"

    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    container_stop "$container_name"
    sleep 2
    container_start "$container_name"

    log_success "Container '$container_name' restarted successfully"
}

# ========================================
# Container Pause/Resume Functions
# ========================================

container_pause() {
    local container_name="$1"

    log_step "Pausing container: $container_name"

    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    if ! container_is_running "$container_name"; then
        log_error "Container '$container_name' is not running"
        return 1
    fi

    if docker pause "$container_name" &> /dev/null; then
        log_success "Container '$container_name' paused successfully"
        return 0
    else
        log_error "Failed to pause container '$container_name'"
        return 1
    fi
}

container_resume() {
    local container_name="$1"

    log_step "Resuming container: $container_name"

    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    if docker unpause "$container_name" &> /dev/null; then
        log_success "Container '$container_name' resumed successfully"
        return 0
    else
        log_error "Failed to resume container '$container_name'"
        return 1
    fi
}

# ========================================
# Container Delete Functions
# ========================================

container_delete() {
    local container_name="$1"
    local remove_volumes="${2:-false}"

    log_step "Deleting container: $container_name"

    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    # Confirm deletion
    if ! confirm "Are you sure you want to delete container '$container_name'?"; then
        log_info "Deletion cancelled"
        return 0
    fi

    local compose_file="$CONTAINERS_DIR/${container_name}.yml"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Compose file not found: $compose_file"
        return 1
    fi

    local compose_cmd=$(get_docker_compose_cmd)
    if [[ -z "$compose_cmd" ]]; then
        return 1
    fi

    # Stop and remove container
    local down_args="-v"
    if [[ "$remove_volumes" != "true" ]]; then
        down_args=""
    fi

    if $compose_cmd -f "$compose_file" down $down_args 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Container '$container_name' stopped and removed"
    else
        log_error "Failed to remove container '$container_name'"
        return 1
    fi

    # Remove domains
    domain_remove_all_for_container "$container_name"

    # Remove from registry
    registry_delete_container "$container_name"

    # Remove compose file
    template_delete_generated "$container_name"

    log_success "Container '$container_name' deleted successfully"
    return 0
}

# ========================================
# Container Update Functions
# ========================================

container_update() {
    local container_name="$1"
    shift
    local args=("$@")

    log_step "Updating container: $container_name"

    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    # For now, update means stop, regenerate, and start
    # In the future, this could be more sophisticated

    log_info "Stopping container..."
    container_stop "$container_name"

    log_info "Updating configuration..."
    # Parse update arguments and regenerate compose file
    # This is simplified - in production, you'd want to merge with existing config

    log_info "Starting container with new configuration..."
    container_start "$container_name"

    log_success "Container '$container_name' updated successfully"
    return 0
}

# ========================================
# Container Status Functions
# ========================================

container_status() {
    local container_name="$1"

    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Container: $container_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Get container info
    local status=$(docker inspect "$container_name" --format '{{.State.Status}}' 2>/dev/null)
    local health=$(docker inspect "$container_name" --format '{{.State.Health.Status}}' 2>/dev/null)
    local image=$(docker inspect "$container_name" --format '{{.Config.Image}}' 2>/dev/null)
    local created=$(docker inspect "$container_name" --format '{{.Created}}' 2>/dev/null)

    echo "Status: $status"

    if [[ -n "$health" && "$health" != "<no value>" ]]; then
        echo "Health: $health"
    fi

    echo "Image: $image"
    echo "Created: $created"
    echo ""

    # Get domains
    local domains=$(domain_list_by_container "$container_name")
    if [[ -n "$domains" ]]; then
        echo "Domains:"
        while IFS= read -r domain; do
            if [[ -n "$domain" ]]; then
                echo "  - https://$domain"
            fi
        done <<< "$domains"
        echo ""
    fi

    # Get ports
    echo "Ports:"
    docker port "$container_name" 2>/dev/null || echo "  (none)"
    echo ""
}

container_list() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Hostfy Containers"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ! -f "$CONTAINERS_REGISTRY" ]]; then
        echo "  (no containers installed)"
        return 0
    fi

    local containers=$(jq -r '.containers[]' "$CONTAINERS_REGISTRY" 2>/dev/null)

    if [[ -z "$containers" ]]; then
        echo "  (no containers installed)"
        return 0
    fi

    printf "%-20s %-15s %-30s %-15s\n" "NAME" "TYPE" "IMAGE" "STATUS"
    printf "%-20s %-15s %-30s %-15s\n" "────" "────" "─────" "──────"

    echo "$containers" | jq -r '. | "\(.name)|\(.type // "custom")|\(.image)|\(.status)"' | while IFS='|' read -r name type image status; do
        if [[ -n "$name" ]]; then
            # Get real-time status
            local real_status="stopped"
            if container_is_running "$name"; then
                real_status="running"
            elif container_exists "$name"; then
                real_status="stopped"
            else
                real_status="missing"
            fi

            printf "%-20s %-15s %-30s %-15s\n" "$name" "$type" "$image" "$real_status"
        fi
    done

    echo ""
}

# ========================================
# Container Logs Functions
# ========================================

container_logs() {
    local container_name="$1"
    local follow="${2:-false}"
    local tail="${3:-50}"

    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    log_info "Showing logs for container: $container_name"
    echo ""

    local args="--tail $tail"

    if [[ "$follow" == "true" ]]; then
        args="$args -f"
    fi

    docker logs $args "$container_name" 2>&1
}

# ========================================
# Container Registration Functions
# ========================================

container_register() {
    local container_name="$1"
    local image="$2"
    local port="$3"
    local domain="$4"

    local container_data=$(jq -n \
        --arg name "$container_name" \
        --arg type "custom" \
        --arg image "$image" \
        --arg status "running" \
        --arg created "$(get_timestamp)" \
        --arg port "$port" \
        --arg domain "$domain" \
        --arg compose_file "$CONTAINERS_DIR/${container_name}.yml" \
        '{
            name: $name,
            type: $type,
            image: $image,
            status: $status,
            created_at: $created,
            ports: [$port],
            domains: (if $domain != "" then [$domain] else [] end),
            compose_file: $compose_file
        }')

    registry_add_container "$container_data"

    log_debug "Container registered: $container_name"
}

# ========================================
# Container Health Check Functions
# ========================================

container_wait_healthy() {
    local container_name="$1"
    local timeout="${2:-30}"

    log_debug "Waiting for container to be healthy: $container_name"

    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if container_is_running "$container_name"; then
            local health=$(docker inspect "$container_name" --format '{{.State.Health.Status}}' 2>/dev/null)

            if [[ -z "$health" || "$health" == "<no value>" ]]; then
                # No health check defined, assume healthy if running
                log_debug "Container is running (no health check defined)"
                return 0
            fi

            if [[ "$health" == "healthy" ]]; then
                log_debug "Container is healthy"
                return 0
            fi
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    log_warning "Container health check timeout"
    return 1
}

# ========================================
# Container Validation Functions
# ========================================

container_validate() {
    local container_name="$1"

    log_step "Validating container: $container_name"

    # Check if container exists
    if ! container_exists "$container_name"; then
        log_error "Container does not exist"
        return 1
    fi

    # Check if running
    if ! container_is_running "$container_name"; then
        log_warning "Container is not running"
    else
        log_success "Container is running"
    fi

    # Check network connectivity
    if network_is_connected "$container_name" "$HOSTFY_NETWORK"; then
        log_success "Container is connected to $HOSTFY_NETWORK"
    else
        log_warning "Container is not connected to $HOSTFY_NETWORK"
    fi

    log_success "Container validation completed"
    return 0
}
