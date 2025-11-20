#!/bin/bash
# lib/catalog-manager.sh
# Container Catalog Management for Hostfy

# Source utilities and managers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/container-manager.sh"

# ========================================
# Configuration
# ========================================
CATALOG_URL="${CATALOG_URL:-https://raw.githubusercontent.com/hostfy/catalog/main/catalog.json}"
CATALOG_FILE="${CATALOG_FILE:-$CATALOG_DIR/containers-catalog.json}"
CATALOG_CACHE_TIME="${CATALOG_CACHE_TIME:-3600}"  # 1 hour

# ========================================
# Catalog Update Functions
# ========================================

catalog_update() {
    local force="${1:-false}"

    log_info "Updating container catalog..."

    # Check cache age
    if [[ -f "$CATALOG_FILE" && "$force" != "true" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS
            local file_age=$(($(date +%s) - $(stat -f %m "$CATALOG_FILE" 2>/dev/null)))
        else
            # Linux
            local file_age=$(($(date +%s) - $(stat -c %Y "$CATALOG_FILE" 2>/dev/null)))
        fi

        if [[ $file_age -lt $CATALOG_CACHE_TIME ]]; then
            log_info "Catalog is up to date (cached)"
            return 0
        fi
    fi

    # Download catalog
    log_step "Downloading catalog from: $CATALOG_URL"

    mkdir -p "$(dirname "$CATALOG_FILE")"

    if curl -fsSL "$CATALOG_URL" -o "$CATALOG_FILE.tmp" 2>&1 | tee -a "$LOG_FILE"; then
        # Validate JSON
        if jq empty "$CATALOG_FILE.tmp" 2>/dev/null; then
            mv "$CATALOG_FILE.tmp" "$CATALOG_FILE"
            local count=$(jq '.containers | length' "$CATALOG_FILE")
            log_success "Catalog updated successfully ($count containers available)"
            return 0
        else
            log_error "Invalid catalog JSON format"
            rm -f "$CATALOG_FILE.tmp"
            return 1
        fi
    else
        log_error "Failed to download catalog from $CATALOG_URL"
        rm -f "$CATALOG_FILE.tmp"
        return 1
    fi
}

catalog_ensure_updated() {
    if [[ ! -f "$CATALOG_FILE" ]]; then
        log_info "Catalog not found locally, downloading..."
        catalog_update true
    else
        catalog_update false
    fi
}

# ========================================
# Catalog Query Functions
# ========================================

catalog_get_info() {
    local container_id="$1"

    catalog_ensure_updated || return 1

    if [[ ! -f "$CATALOG_FILE" ]]; then
        log_error "Catalog file not found: $CATALOG_FILE"
        return 1
    fi

    # Validate catalog JSON first
    if ! jq empty "$CATALOG_FILE" 2>/dev/null; then
        log_error "Catalog file is not valid JSON: $CATALOG_FILE"
        return 1
    fi

    local result=$(jq --arg id "$container_id" '
        .containers[] | select(.slug == $id or .id == $id)
    ' "$CATALOG_FILE" 2>&1)

    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "jq error while reading catalog: $result"
        return 1
    fi

    # Return result (may be empty if container not found)
    echo "$result"
}

catalog_exists() {
    local container_id="$1"

    local info=$(catalog_get_info "$container_id")

    [[ -n "$info" ]]
}

# ========================================
# Catalog List Functions
# ========================================

catalog_list() {
    local category="$1"
    local tag="$2"

    catalog_ensure_updated || return 1

    local jq_filter='.containers[]'

    # Apply filters
    if [[ -n "$category" ]]; then
        jq_filter="$jq_filter | select(.category == \"$category\")"
    fi

    if [[ -n "$tag" ]]; then
        jq_filter="$jq_filter | select(.tags[] == \"$tag\")"
    fi

    # Format output
    jq -r "$jq_filter | \"  \(.slug) - \(.description)\"" "$CATALOG_FILE" | sort
}

catalog_search() {
    local term="$1"

    catalog_ensure_updated || return 1

    log_info "Searching for '$term'..."
    echo ""

    jq -r --arg term "$term" '
        .containers[] |
        select(
            (.name | ascii_downcase | contains($term | ascii_downcase)) or
            (.description | ascii_downcase | contains($term | ascii_downcase)) or
            (.tags[] | ascii_downcase | contains($term | ascii_downcase))
        ) |
        "  \(.slug) - \(.description)"
    ' "$CATALOG_FILE" | sort
}

# ========================================
# Catalog Info Functions
# ========================================

catalog_info() {
    local container_id="$1"

    local info=$(catalog_get_info "$container_id")

    if [[ -z "$info" ]]; then
        log_error "Container '$container_id' not found in catalog"
        return 1
    fi

    # Format output
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$info" | jq -r '"Container: \(.name)"'
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "$info" | jq -r '
        "ID: \(.slug)",
        "Description: \(.description)",
        "Category: \(.category)",
        "Tags: \(.tags | join(", "))",
        "Official: \(.official)",
        "",
        "📦 Image:",
        "  Repository: \(.image.registry)/\(.image.repository)",
        "  Default Version: \(.image.default_version)",
        ""
    '

    # Ports
    echo "🔌 Ports:"
    echo "$info" | jq -r '.ports[] | "  - \(.external):\(.internal) (\(.description))"'
    echo ""

    # Traefik
    echo "🌐 Traefik:"
    echo "$info" | jq -r '"  Enabled: \(.traefik.enabled)"'
    local traefik_enabled=$(echo "$info" | jq -r '.traefik.enabled')
    if [[ "$traefik_enabled" == "true" ]]; then
        echo "$info" | jq -r '"  Default Domain: \(.traefik.default_domain // "N/A")"'
    fi
    echo ""

    # Environment Variables
    echo "📋 Environment Variables:"
    local env_count=$(echo "$info" | jq -r '.environment | length')
    if [[ "$env_count" -gt 0 ]]; then
        echo "$info" | jq -r '
            .environment[] |
            "  - \(.key): \(.description)" +
            (if .required then " (required)" else "" end) +
            (if .default then " [default: \(.default)]" else "" end)
        '
    else
        echo "  (none)"
    fi
    echo ""

    # Dependencies
    local deps=$(echo "$info" | jq -r '.dependencies | length')
    if [[ $deps -gt 0 ]]; then
        echo "🔗 Dependencies:"
        echo "$info" | jq -r '.dependencies[] | "  - \(.)"'
        echo ""
    fi
}

catalog_versions() {
    local container_id="$1"

    local info=$(catalog_get_info "$container_id")

    if [[ -z "$info" ]]; then
        log_error "Container '$container_id' not found in catalog"
        return 1
    fi

    echo "Available versions for '$container_id':"
    echo ""
    echo "$info" | jq -r '
        .image.versions[] |
        "  \(.tag) - \(.description)" +
        (if .recommended then " [RECOMMENDED]" else "" end)
    '
}

catalog_categories() {
    catalog_ensure_updated || return 1

    echo "Available categories:"
    echo ""
    jq -r '.categories[] | "  \(.id) - \(.description)"' "$CATALOG_FILE"
}

# ========================================
# Catalog Installation Functions
# ========================================

catalog_install() {
    local container_id="$1"
    shift
    local args=("$@")

    catalog_ensure_updated || return 1

    # Get container info
    local info=$(catalog_get_info "$container_id")

    if [[ -z "$info" ]]; then
        log_error "Container '$container_id' not found in catalog"
        log_info "Available containers: $(catalog_list | head -5)"
        log_info "Use 'hostfy catalog list' to see all available containers"
        return 1
    fi

    log_info "Installing '$container_id' from catalog..."

    # Parse installation options
    local version=""
    local with_deps=false
    local interactive=false
    local custom_domain=""
    local env_vars=()

    # Parse args
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
            --version)
                i=$((i + 1))
                version="${args[$i]}"
                ;;
            --with-deps)
                with_deps=true
                ;;
            --interactive)
                interactive=true
                ;;
            --domain)
                i=$((i + 1))
                custom_domain="${args[$i]}"
                ;;
            --env)
                i=$((i + 1))
                env_vars+=("${args[$i]}")
                ;;
            *)
                log_warning "Unknown option: ${args[$i]}"
                ;;
        esac
        i=$((i + 1))
    done

    # Extract and validate version
    if [[ -z "$version" ]]; then
        version=$(echo "$info" | jq -r '.image.default_version // empty')
        if [[ -z "$version" ]]; then
            log_error "No default version found for '$container_id'"
            return 1
        fi
    fi

    log_debug "Using version: $version"

    # Check dependencies FIRST (before attempting installation)
    local deps=$(echo "$info" | jq -r '.dependencies[]?' 2>/dev/null)
    if [[ -n "$deps" ]]; then
        local missing_deps=()
        local stopped_deps=()

        while IFS= read -r dep; do
            if [[ -n "$dep" ]]; then
                if ! container_exists "$dep"; then
                    missing_deps+=("$dep")
                elif ! container_is_running "$dep"; then
                    stopped_deps+=("$dep")
                fi
            fi
        done <<< "$deps"

        # Handle missing dependencies
        if [[ ${#missing_deps[@]} -gt 0 ]]; then
            if [[ "$with_deps" == "true" ]]; then
                log_info "📦 Installing missing dependencies: ${missing_deps[*]}"
                for dep in "${missing_deps[@]}"; do
                    log_info "  📦 Installing $dep..."
                    # Install dependency WITHOUT parent args (no --domain, etc.)
                    if ! catalog_install "$dep"; then
                        log_error "Failed to install dependency: $dep"
                        return 1
                    fi
                done
            else
                log_error "Missing required dependencies: ${missing_deps[*]}"
                log_info "Install with: hostfy install $container_id --with-deps"
                return 1
            fi
        fi

        # Handle stopped dependencies
        if [[ ${#stopped_deps[@]} -gt 0 ]]; then
            log_info "Starting stopped dependencies: ${stopped_deps[*]}"
            for dep in "${stopped_deps[@]}"; do
                log_info "  ▶ Starting $dep..."
                container_start "$dep"
            done
        fi

        # Verify all dependencies are running
        while IFS= read -r dep; do
            if [[ -n "$dep" ]]; then
                if ! container_is_running "$dep"; then
                    log_error "Dependency '$dep' is not running"
                    return 1
                fi
                log_success "  ✅ $dep (running)"
            fi
        done <<< "$deps"
    fi

    # Interactive mode: prompt for required environment variables
    if [[ "$interactive" == "true" ]]; then
        echo ""
        log_info "🧙 Interactive Configuration Wizard"
        echo ""

        local env_keys=$(echo "$info" | jq -r '.environment[]? | select(.required == true) | .key')

        while IFS= read -r var; do
            if [[ -n "$var" ]]; then
                local description=$(echo "$info" | jq -r --arg k "$var" '.environment[] | select(.key == $k) | .description')
                local default=$(echo "$info" | jq -r --arg k "$var" '.environment[] | select(.key == $k) | .default // empty')
                local is_secret=$(echo "$info" | jq -r --arg k "$var" '.environment[] | select(.key == $k) | .secret // false')

                echo -n "  $var ($description)"
                [[ -n "$default" ]] && echo -n " [default: $default]"
                echo -n ": "

                if [[ "$is_secret" == "true" ]]; then
                    read -s value
                    echo ""
                else
                    read value
                fi

                [[ -z "$value" && -n "$default" ]] && value="$default"

                if [[ -n "$value" ]]; then
                    env_vars+=("${var}=${value}")
                fi
            fi
        done <<< "$env_keys"
        echo ""
    fi

    # Build installation arguments - Extract and validate repository
    local repository=$(echo "$info" | jq -r '.image.repository // empty')
    if [[ -z "$repository" ]]; then
        log_error "No repository found in catalog for '$container_id'"
        log_debug "Container info: $info"
        return 1
    fi

    local image="${repository}:${version}"
    log_debug "Image: $image"

    # Extract port with proper fallback
    local port=$(echo "$info" | jq -r '
        if .traefik.port then
            .traefik.port
        elif .ports[0].external then
            .ports[0].external
        else
            80
        end
    ')

    if [[ -z "$port" || "$port" == "null" ]]; then
        port="80"
    fi

    log_debug "Port: $port"

    # Determine domain
    local domain="$custom_domain"
    if [[ -z "$domain" ]]; then
        domain=$(echo "$info" | jq -r '.traefik.default_domain // empty')
    fi

    # Build install command
    local install_args=(
        "--image" "$image"
        "--port" "$port"
    )

    if [[ -n "$domain" && "$domain" != "null" ]]; then
        install_args+=("--domain" "$domain")
    fi

    for env_var in "${env_vars[@]}"; do
        install_args+=("--env" "$env_var")
    done

    # Install container
    container_install "$container_id" "${install_args[@]}"

    if [[ $? -eq 0 ]]; then
        log_success "✅ '$container_id' installed successfully from catalog!"

        if [[ -n "$domain" && "$domain" != "null" ]]; then
            log_info "🔗 Access at: https://$domain"
        fi

        return 0
    else
        log_error "Failed to install '$container_id'"
        return 1
    fi
}

# ========================================
# Catalog Statistics
# ========================================

catalog_stats() {
    catalog_ensure_updated || return 1

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Catalog Statistics"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local total=$(jq -r '.containers | length' "$CATALOG_FILE")
    local official=$(jq -r '.containers | map(select(.official == true)) | length' "$CATALOG_FILE")
    local categories=$(jq -r '.categories | length' "$CATALOG_FILE")

    echo "Total Containers: $total"
    echo "Official: $official"
    echo "Community: $((total - official))"
    echo "Categories: $categories"
    echo ""

    echo "Containers by Category:"
    jq -r '.categories[] | .id' "$CATALOG_FILE" | while read -r cat; do
        local count=$(jq -r --arg cat "$cat" '.containers | map(select(.category == $cat)) | length' "$CATALOG_FILE")
        echo "  - $cat: $count"
    done

    echo ""
}

# ========================================
# Catalog Validation
# ========================================

catalog_validate() {
    log_step "Validating catalog"

    if [[ ! -f "$CATALOG_FILE" ]]; then
        log_error "Catalog file not found: $CATALOG_FILE"
        return 1
    fi

    # Validate JSON structure
    if ! jq empty "$CATALOG_FILE" 2>/dev/null; then
        log_error "Invalid JSON format"
        return 1
    fi

    # Check required fields
    local required_fields=("version" "last_updated" "containers" "categories")

    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$CATALOG_FILE" &>/dev/null; then
            log_error "Missing required field: $field"
            return 1
        fi
    done

    log_success "Catalog is valid"
    return 0
}

# ========================================
# Catalog Export Functions
# ========================================

catalog_export_installed() {
    local output_file="${1:-./installed-containers.json}"

    log_step "Exporting installed containers from catalog"

    if [[ ! -f "$CONTAINERS_REGISTRY" ]]; then
        log_error "No containers installed"
        return 1
    fi

    # Create export
    jq -n \
        --arg exported "$(get_timestamp)" \
        --slurpfile installed "$CONTAINERS_REGISTRY" \
        '{
            exported_at: $exported,
            containers: $installed[0].containers
        }' > "$output_file"

    log_success "Installed containers exported to: $output_file"
}

# ========================================
# Catalog Sync Functions
# ========================================

catalog_sync_check() {
    log_step "Checking for container updates..."

    if [[ ! -f "$CONTAINERS_REGISTRY" ]]; then
        log_info "No containers installed"
        return 0
    fi

    catalog_ensure_updated || return 1

    local updates_available=false

    # Check each installed container
    jq -r '.containers[] | .name' "$CONTAINERS_REGISTRY" | while read -r container_name; do
        if catalog_exists "$container_name"; then
            local installed_image=$(jq -r --arg name "$container_name" '.containers[] | select(.name == $name) | .image' "$CONTAINERS_REGISTRY")
            local catalog_image=$(catalog_get_info "$container_name" | jq -r '.image.repository + ":" + .image.default_version')

            if [[ "$installed_image" != "$catalog_image" ]]; then
                log_info "  📦 Update available for $container_name: $installed_image → $catalog_image"
                updates_available=true
            fi
        fi
    done

    if [[ "$updates_available" == "false" ]]; then
        log_success "All containers are up to date"
    fi
}
