#!/bin/bash
# uninstall.sh
# Script to uninstall Hostfy and remove all related components

# Colors (define first for logging)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${NC}ℹ $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Detect HOSTFY_ROOT - handles both local and curl|bash execution
detect_hostfy_root() {
    # Method 1: Try BASH_SOURCE (works for local execution)
    if [[ -n "${BASH_SOURCE[0]}" && "${BASH_SOURCE[0]}" != "bash" ]]; then
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
        local potential_root="$(dirname "$script_dir" 2>/dev/null)"
        if [[ -d "$potential_root/commands" && -d "$potential_root/docker" ]]; then
            echo "$potential_root"
            return 0
        fi
    fi

    # Method 2: Follow the hostfy symlink
    if [[ -L "/usr/local/bin/hostfy" ]]; then
        local link_target="$(readlink /usr/local/bin/hostfy)"
        local commands_dir="$(dirname "$link_target")"
        local potential_root="$(dirname "$commands_dir")"
        if [[ -d "$potential_root/commands" ]]; then
            echo "$potential_root"
            return 0
        fi
    fi

    # Method 3: Check common installation paths
    local common_paths=(
        "$HOME/hostfy"
        "$HOME/.hostfy"
        "/opt/hostfy"
        "/usr/local/hostfy"
        "$HOME/Applications/Apps/hostfyapp"
    )

    for path in "${common_paths[@]}"; do
        if [[ -d "$path/commands" ]]; then
            echo "$path"
            return 0
        fi
    done

    # Not found
    return 1
}

# Detect installation path
HOSTFY_ROOT="$(detect_hostfy_root)"

if [[ -z "$HOSTFY_ROOT" || "$HOSTFY_ROOT" == "/" ]]; then
    log_warning "Could not auto-detect Hostfy installation path."
    log_info "Please enter the Hostfy installation directory:"
    # Will read from tty after exec 3</dev/tty
    HOSTFY_ROOT=""
fi

DOCKER_DIR="$HOSTFY_ROOT/docker"
CONFIG_DIR="$HOSTFY_ROOT/config"
LOGS_DIR="$HOSTFY_ROOT/logs"
SCRIPT_DIR="$HOSTFY_ROOT/commands"

# Open /dev/tty for interactive input (required for curl | bash)
exec 3</dev/tty || {
    log_error "Cannot open terminal for input. Run directly: bash <(curl -fsSL URL)"
    exit 1
}

# If HOSTFY_ROOT was not detected, ask the user
if [[ -z "$HOSTFY_ROOT" ]]; then
    printf "Enter path: "
    read -r HOSTFY_ROOT <&3

    if [[ ! -d "$HOSTFY_ROOT" ]]; then
        log_error "Directory does not exist: $HOSTFY_ROOT"
        exec 3<&-
        exit 1
    fi

    DOCKER_DIR="$HOSTFY_ROOT/docker"
    CONFIG_DIR="$HOSTFY_ROOT/config"
    LOGS_DIR="$HOSTFY_ROOT/logs"
    SCRIPT_DIR="$HOSTFY_ROOT/commands"
fi

log_info "Hostfy installation found at: $HOSTFY_ROOT"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   🗑️  Hostfy Uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_warning "This script will remove Hostfy and all its components."
log_warning "Running containers will be stopped and removed."
echo ""
printf "Are you sure you want to continue? (y/N) "
read -n 1 -r REPLY <&3
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Uninstall cancelled."
    exec 3<&-
    exit 0
fi

# 1. Stop API
log_info "Stopping API server..."
if [[ -f "$SCRIPT_DIR/hostfy.sh" ]]; then
    bash "$SCRIPT_DIR/hostfy.sh" api stop >/dev/null 2>&1
fi
# Fallback: kill by port 3000 if still running
if lsof -i :3000 | grep -q LISTEN; then
    log_info "Killing process on port 3000..."
    lsof -ti :3000 | xargs kill -9 2>/dev/null
fi

# 2. Stop and Remove Traefik
log_info "Stopping Traefik..."
if [[ -d "$DOCKER_DIR/traefik" ]]; then
    cd "$DOCKER_DIR/traefik"
    docker compose down >/dev/null 2>&1 || docker-compose down >/dev/null 2>&1
fi

# 3. Stop and Remove Managed Containers
log_info "Stopping managed containers..."
# Find all containers with label hostfy.managed=true
containers=$(docker ps -a --filter "label=hostfy.managed=true" --format "{{.Names}}")
if [[ -n "$containers" ]]; then
    echo "$containers" | while read -r container; do
        log_info "Removing container: $container"
        docker stop "$container" >/dev/null 2>&1
        docker rm "$container" >/dev/null 2>&1
    done
else
    log_info "No managed containers found."
fi

# 4. Remove Docker Network
log_info "Removing Docker network..."
if docker network ls | grep -q "hostfy-network"; then
    docker network rm hostfy-network >/dev/null 2>&1
    log_success "Network removed"
else
    log_info "Network not found"
fi

# 5. Remove Global CLI
log_info "Removing global CLI..."
if [[ -L "/usr/local/bin/hostfy" ]]; then
    rm "/usr/local/bin/hostfy"
    log_success "CLI link removed"
elif [[ -f "/usr/local/bin/hostfy" ]]; then
     # Try with sudo if permission denied
     if rm "/usr/local/bin/hostfy" 2>/dev/null; then
        log_success "CLI link removed"
     else
        sudo rm "/usr/local/bin/hostfy"
        log_success "CLI link removed (with sudo)"
     fi
fi

# 6. Remove Files
echo ""
log_warning "Do you want to delete all Hostfy files and data?"
log_warning "This includes configuration, logs, and database volumes in $HOSTFY_ROOT"
printf "Delete files? (y/N) "
read -n 1 -r REPLY <&3
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Removing files..."

    # Extended safety checks - never delete critical system directories
    local dangerous_paths=("/" "/root" "/home" "/usr" "/var" "/etc" "/bin" "/sbin" "/opt" "/tmp")
    local is_dangerous=false

    for dangerous in "${dangerous_paths[@]}"; do
        if [[ "$HOSTFY_ROOT" == "$dangerous" ]]; then
            is_dangerous=true
            break
        fi
    done

    if [[ "$is_dangerous" == "true" ]]; then
        log_error "Safety check failed: Cannot delete system directory '$HOSTFY_ROOT'"
        log_info "Please manually remove Hostfy files from subdirectories:"
        log_info "  rm -rf $HOSTFY_ROOT/commands"
        log_info "  rm -rf $HOSTFY_ROOT/docker"
        log_info "  rm -rf $HOSTFY_ROOT/config"
        log_info "  rm -rf $HOSTFY_ROOT/logs"
    elif [[ -n "$HOSTFY_ROOT" ]]; then
        rm -rf "$HOSTFY_ROOT"
        log_success "Files removed"
    else
        log_error "Safety check failed: HOSTFY_ROOT is empty."
    fi
else
    log_info "Files kept at $HOSTFY_ROOT"
fi

# Close file descriptor
exec 3<&-

echo ""
log_success "Uninstallation complete."
