#!/bin/bash
# commands/initialize.sh
# Hostfy System Initialization Script

set -euo pipefail

# ========================================
# Script Directory Setup
# ========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Load libraries
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/network-manager.sh"
source "$LIB_DIR/catalog-manager.sh"

# ========================================
# Configuration
# ========================================
HOSTFY_NETWORK="${HOSTFY_NETWORK:-hostfy-network}"
TRAEFIK_VERSION="${TRAEFIK_VERSION:-v2.10}"

# ========================================
# Welcome Banner
# ========================================
show_banner() {
    echo ""
    echo ""
    echo "   =€ Hostfy Container Management System"
    echo "   Initialization Script"
    echo ""
    echo ""
}

# ========================================
# Dependency Checks
# ========================================
check_system_dependencies() {
    log_step "Checking system dependencies..."

    local missing_deps=()

    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    else
        log_success "Docker is installed"

        # Check Docker daemon
        if ! docker info &> /dev/null; then
            log_error "Docker daemon is not running"
            log_info "Please start Docker and run this script again"
            exit 1
        else
            log_success "Docker daemon is running"
        fi
    fi

    # Check Docker Compose
    if ! check_docker_compose; then
        missing_deps+=("docker-compose")
    else
        log_success "Docker Compose is installed"
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    else
        log_success "jq is installed"
    fi

    # Check curl
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    else
        log_success "curl is installed"
    fi

    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo ""
        log_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        log_info "Please install the missing dependencies:"

        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                docker)
                    echo "  - Docker: https://docs.docker.com/get-docker/"
                    ;;
                docker-compose)
                    echo "  - Docker Compose: https://docs.docker.com/compose/install/"
                    ;;
                jq)
                    echo "  - jq: https://stedolan.github.io/jq/download/"
                    echo "    macOS: brew install jq"
                    echo "    Ubuntu: sudo apt-get install jq"
                    ;;
                curl)
                    echo "  - curl: usually pre-installed on most systems"
                    ;;
            esac
        done

        echo ""
        exit 1
    fi

    log_success "All dependencies are installed"
}

# ========================================
# Directory Structure Setup
# ========================================
setup_directories() {
    log_step "Setting up directory structure..."

    local dirs=(
        "$CONFIG_DIR"
        "$DOCKER_DIR"
        "$DOCKER_DIR/traefik"
        "$DOCKER_DIR/traefik/dynamic"
        "$DOCKER_DIR/templates"
        "$DOCKER_DIR/containers"
        "$DOCKER_DIR/network"
        "$CATALOG_DIR"
        "$LOGS_DIR"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_debug "Created directory: $dir"
        fi
    done

    log_success "Directory structure created"
}

# ========================================
# Network Setup
# ========================================
setup_network() {
    log_step "Setting up Docker network: $HOSTFY_NETWORK"

    if network_exists "$HOSTFY_NETWORK"; then
        log_info "Network already exists"
        network_inspect "$HOSTFY_NETWORK"
    else
        if network_create "$HOSTFY_NETWORK"; then
            log_success "Network created successfully"
        else
            log_error "Failed to create network"
            return 1
        fi
    fi
}

# ========================================
# Traefik Setup
# ========================================
setup_traefik_config() {
    log_step "Setting up Traefik configuration..."

    local traefik_yml="$DOCKER_DIR/traefik/traefik.yml"
    local traefik_compose="$DOCKER_DIR/traefik/docker-compose.yml"
    local acme_file="$DOCKER_DIR/traefik/acme.json"

    # Create traefik.yml
    cat > "$traefik_yml" <<'EOF'
# Traefik Static Configuration
api:
  dashboard: true
  insecure: true  # For development - disable in production

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: hostfy-network
  file:
    directory: "/dynamic"
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@hostfy.local
      storage: /acme.json
      httpChallenge:
        entryPoint: web

log:
  level: INFO

accessLog:
  filePath: /var/log/traefik/access.log
EOF

    log_success "Created traefik.yml"

    # Create docker-compose.yml for Traefik
    cat > "$traefik_compose" <<EOF
version: '3.8'

services:
  traefik:
    image: traefik:${TRAEFIK_VERSION}
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - hostfy-network
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./dynamic:/dynamic:ro
      - ./acme.json:/acme.json
      - ./logs:/var/log/traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(\`traefik.localhost\`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.entrypoints=web"

networks:
  hostfy-network:
    external: true
EOF

    log_success "Created docker-compose.yml for Traefik"

    # Create acme.json with proper permissions
    if [[ ! -f "$acme_file" ]]; then
        touch "$acme_file"
        chmod 600 "$acme_file"
        log_success "Created acme.json for SSL certificates"
    fi

    # Create dynamic configuration directory and placeholder
    mkdir -p "$DOCKER_DIR/traefik/dynamic"
    cat > "$DOCKER_DIR/traefik/dynamic/.gitkeep" <<EOF
# Dynamic Traefik configuration files will be placed here
EOF

    log_success "Traefik configuration completed"
}

start_traefik() {
    log_step "Starting Traefik..."

    local traefik_compose="$DOCKER_DIR/traefik/docker-compose.yml"
    local compose_cmd=$(get_docker_compose_cmd)

    if [[ -z "$compose_cmd" ]]; then
        log_error "Docker Compose not found"
        return 1
    fi

    cd "$DOCKER_DIR/traefik"

    if $compose_cmd up -d 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Traefik started successfully"

        # Wait for Traefik to be ready
        log_info "Waiting for Traefik to be ready..."
        sleep 5

        if container_is_running "traefik"; then
            log_success "Traefik is running"
            log_info "Dashboard available at: http://traefik.localhost:8080"
        else
            log_warning "Traefik container exists but may not be running properly"
        fi
    else
        log_error "Failed to start Traefik"
        return 1
    fi

    cd "$HOSTFY_ROOT"
}

# ========================================
# Template Setup
# ========================================
setup_templates() {
    log_step "Setting up container templates..."

    # PostgreSQL Template
    cat > "$DOCKER_DIR/templates/postgres.yml" <<'EOF'
version: '3.8'

services:
  {{CONTAINER_NAME}}:
    image: postgres:{{VERSION}}
    container_name: {{CONTAINER_NAME}}
    restart: unless-stopped
    environment:
      POSTGRES_DB: {{DB_NAME}}
      POSTGRES_USER: {{DB_USER}}
      POSTGRES_PASSWORD: {{DB_PASSWORD}}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - {{VOLUME_NAME}}:/var/lib/postgresql/data
    networks:
      - hostfy-network
    ports:
      - "{{PORT}}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U {{DB_USER}}"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      - "hostfy.managed=true"
      - "hostfy.type=postgres"
      - "hostfy.version={{VERSION}}"

volumes:
  {{VOLUME_NAME}}:
    driver: local

networks:
  hostfy-network:
    external: true
EOF

    log_success "Created PostgreSQL template"

    # Redis Template
    cat > "$DOCKER_DIR/templates/redis.yml" <<'EOF'
version: '3.8'

services:
  {{CONTAINER_NAME}}:
    image: redis:{{VERSION}}
    container_name: {{CONTAINER_NAME}}
    restart: unless-stopped
    command: redis-server --requirepass {{REDIS_PASSWORD}} --appendonly yes
    volumes:
      - {{VOLUME_NAME}}:/data
    networks:
      - hostfy-network
    ports:
      - "{{PORT}}:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    labels:
      - "hostfy.managed=true"
      - "hostfy.type=redis"
      - "hostfy.version={{VERSION}}"

volumes:
  {{VOLUME_NAME}}:
    driver: local

networks:
  hostfy-network:
    external: true
EOF

    log_success "Created Redis template"

    # Base Container Template
    cat > "$DOCKER_DIR/templates/base-container.yml" <<'EOF'
version: '3.8'

services:
  {{SERVICE_NAME}}:
    image: {{IMAGE}}
    container_name: {{CONTAINER_NAME}}
    restart: unless-stopped
    networks:
      - hostfy-network
    labels:
      - "hostfy.managed=true"
      - "hostfy.type=custom"
{{TRAEFIK_LABELS}}

networks:
  hostfy-network:
    external: true
EOF

    log_success "Created base container template"

    log_success "All templates created"
}

# ========================================
# Catalog Setup
# ========================================
setup_catalog() {
    log_step "Setting up container catalog..."

    if catalog_update true; then
        log_success "Catalog initialized"
    else
        log_warning "Could not download catalog, but system will work with custom containers"
    fi
}

# ========================================
# Configuration Files Setup
# ========================================
setup_config_files() {
    log_step "Setting up configuration files..."

    # Initialize registries
    ensure_json_file "$CONTAINERS_REGISTRY" '{"containers":[]}'
    log_success "Created containers registry"

    ensure_json_file "$DOMAINS_REGISTRY" '{"domains":[]}'
    log_success "Created domains registry"

    # Create settings file
    cat > "$SETTINGS_FILE" <<EOF
{
  "network": {
    "name": "$HOSTFY_NETWORK",
    "driver": "bridge",
    "subnet": "172.20.0.0/16"
  },
  "traefik": {
    "enabled": true,
    "version": "$TRAEFIK_VERSION",
    "dashboard_port": 8080,
    "http_port": 80,
    "https_port": 443
  },
  "catalog": {
    "url": "$CATALOG_URL",
    "cache_time": $CATALOG_CACHE_TIME
  }
}
EOF

    log_success "Created settings file"
}

# ========================================
# Verification
# ========================================
verify_installation() {
    log_step "Verifying installation..."

    local issues=()

    # Check network
    if ! network_exists "$HOSTFY_NETWORK"; then
        issues+=("Network '$HOSTFY_NETWORK' not found")
    fi

    # Check Traefik
    if ! container_is_running "traefik"; then
        issues+=("Traefik is not running")
    fi

    # Check directories
    local required_dirs=(
        "$CONFIG_DIR"
        "$DOCKER_DIR/traefik"
        "$DOCKER_DIR/templates"
        "$CATALOG_DIR"
        "$LOGS_DIR"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            issues+=("Directory missing: $dir")
        fi
    done

    if [[ ${#issues[@]} -gt 0 ]]; then
        log_error "Verification failed with the following issues:"
        for issue in "${issues[@]}"; do
            log_error "  - $issue"
        done
        return 1
    fi

    log_success "Installation verified successfully"
    return 0
}

# ========================================
# Completion Message
# ========================================
show_completion() {
    echo ""
    echo ""
    echo "    Hostfy Initialization Complete!"
    echo ""
    echo ""
    log_success "Hostfy is ready to use!"
    echo ""
    echo "Quick Start:"
    echo "  1. Update catalog:        ./hostfy catalog update"
    echo "  2. Browse containers:     ./hostfy catalog list"
    echo "  3. Install PostgreSQL:    ./hostfy install postgres"
    echo "  4. Install Redis:         ./hostfy install redis"
    echo "  5. List containers:       ./hostfy list"
    echo ""
    echo "Traefik Dashboard: http://traefik.localhost:8080"
    echo ""
    echo "For help:                   ./hostfy --help"
    echo ""
}

# ========================================
# Main Initialization Flow
# ========================================
main() {
    show_banner

    log_info "Starting Hostfy initialization..."
    echo ""

    # Run initialization steps
    check_system_dependencies
    echo ""

    setup_directories
    echo ""

    setup_network
    echo ""

    setup_traefik_config
    echo ""

    start_traefik
    echo ""

    setup_templates
    echo ""

    setup_config_files
    echo ""

    setup_catalog
    echo ""

    verify_installation
    echo ""

    show_completion
}

# Run main function
main "$@"
