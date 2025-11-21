#!/bin/bash
# initialize.sh
# Hostfy System Bootstrap and Initialization Script
# This script downloads all necessary files and sets up the Hostfy system

set -e

# ========================================
# Configuration
# ========================================
GITHUB_REPO="eduardocarezia/hostfy-cli"
GITHUB_BRANCH="main"
GITHUB_RAW_URL="https://github.com/${GITHUB_REPO}/raw/refs/heads/${GITHUB_BRANCH}"

# Force automatic installation without prompts
HOSTFY_FORCE="${HOSTFY_FORCE:-true}"

# Detect script directory (works when piped from curl)
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(pwd)/commands"
fi
COMMANDS_DIR="$SCRIPT_DIR"
LIB_DIR="$COMMANDS_DIR/lib"
CATALOG_DIR="$COMMANDS_DIR/catalog"
HOSTFY_ROOT="$(dirname "$COMMANDS_DIR")"
DOCKER_DIR="$HOSTFY_ROOT/docker"
CONFIG_DIR="$HOSTFY_ROOT/config"
LOGS_DIR="$HOSTFY_ROOT/logs"

HOSTFY_NETWORK="${HOSTFY_NETWORK:-hostfy-network}"
TRAEFIK_VERSION="${TRAEFIK_VERSION:-v2.10}"
CATALOG_URL="${CATALOG_URL:-${GITHUB_RAW_URL}/catalog/containers-catalog.json}"

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
# OS Detection
# ========================================
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                echo "debian"
                ;;
            centos|rhel|fedora)
                echo "rhel"
                ;;
            alpine)
                echo "alpine"
                ;;
            *)
                echo "linux"
                ;;
        esac
    else
        echo "unknown"
    fi
}

# ========================================
# Dependency Installation Functions
# ========================================
install_node() {
    local os=$(detect_os)

    log_step "Installing Node.js and npm..."

    case "$os" in
        macos)
            if command -v brew &> /dev/null; then
                brew install node
                log_success "Node.js installed successfully!"
            else
                log_error "Homebrew not found. Please install Node.js manually: https://nodejs.org/"
                exit 1
            fi
            ;;
        debian)
            # Check for sudo
            if command -v sudo &> /dev/null; then
                SUDO="sudo"
            else
                SUDO=""
            fi

            curl -fsSL https://deb.nodesource.com/setup_lts.x | $SUDO -E bash -
            $SUDO apt-get install -y nodejs
            log_success "Node.js installed successfully!"
            ;;
        rhel)
            if command -v sudo &> /dev/null; then
                SUDO="sudo"
            else
                SUDO=""
            fi
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | $SUDO bash -
            $SUDO yum install -y nodejs
            log_success "Node.js installed successfully!"
            ;;
        alpine)
            if command -v sudo &> /dev/null; then
                SUDO="sudo"
            else
                SUDO=""
            fi
            $SUDO apk add --no-cache nodejs npm
            log_success "Node.js installed successfully!"
            ;;
        *)
            log_error "Unable to install Node.js automatically"
            log_info "Please install manually: https://nodejs.org/"
            exit 1
            ;;
    esac
}

install_docker() {
    local os=$(detect_os)

    log_step "Installing Docker..."

    case "$os" in
        macos)
            log_info "Please install Docker Desktop from: https://docs.docker.com/desktop/mac/install/"
            log_info "After installation, start Docker Desktop and run this script again."
            exit 1
            ;;
        debian)
            log_info "Installing Docker on Ubuntu/Debian..."

            # Update package index
            sudo apt-get update

            # Install prerequisites
            sudo apt-get install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release

            # Add Docker's official GPG key
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

            # Set up repository
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            # Install Docker Engine
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            # Add user to docker group
            sudo usermod -aG docker $USER

            # Start Docker
            sudo systemctl start docker
            sudo systemctl enable docker

            log_success "Docker installed successfully!"
            log_warning "Please logout and login again for group changes to take effect"
            ;;
        rhel)
            log_info "Installing Docker on CentOS/RHEL/Fedora..."

            # Remove old versions
            sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine

            # Install prerequisites
            sudo yum install -y yum-utils

            # Add Docker repository
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

            # Install Docker Engine
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            # Add user to docker group
            sudo usermod -aG docker $USER

            # Start Docker
            sudo systemctl start docker
            sudo systemctl enable docker

            log_success "Docker installed successfully!"
            log_warning "Please logout and login again for group changes to take effect"
            ;;
        alpine)
            log_info "Installing Docker on Alpine..."
            sudo apk add --no-cache docker docker-compose
            sudo rc-update add docker boot
            sudo service docker start
            sudo addgroup $USER docker
            log_success "Docker installed successfully!"
            ;;
        *)
            log_error "Unsupported operating system"
            log_info "Please install Docker manually: https://docs.docker.com/get-docker/"
            exit 1
            ;;
    esac
}

install_docker_compose() {
    # Check if Docker Compose plugin is already installed
    if docker compose version &> /dev/null 2>&1; then
        log_success "Docker Compose plugin is already installed"
        return 0
    fi

    local os=$(detect_os)

    log_step "Installing Docker Compose..."

    case "$os" in
        macos)
            log_info "Docker Compose is included with Docker Desktop on macOS"
            ;;
        debian|rhel)
            # Docker Compose plugin should be installed with Docker
            # If not, install standalone version
            log_info "Installing Docker Compose standalone..."

            local compose_version="v2.23.0"
            sudo curl -L "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose

            log_success "Docker Compose installed successfully!"
            ;;
        alpine)
            log_info "Docker Compose should be installed with docker-compose package"
            ;;
        *)
            log_error "Unable to install Docker Compose automatically"
            log_info "Please install manually: https://docs.docker.com/compose/install/"
            exit 1
            ;;
    esac
}

install_jq() {
    local os=$(detect_os)

    log_step "Installing jq..."

    case "$os" in
        macos)
            if command -v brew &> /dev/null; then
                brew install jq
                log_success "jq installed successfully!"
            else
                log_error "Homebrew not found"
                log_info "Install Homebrew first: https://brew.sh/"
                log_info "Or install jq manually: https://stedolan.github.io/jq/download/"
                exit 1
            fi
            ;;
        debian)
            sudo apt-get update
            sudo apt-get install -y jq
            log_success "jq installed successfully!"
            ;;
        rhel)
            sudo yum install -y jq
            log_success "jq installed successfully!"
            ;;
        alpine)
            sudo apk add --no-cache jq
            log_success "jq installed successfully!"
            ;;
        *)
            log_error "Unable to install jq automatically"
            log_info "Please install manually: https://stedolan.github.io/jq/download/"
            exit 1
            ;;
    esac
}

install_curl() {
    local os=$(detect_os)

    log_step "Installing curl..."

    case "$os" in
        macos)
            log_info "curl is pre-installed on macOS"
            ;;
        debian)
            sudo apt-get update
            sudo apt-get install -y curl
            log_success "curl installed successfully!"
            ;;
        rhel)
            sudo yum install -y curl
            log_success "curl installed successfully!"
            ;;
        alpine)
            sudo apk add --no-cache curl
            log_success "curl installed successfully!"
            ;;
        *)
            log_error "Unable to install curl automatically"
            exit 1
            ;;
    esac
}



# ========================================
# Dependency Checks with Auto-Install
# ========================================
check_system_dependencies() {
    log_step "Checking system dependencies..."

    local missing_deps=()
    local os=$(detect_os)

    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    else
        log_success "Docker is installed"

        # Check Docker daemon
        if ! docker info &> /dev/null; then
            log_warning "Docker daemon is not running"
            log_info "Attempting to start Docker..."

            case "$os" in
                debian|rhel)
                    sudo systemctl start docker
                    sleep 2
                    if docker info &> /dev/null; then
                        log_success "Docker daemon started successfully"
                    else
                        log_error "Failed to start Docker daemon"
                        log_info "Please start Docker manually and run this script again"
                        exit 1
                    fi
                    ;;
                macos)
                    log_error "Please start Docker Desktop and run this script again"
                    exit 1
                    ;;
            esac
        else
            log_success "Docker daemon is running"
        fi
    fi

    # Check Docker Compose
    if docker compose version &> /dev/null 2>&1; then
        log_success "Docker Compose is installed (plugin)"
    elif command -v docker-compose &> /dev/null; then
        log_success "Docker Compose is installed (standalone)"
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

    # Check Node.js
    if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
        missing_deps+=("node")
    else
        log_success "Node.js is installed"
    fi

    # Auto-install missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo ""
        log_warning "Missing dependencies: ${missing_deps[*]}"
        log_info "Installing dependencies automatically..."
        echo ""

        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                docker)
                    install_docker
                    ;;
                docker-compose)
                    install_docker_compose
                    ;;
                jq)
                    install_jq
                    ;;
                curl)
                    install_curl
                    ;;
                node)
                    install_node
                    ;;
            esac
        done

        echo ""
        log_success "All dependencies installed!"

        # Check if Docker was installed and needs restart
        if [[ " ${missing_deps[@]} " =~ " docker " ]]; then
            log_warning "Docker was just installed."
            log_info "Note: You may need to logout/login for group permissions to take effect."
            log_info "Continuing with installation..."
            echo ""
            sleep 2
        fi
    else
        log_success "All dependencies are installed"
    fi
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
    log_step "Checking Hostfy files..."

    local needs_download=false

    # Check if main CLI exists
    if [[ ! -f "$COMMANDS_DIR/hostfy.sh" ]]; then
        needs_download=true
        log_info "hostfy.sh not found, will download"
    else
        log_success "hostfy.sh already exists"
    fi

    # Check library files
    local lib_files=(
        "utils.sh"
        "network-manager.sh"
        "template-engine.sh"
        "domain-manager.sh"
        "container-manager.sh"
        "catalog-manager.sh"
        "api-manager.sh"
    )

    local missing_libs=()
    for lib_file in "${lib_files[@]}"; do
        if [[ ! -f "$LIB_DIR/${lib_file}" ]]; then
            missing_libs+=("$lib_file")
            needs_download=true
        fi
    done

    # Check catalog
    local needs_catalog=false
    if [[ ! -f "$CATALOG_DIR/containers-catalog.json" ]]; then
        needs_catalog=true
        needs_download=true
    fi

    # If all files exist, skip download
    if [[ "$needs_download" == "false" ]]; then
        log_success "All Hostfy files already present, skipping download"
        return 0
    fi

    # Download missing files
    log_step "Downloading missing files from GitHub..."

    # Download main CLI if needed
    if [[ ! -f "$COMMANDS_DIR/hostfy.sh" ]]; then
        log_info "Downloading hostfy.sh..."
        if download_file "${GITHUB_RAW_URL}/hostfy.sh" "$COMMANDS_DIR/hostfy.sh"; then
            chmod +x "$COMMANDS_DIR/hostfy.sh"
            log_success "hostfy.sh downloaded"
        else
            log_error "Failed to download hostfy.sh"
            return 1
        fi
    fi

    # Download missing library files
    if [[ ${#missing_libs[@]} -gt 0 ]]; then
        log_info "Downloading missing library files..."
        for lib_file in "${missing_libs[@]}"; do
            log_info "  - $lib_file"
            if download_file "${GITHUB_RAW_URL}/lib/${lib_file}" "$LIB_DIR/${lib_file}"; then
                chmod +x "$LIB_DIR/${lib_file}"
            else
                log_error "Failed to download $lib_file"
                return 1
            fi
        done
        log_success "Library files downloaded"
    else
        log_success "All library files already present"
    fi

    # Download catalog if needed
    if [[ "$needs_catalog" == "true" ]]; then
        log_info "Downloading container catalog..."
        if download_file "$CATALOG_URL" "$CATALOG_DIR/containers-catalog.json"; then
            log_success "Container catalog downloaded"
        else
            log_warning "Could not download catalog, but system will work with custom containers"
        fi
    else
        log_success "Catalog already present"
    fi

    log_success "All required files are available"
}

download_api_files() {
    log_step "Checking API files..."
    
    local api_dir="$COMMANDS_DIR/api"
    mkdir -p "$api_dir"

    local needs_download=false
    if [[ ! -f "$api_dir/package.json" ]] || [[ ! -f "$api_dir/server.js" ]]; then
        needs_download=true
    fi

    if [[ "$needs_download" == "false" ]]; then
        log_success "API files already present"
        return 0
    fi

    log_info "Downloading API files..."
    
    download_file "${GITHUB_RAW_URL}/api/package.json" "$api_dir/package.json"
    download_file "${GITHUB_RAW_URL}/api/server.js" "$api_dir/server.js"
    
    log_success "API files downloaded"
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

setup_api() {
    log_step "Setting up API..."

    local api_dir="$COMMANDS_DIR/api"
    
    if [[ ! -d "$api_dir" ]]; then
        log_error "API directory not found"
        return 1
    fi

    cd "$api_dir"
    
    if [[ ! -d "node_modules" ]]; then
        log_info "Installing API dependencies..."
        if npm install; then
            log_success "API dependencies installed"
        else
            log_error "Failed to install API dependencies"
            return 1
        fi
    else
        log_success "API dependencies already installed"
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
    local lib_files=("utils.sh" "network-manager.sh" "template-engine.sh" "domain-manager.sh" "container-manager.sh" "catalog-manager.sh" "api-manager.sh")
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
# Install Hostfy CLI Globally
# ========================================
install_cli() {
    log_step "Installing Hostfy CLI globally..."

    local install_dir="/usr/local/bin"
    local cli_name="hostfy"

    # Create wrapper script that works from any directory
    cat > "$COMMANDS_DIR/hostfy-wrapper.sh" <<EOF
#!/bin/bash
# Hostfy CLI Wrapper - Can be executed from anywhere

# Find Hostfy installation directory
HOSTFY_INSTALL_DIR="$COMMANDS_DIR"

# Export paths for the main script
export COMMANDS_DIR="\$HOSTFY_INSTALL_DIR"
export LIB_DIR="\$COMMANDS_DIR/lib"
export CATALOG_DIR="\$COMMANDS_DIR/catalog"
export HOSTFY_ROOT="\$(dirname "\$COMMANDS_DIR")"
export DOCKER_DIR="\$HOSTFY_ROOT/docker"
export CONFIG_DIR="\$HOSTFY_ROOT/config"
export LOGS_DIR="\$HOSTFY_ROOT/logs"

# Execute the main script
exec "\$COMMANDS_DIR/hostfy.sh" "\$@"
EOF

    chmod +x "$COMMANDS_DIR/hostfy-wrapper.sh"

    # Install globally (requires sudo on Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if [[ -w "$install_dir" ]]; then
            ln -sf "$COMMANDS_DIR/hostfy-wrapper.sh" "$install_dir/$cli_name"
            log_success "Hostfy CLI installed: $install_dir/$cli_name"
        else
            sudo ln -sf "$COMMANDS_DIR/hostfy-wrapper.sh" "$install_dir/$cli_name"
            log_success "Hostfy CLI installed: $install_dir/$cli_name (with sudo)"
        fi
    else
        # Linux
        sudo ln -sf "$COMMANDS_DIR/hostfy-wrapper.sh" "$install_dir/$cli_name"
        log_success "Hostfy CLI installed: $install_dir/$cli_name"
    fi

    # Verify installation
    if command -v hostfy &> /dev/null; then
        log_success "Hostfy CLI is now available globally!"
        log_info "You can run 'hostfy' from anywhere"
    else
        log_warning "Hostfy installed but may need to restart your terminal"
    fi
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
    log_success "Hostfy CLI is ready to use globally!"
    echo ""
    echo "Quick Start:"
    echo "  1. Update catalog:        hostfy catalog update"
    echo "  2. Browse containers:     hostfy catalog list"
    echo "  3. Search containers:     hostfy catalog search whatsapp"
    echo "  4. Install from catalog:  hostfy install n8n --with-deps"
    echo "  5. List containers:       hostfy list"
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
    echo "For help:          hostfy --help"
    echo "Documentation:     https://github.com/${GITHUB_REPO}"
    echo ""
    echo "Note: If 'hostfy' command is not found, restart your terminal or run:"
    echo "      export PATH=\"/usr/local/bin:\$PATH\""
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

    download_api_files
    echo ""

    setup_network
    echo ""

    setup_traefik_config
    echo ""

    setup_templates
    echo ""

    setup_api
    echo ""
    
    # Start Traefik
    start_traefik
    echo ""

    setup_config_files
    echo ""

    install_cli
    echo ""

    verify_installation
    echo ""

    show_completion
}

# Run main function
main "$@"
