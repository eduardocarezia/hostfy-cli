#!/bin/bash
# initialize.sh
# Hostfy System Bootstrap and Initialization Script
# This script downloads all necessary files and sets up the Hostfy system

set -euo pipefail

# ========================================
# Configuration
# ========================================
GITHUB_REPO="eduardocarezia/hostfy-cli"
GITHUB_BRANCH="main"
GITHUB_RAW_URL="https://github.com/${GITHUB_REPO}/raw/refs/heads/${GITHUB_BRANCH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR"
LIB_DIR="$COMMANDS_DIR/lib"
CATALOG_DIR="$COMMANDS_DIR/catalog"
HOSTFY_ROOT="$(dirname "$COMMANDS_DIR")"
DOCKER_DIR="$HOSTFY_ROOT/docker"
CONFIG_DIR="$HOSTFY_ROOT/config"
LOGS_DIR="$HOSTFY_ROOT/logs"

HOSTFY_NETWORK="${HOSTFY_NETWORK:-hostfy-network}"
TRAEFIK_VERSION="${TRAEFIK_VERSION:-v2.10}"
CATALOG_URL="${CATALOG_URL:-${GITHUB_RAW_URL}/commands/catalog/containers-catalog.json}"

# ========================================
# Colors and Formatting
# ========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ========================================
# Logging Functions
# ========================================
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}▶${NC}  $1"
}

# ========================================
# Welcome Banner
# ========================================
show_banner() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   🚀 Hostfy Container Management System"
    echo "   Bootstrap & Initialization Script"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Repository: https://github.com/${GITHUB_REPO}"
    echo "Branch: ${GITHUB_BRANCH}"
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
    if docker compose version &> /dev/null 2>&1; then
        log_success "Docker Compose is installed (v2)"
    elif command -v docker-compose &> /dev/null; then
        log_success "Docker Compose is installed (v1)"
    else
        missing_deps+=("docker-compose")
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
        "$COMMANDS_DIR"
        "$LIB_DIR"
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
        fi
    done

    log_success "Directory structure created"
}

# ========================================
# Download Files from GitHub
# ========================================
download_file() {
    local url="$1"
    local output="$2"

    if curl -fsSL "$url" -o "$output" 2>/dev/null; then
        return 0
    else
        log_error "Failed to download: $url"
        return 1
    fi
}

download_hostfy_files() {
    log_step "Downloading Hostfy files from GitHub..."

    # Download main CLI
    log_info "Downloading hostfy.sh..."
    if download_file "${GITHUB_RAW_URL}/commands/hostfy.sh" "$COMMANDS_DIR/hostfy.sh"; then
        chmod +x "$COMMANDS_DIR/hostfy.sh"
        log_success "hostfy.sh downloaded"
    else
        log_error "Failed to download hostfy.sh"
        return 1
    fi

    # Download library files
    local lib_files=(
        "utils.sh"
        "network-manager.sh"
        "template-engine.sh"
        "domain-manager.sh"
        "container-manager.sh"
        "catalog-manager.sh"
    )

    log_info "Downloading library files..."
    for lib_file in "${lib_files[@]}"; do
        log_info "  - $lib_file"
        if download_file "${GITHUB_RAW_URL}/commands/lib/${lib_file}" "$LIB_DIR/${lib_file}"; then
            chmod +x "$LIB_DIR/${lib_file}"
        else
            log_error "Failed to download $lib_file"
            return 1
        fi
    done

    log_success "All library files downloaded"

    # Download catalog
    log_info "Downloading container catalog..."
    if download_file "$CATALOG_URL" "$CATALOG_DIR/containers-catalog.json"; then
        log_success "Container catalog downloaded"
    else
        log_warning "Could not download catalog, but system will work with custom containers"
    fi

    log_success "All Hostfy files downloaded successfully"
}

# ========================================
# Network Setup
# ========================================
setup_network() {
    log_step "Setting up Docker network: $HOSTFY_NETWORK"

    if docker network ls --format '{{.Name}}' | grep -q "^${HOSTFY_NETWORK}$"; then
        log_info "Network already exists"
    else
        if docker network create --driver bridge --subnet 172.20.0.0/16 "$HOSTFY_NETWORK" &> /dev/null; then
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

    # Create dynamic configuration directory
    mkdir -p "$DOCKER_DIR/traefik/dynamic"
    mkdir -p "$DOCKER_DIR/traefik/logs"

    log_success "Traefik configuration completed"
}

start_traefik() {
    log_step "Starting Traefik..."

    cd "$DOCKER_DIR/traefik"

    local compose_cmd=""
    if docker compose version &> /dev/null 2>&1; then
        compose_cmd="docker compose"
    elif command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        log_error "Docker Compose not found"
        return 1
    fi

    if $compose_cmd up -d 2>&1; then
        log_success "Traefik started successfully"

        # Wait for Traefik to be ready
        log_info "Waiting for Traefik to be ready..."
        sleep 5

        if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
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
}

# ========================================
# Configuration Files Setup
# ========================================
setup_config_files() {
    log_step "Setting up configuration files..."

    # Initialize registries
    echo '{"containers":[]}' > "$CONFIG_DIR/containers.json"
    log_success "Created containers registry"

    echo '{"domains":[]}' > "$CONFIG_DIR/domains.json"
    log_success "Created domains registry"

    # Create settings file
    cat > "$CONFIG_DIR/settings.json" <<EOF
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
    "cache_time": 3600
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
    if ! docker network ls --format '{{.Name}}' | grep -q "^${HOSTFY_NETWORK}$"; then
        issues+=("Network '$HOSTFY_NETWORK' not found")
    fi

    # Check Traefik
    if ! docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
        issues+=("Traefik is not running")
    fi

    # Check hostfy.sh
    if [[ ! -f "$COMMANDS_DIR/hostfy.sh" ]]; then
        issues+=("hostfy.sh not found")
    fi

    # Check library files
    local lib_files=("utils.sh" "network-manager.sh" "template-engine.sh" "domain-manager.sh" "container-manager.sh" "catalog-manager.sh")
    for lib_file in "${lib_files[@]}"; do
        if [[ ! -f "$LIB_DIR/$lib_file" ]]; then
            issues+=("lib/$lib_file not found")
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
# Create Convenience Symlink
# ========================================
create_symlink() {
    log_step "Creating convenience symlink..."

    if [[ -f "$HOSTFY_ROOT/hostfy" ]]; then
        rm -f "$HOSTFY_ROOT/hostfy"
    fi

    ln -s "$COMMANDS_DIR/hostfy.sh" "$HOSTFY_ROOT/hostfy"
    chmod +x "$HOSTFY_ROOT/hostfy"

    log_success "Created symlink: ./hostfy -> commands/hostfy.sh"
}

# ========================================
# Completion Message
# ========================================
show_completion() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   ✅ Hostfy Installation Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_success "Hostfy is ready to use!"
    echo ""
    echo "Quick Start:"
    echo "  1. Update catalog:        ./hostfy catalog update"
    echo "  2. Browse containers:     ./hostfy catalog list"
    echo "  3. Search containers:     ./hostfy catalog search whatsapp"
    echo "  4. Install from catalog:  ./hostfy install n8n --with-deps"
    echo "  5. List containers:       ./hostfy list"
    echo ""
    echo "Available in catalog:"
    echo "  - postgres       PostgreSQL database"
    echo "  - redis          Redis cache"
    echo "  - n8n            Workflow automation"
    echo "  - evolution-api  WhatsApp Multi-Device API"
    echo "  - chatwoot       Customer engagement platform"
    echo ""
    echo "Traefik Dashboard: http://traefik.localhost:8080"
    echo ""
    echo "For help:          ./hostfy --help"
    echo "Documentation:     https://github.com/${GITHUB_REPO}"
    echo ""
}

# ========================================
# Main Initialization Flow
# ========================================
main() {
    show_banner

    log_info "Starting Hostfy installation..."
    echo ""

    # Run initialization steps
    check_system_dependencies
    echo ""

    setup_directories
    echo ""

    download_hostfy_files
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

    create_symlink
    echo ""

    verify_installation
    echo ""

    show_completion
}

# Run main function
main "$@"
