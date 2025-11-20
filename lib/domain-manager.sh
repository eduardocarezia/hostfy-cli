#!/bin/bash
# lib/domain-manager.sh
# Domain and Traefik Label Management for Hostfy

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ========================================
# Configuration
# ========================================
HOSTFY_NETWORK="${HOSTFY_NETWORK:-hostfy-network}"
SSL_RESOLVER="${SSL_RESOLVER:-letsencrypt}"

# ========================================
# Domain Registry Functions
# ========================================

domain_add_to_registry() {
    local domain="$1"
    local container="$2"
    local router="$3"

    ensure_json_file "$DOMAINS_REGISTRY" '{"domains":[]}'

    local domain_entry=$(jq -n \
        --arg domain "$domain" \
        --arg container "$container" \
        --arg router "$router" \
        --arg created "$(get_timestamp)" \
        '{
            domain: $domain,
            container: $container,
            router: $router,
            ssl: {
                enabled: true,
                resolver: "letsencrypt"
            },
            created_at: $created
        }')

    json_append "$DOMAINS_REGISTRY" ".domains" "$domain_entry"

    log_success "Domain registered: $domain → $container"
}

domain_remove_from_registry() {
    local domain="$1"

    if [[ ! -f "$DOMAINS_REGISTRY" ]]; then
        return 0
    fi

    local tmp_file=$(mktemp)
    jq ".domains |= map(select(.domain != \"$domain\"))" "$DOMAINS_REGISTRY" > "$tmp_file" && mv "$tmp_file" "$DOMAINS_REGISTRY"

    log_success "Domain removed from registry: $domain"
}

domain_get_from_registry() {
    local domain="$1"

    if [[ ! -f "$DOMAINS_REGISTRY" ]]; then
        echo ""
        return 1
    fi

    jq -r ".domains[] | select(.domain == \"$domain\")" "$DOMAINS_REGISTRY"
}

domain_list_by_container() {
    local container="$1"

    if [[ ! -f "$DOMAINS_REGISTRY" ]]; then
        echo "[]"
        return 0
    fi

    jq -r ".domains[] | select(.container == \"$container\") | .domain" "$DOMAINS_REGISTRY"
}

domain_exists_in_registry() {
    local domain="$1"

    if [[ ! -f "$DOMAINS_REGISTRY" ]]; then
        return 1
    fi

    local count=$(jq -r ".domains[] | select(.domain == \"$domain\") | .domain" "$DOMAINS_REGISTRY" | wc -l | tr -d ' ')

    [[ "$count" -gt 0 ]]
}

# ========================================
# Traefik Label Generation
# ========================================

domain_generate_router_name() {
    local container_name="$1"
    local domain="$2"

    # Generate unique router name
    local slug=$(slugify "${container_name}-${domain}")
    local random=$(generate_random_string 6)

    echo "${slug}-${random}"
}

domain_generate_labels() {
    local container_name="$1"
    local domain="$2"
    local port="$3"
    local ssl="${4:-true}"

    local router_name=$(domain_generate_router_name "$container_name" "$domain")

    log_debug "Generating Traefik labels for domain: $domain"

    local labels=""

    # Enable Traefik
    labels="${labels}      - \"traefik.enable=true\"\n"

    # Docker network
    labels="${labels}      - \"traefik.docker.network=${HOSTFY_NETWORK}\"\n"

    # HTTP Router
    labels="${labels}      - \"traefik.http.routers.${router_name}.rule=Host(\\\`${domain}\\\`)\"\n"
    labels="${labels}      - \"traefik.http.routers.${router_name}.entrypoints=websecure\"\n"

    # SSL/TLS
    if [[ "$ssl" == "true" ]]; then
        labels="${labels}      - \"traefik.http.routers.${router_name}.tls=true\"\n"
        labels="${labels}      - \"traefik.http.routers.${router_name}.tls.certresolver=${SSL_RESOLVER}\"\n"
    fi

    # Service
    labels="${labels}      - \"traefik.http.services.${router_name}.loadbalancer.server.port=${port}\"\n"

    # Middlewares (optional - headers)
    labels="${labels}      - \"traefik.http.routers.${router_name}.middlewares=${router_name}-headers\"\n"
    labels="${labels}      - \"traefik.http.middlewares.${router_name}-headers.headers.customrequestheaders.X-Forwarded-Proto=https\"\n"

    echo -e "$labels"
}

domain_generate_labels_multiple() {
    local container_name="$1"
    local port="$2"
    shift 2
    local domains=("$@")

    local all_labels=""

    for domain in "${domains[@]}"; do
        local labels=$(domain_generate_labels "$container_name" "$domain" "$port")
        all_labels="${all_labels}${labels}"
    done

    echo -e "$all_labels"
}

# ========================================
# Domain Validation
# ========================================

domain_validate() {
    local domain="$1"

    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: $domain"
        log_info "Domain must be a valid DNS name (e.g., example.com, api.example.com)"
        return 1
    fi

    # Check if domain is already in use
    if domain_exists_in_registry "$domain"; then
        local existing_container=$(jq -r ".domains[] | select(.domain == \"$domain\") | .container" "$DOMAINS_REGISTRY")
        log_error "Domain '$domain' is already in use by container: $existing_container"
        return 1
    fi

    return 0
}

# ========================================
# Domain Management Functions
# ========================================

domain_add() {
    local container_name="$1"
    local domain="$2"
    local port="${3:-80}"

    log_step "Adding domain to container: $domain → $container_name"

    # Validate domain
    if ! validate_domain "$domain"; then
        return 1
    fi

    if domain_exists_in_registry "$domain"; then
        log_error "Domain already exists: $domain"
        return 1
    fi

    # Check if container exists
    if ! container_exists "$container_name"; then
        log_error "Container '$container_name' does not exist"
        return 1
    fi

    # Generate router name
    local router_name=$(domain_generate_router_name "$container_name" "$domain")

    # Add to registry
    domain_add_to_registry "$domain" "$container_name" "$router_name"

    # Generate labels
    local labels=$(domain_generate_labels "$container_name" "$domain" "$port")

    log_info "Generated Traefik labels:"
    echo -e "$labels"

    log_warning "Container needs to be recreated for domain changes to take effect"
    log_info "Run: hostfy restart $container_name"

    return 0
}

domain_remove() {
    local container_name="$1"
    local domain="$2"

    log_step "Removing domain from container: $domain"

    # Check if domain exists
    if ! domain_exists_in_registry "$domain"; then
        log_error "Domain not found: $domain"
        return 1
    fi

    # Verify domain belongs to container
    local domain_container=$(jq -r ".domains[] | select(.domain == \"$domain\") | .container" "$DOMAINS_REGISTRY")

    if [[ "$domain_container" != "$container_name" ]]; then
        log_error "Domain '$domain' belongs to container '$domain_container', not '$container_name'"
        return 1
    fi

    # Remove from registry
    domain_remove_from_registry "$domain"

    log_warning "Container needs to be recreated for domain changes to take effect"
    log_info "Run: hostfy restart $container_name"

    return 0
}

domain_list() {
    local container_name="${1:-}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ -n "$container_name" ]]; then
        echo "   Domains for container: $container_name"
    else
        echo "   All Domains"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ! -f "$DOMAINS_REGISTRY" ]]; then
        echo "  (no domains registered)"
        return 0
    fi

    if [[ -n "$container_name" ]]; then
        local domains=$(domain_list_by_container "$container_name")

        if [[ -z "$domains" ]]; then
            echo "  (no domains configured)"
            return 0
        fi

        while IFS= read -r domain; do
            if [[ -n "$domain" ]]; then
                echo "  - https://$domain"
            fi
        done <<< "$domains"
    else
        jq -r '.domains[] | "  \(.domain) → \(.container)"' "$DOMAINS_REGISTRY"
    fi

    echo ""
}

domain_info() {
    local domain="$1"

    if ! domain_exists_in_registry "$domain"; then
        log_error "Domain not found: $domain"
        return 1
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Domain: $domain"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    jq -r ".domains[] | select(.domain == \"$domain\") |
        \"Container: \(.container)\",
        \"Router: \(.router)\",
        \"SSL Enabled: \(.ssl.enabled)\",
        \"SSL Resolver: \(.ssl.resolver)\",
        \"Created: \(.created_at)\"
    " "$DOMAINS_REGISTRY"

    echo ""
}

# ========================================
# Domain Update Functions
# ========================================

domain_update_ssl() {
    local domain="$1"
    local enabled="${2:-true}"

    if ! domain_exists_in_registry "$domain"; then
        log_error "Domain not found: $domain"
        return 1
    fi

    local tmp_file=$(mktemp)
    jq "(.domains[] | select(.domain == \"$domain\") | .ssl.enabled) = ($enabled | test(\"true\"))" "$DOMAINS_REGISTRY" > "$tmp_file" && mv "$tmp_file" "$DOMAINS_REGISTRY"

    log_success "SSL updated for domain: $domain (enabled: $enabled)"
}

# ========================================
# Bulk Domain Operations
# ========================================

domain_add_multiple() {
    local container_name="$1"
    local port="$2"
    shift 2
    local domains=("$@")

    log_step "Adding multiple domains to container: $container_name"

    for domain in "${domains[@]}"; do
        domain_add "$container_name" "$domain" "$port"
    done

    log_success "All domains added successfully"
}

domain_remove_all_for_container() {
    local container_name="$1"

    log_step "Removing all domains for container: $container_name"

    local domains=$(domain_list_by_container "$container_name")

    if [[ -z "$domains" ]]; then
        log_info "No domains to remove"
        return 0
    fi

    while IFS= read -r domain; do
        if [[ -n "$domain" ]]; then
            domain_remove_from_registry "$domain"
        fi
    done <<< "$domains"

    log_success "All domains removed for container: $container_name"
}

# ========================================
# Traefik Dynamic Configuration
# ========================================

domain_generate_dynamic_config() {
    local output_file="${1:-$DOCKER_DIR/traefik/dynamic/domains.yml}"

    log_step "Generating Traefik dynamic configuration"

    mkdir -p "$(dirname "$output_file")"

    # This is a placeholder for generating Traefik dynamic configuration
    # from the domains registry

    cat > "$output_file" <<EOF
# Traefik Dynamic Configuration
# Generated by Hostfy at $(get_timestamp)

http:
  routers: {}
  services: {}
  middlewares: {}
EOF

    log_success "Dynamic configuration generated: $output_file"
}

# ========================================
# Domain Testing Functions
# ========================================

domain_test_resolution() {
    local domain="$1"

    log_step "Testing DNS resolution for: $domain"

    if host "$domain" &> /dev/null; then
        local ip=$(host "$domain" | grep "has address" | awk '{print $4}' | head -1)
        log_success "Domain resolves to: $ip"
        return 0
    else
        log_error "Domain does not resolve: $domain"
        return 1
    fi
}

domain_test_https() {
    local domain="$1"

    log_step "Testing HTTPS access for: $domain"

    if curl -s -o /dev/null -w "%{http_code}" "https://$domain" | grep -q "^[23]"; then
        log_success "HTTPS is accessible: $domain"
        return 0
    else
        log_error "HTTPS is not accessible: $domain"
        return 1
    fi
}

# ========================================
# Domain Statistics
# ========================================

domain_stats() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Domain Statistics"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ! -f "$DOMAINS_REGISTRY" ]]; then
        echo "Total Domains: 0"
        return 0
    fi

    local total=$(jq -r '.domains | length' "$DOMAINS_REGISTRY")
    local with_ssl=$(jq -r '.domains | map(select(.ssl.enabled == true)) | length' "$DOMAINS_REGISTRY")

    echo "Total Domains: $total"
    echo "With SSL: $with_ssl"
    echo "Without SSL: $((total - with_ssl))"
    echo ""
}
