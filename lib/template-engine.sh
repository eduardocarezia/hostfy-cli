#!/bin/bash
# lib/template-engine.sh
# Template Engine for Docker Compose YAML Generation

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ========================================
# Configuration
# ========================================
TEMPLATES_DIR="${TEMPLATES_DIR:-$DOCKER_DIR/templates}"
CONTAINERS_DIR="${CONTAINERS_DIR:-$DOCKER_DIR/containers}"

# ========================================
# Template Loading Functions
# ========================================

template_load() {
    local template_name="$1"
    local template_file="$TEMPLATES_DIR/${template_name}.yml"

    log_debug "Loading template: $template_name"

    if [[ ! -f "$template_file" ]]; then
        log_error "Template not found: $template_file"
        return 1
    fi

    cat "$template_file"
}

template_exists() {
    local template_name="$1"
    local template_file="$TEMPLATES_DIR/${template_name}.yml"

    [[ -f "$template_file" ]]
}

template_list() {
    log_info "Available templates:"
    echo ""

    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        log_warning "Templates directory not found: $TEMPLATES_DIR"
        return 1
    fi

    find "$TEMPLATES_DIR" -name "*.yml" -type f | while read -r template_file; do
        local template_name=$(basename "$template_file" .yml)
        echo "  - $template_name"
    done
}

# ========================================
# Variable Substitution Functions
# ========================================

template_substitute() {
    local template_content="$1"
    shift
    local variables=("$@")

    local result="$template_content"

    # Substitute variables in format {{VARIABLE}}
    for var_pair in "${variables[@]}"; do
        local key="${var_pair%%=*}"
        local value="${var_pair#*=}"

        # Escape special characters in value for sed
        value=$(echo "$value" | sed 's/[&/\]/\\&/g')

        result=$(echo "$result" | sed "s|{{${key}}}|${value}|g")
    done

    echo "$result"
}

template_render() {
    local template_name="$1"
    shift
    local variables=("$@")

    log_debug "Rendering template: $template_name"

    # Load template
    local template_content=$(template_load "$template_name")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Substitute variables
    template_substitute "$template_content" "${variables[@]}"
}

# ========================================
# YAML Validation Functions
# ========================================

template_validate_yaml() {
    local yaml_content="$1"

    log_debug "Validating YAML syntax"

    # Create temporary file
    local tmp_file=$(mktemp /tmp/hostfy-yaml-XXXXXX.yml)
    echo "$yaml_content" > "$tmp_file"

    # Validate with docker compose config
    local compose_cmd=$(get_docker_compose_cmd)
    if [[ -z "$compose_cmd" ]]; then
        log_error "Docker Compose not found"
        rm -f "$tmp_file"
        return 1
    fi

    if $compose_cmd -f "$tmp_file" config &> /dev/null; then
        log_debug "YAML syntax is valid"
        rm -f "$tmp_file"
        return 0
    else
        log_error "Invalid YAML syntax"
        rm -f "$tmp_file"
        return 1
    fi
}

# ========================================
# File Generation Functions
# ========================================

template_generate_file() {
    local template_name="$1"
    local output_file="$2"
    shift 2
    local variables=("$@")

    log_step "Generating compose file from template: $template_name"

    # Render template
    local rendered_content=$(template_render "$template_name" "${variables[@]}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Validate YAML
    if ! template_validate_yaml "$rendered_content"; then
        log_error "Generated YAML is invalid"
        return 1
    fi

    # Ensure output directory exists
    mkdir -p "$(dirname "$output_file")"

    # Write to file
    echo "$rendered_content" > "$output_file"

    log_success "Compose file generated: $output_file"
    return 0
}

# ========================================
# Container-Specific Template Functions
# ========================================

template_generate_postgres() {
    local container_name="$1"
    local version="${2:-16-alpine}"
    local db_name="${3:-hostfy}"
    local db_user="${4:-admin}"
    local db_password="${5:-$(generate_password)}"
    local port="${6:-5432}"

    local output_file="$CONTAINERS_DIR/${container_name}.yml"
    local volume_name="${container_name}_data"

    local variables=(
        "VERSION=$version"
        "CONTAINER_NAME=$container_name"
        "DB_NAME=$db_name"
        "DB_USER=$db_user"
        "DB_PASSWORD=$db_password"
        "PORT=$port"
        "VOLUME_NAME=$volume_name"
    )

    template_generate_file "postgres" "$output_file" "${variables[@]}"
}

template_generate_redis() {
    local container_name="$1"
    local version="${2:-7-alpine}"
    local password="${3:-$(generate_password)}"
    local port="${4:-6379}"

    local output_file="$CONTAINERS_DIR/${container_name}.yml"
    local volume_name="${container_name}_data"

    local variables=(
        "VERSION=$version"
        "CONTAINER_NAME=$container_name"
        "REDIS_PASSWORD=$password"
        "PORT=$port"
        "VOLUME_NAME=$volume_name"
    )

    template_generate_file "redis" "$output_file" "${variables[@]}"
}

template_generate_custom() {
    local container_name="$1"
    local image="$2"
    local port="${3:-80}"
    local env_vars="${4:-}"
    local volumes="${5:-}"
    local traefik_labels="${6:-}"

    local output_file="$CONTAINERS_DIR/${container_name}.yml"
    local service_name=$(slugify "$container_name")

    # Parse ports - only expose to host if NOT using Traefik (no domain specified)
    # When using Traefik, it connects to containers via internal Docker network
    local ports_section=""
    if [[ -n "$port" && -z "$traefik_labels" ]]; then
        # No Traefik = expose port directly to host machine
        ports_section="ports:\n      - \"$port:$port\""
        log_debug "Exposing port $port directly to host (no Traefik routing)"
    fi

    # Parse environment variables
    local env_section=""
    if [[ -n "$env_vars" ]]; then
        env_section="environment:"
        IFS=',' read -ra ENV_ARRAY <<< "$env_vars"
        for env in "${ENV_ARRAY[@]}"; do
            env_section="$env_section\n      $env"
        done
    fi

    # Parse volumes
    local volumes_section=""
    if [[ -n "$volumes" ]]; then
        volumes_section="volumes:"
        IFS=',' read -ra VOL_ARRAY <<< "$volumes"
        for vol in "${VOL_ARRAY[@]}"; do
            volumes_section="$volumes_section\n      - $vol"
        done
    fi

    local variables=(
        "SERVICE_NAME=$service_name"
        "CONTAINER_NAME=$container_name"
        "IMAGE=$image"
        "PORTS=$ports_section"
        "ENVIRONMENT_VARS=$env_section"
        "VOLUMES=$volumes_section"
        "TRAEFIK_LABELS=$traefik_labels"
    )

    template_generate_file "base-container" "$output_file" "${variables[@]}"
}

# ========================================
# Template Merging Functions
# ========================================

template_merge() {
    local base_file="$1"
    local override_file="$2"
    local output_file="$3"

    log_debug "Merging templates: $base_file + $override_file"

    if [[ ! -f "$base_file" ]]; then
        log_error "Base file not found: $base_file"
        return 1
    fi

    if [[ ! -f "$override_file" ]]; then
        log_error "Override file not found: $override_file"
        return 1
    fi

    # Use docker compose config to merge files
    local compose_cmd=$(get_docker_compose_cmd)
    if [[ -z "$compose_cmd" ]]; then
        log_error "Docker Compose not found"
        return 1
    fi

    if $compose_cmd -f "$base_file" -f "$override_file" config > "$output_file" 2>/dev/null; then
        log_success "Templates merged successfully: $output_file"
        return 0
    else
        log_error "Failed to merge templates"
        return 1
    fi
}

# ========================================
# Template Injection Functions
# ========================================

template_inject_labels() {
    local compose_file="$1"
    local labels="$2"

    log_debug "Injecting labels into compose file: $compose_file"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Compose file not found: $compose_file"
        return 1
    fi

    # Create temporary file
    local tmp_file=$(mktemp)
    cp "$compose_file" "$tmp_file"

    # Inject labels (this is a simplified version, might need more sophisticated YAML manipulation)
    # In production, consider using yq or similar tool for proper YAML manipulation

    # For now, we'll append labels at the end of the services section
    # This is a basic implementation

    log_warning "Label injection is basic implementation. Consider using yq for production."

    rm -f "$tmp_file"
    return 0
}

# ========================================
# Template Cleanup Functions
# ========================================

template_delete_generated() {
    local container_name="$1"
    local compose_file="$CONTAINERS_DIR/${container_name}.yml"

    if [[ ! -f "$compose_file" ]]; then
        log_debug "Compose file not found: $compose_file"
        return 0
    fi

    if rm -f "$compose_file"; then
        log_success "Deleted compose file: $compose_file"
        return 0
    else
        log_error "Failed to delete compose file: $compose_file"
        return 1
    fi
}

template_cleanup_all() {
    log_step "Cleaning up all generated compose files"

    if [[ ! -d "$CONTAINERS_DIR" ]]; then
        log_info "No containers directory found"
        return 0
    fi

    local count=$(find "$CONTAINERS_DIR" -name "*.yml" -type f | wc -l | tr -d ' ')

    if [[ "$count" -eq 0 ]]; then
        log_info "No compose files to clean up"
        return 0
    fi

    if ! confirm "This will delete $count generated compose files. Continue?"; then
        log_info "Cleanup cancelled"
        return 0
    fi

    find "$CONTAINERS_DIR" -name "*.yml" -type f -delete

    log_success "Cleanup completed"
}

# ========================================
# Template Info Functions
# ========================================

template_info() {
    local template_name="$1"

    if ! template_exists "$template_name"; then
        log_error "Template not found: $template_name"
        return 1
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Template: $template_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local template_file="$TEMPLATES_DIR/${template_name}.yml"

    echo "Path: $template_file"
    echo ""
    echo "Variables (detected):"

    # Extract variables from template
    grep -o '{{[^}]*}}' "$template_file" | sort -u | while read -r var; do
        local var_name=$(echo "$var" | sed 's/{{//g' | sed 's/}}//g')
        echo "  - $var_name"
    done

    echo ""
}

# ========================================
# Initialization
# ========================================

template_ensure_directories() {
    mkdir -p "$TEMPLATES_DIR"
    mkdir -p "$CONTAINERS_DIR"
}

# Auto-initialize
template_ensure_directories
