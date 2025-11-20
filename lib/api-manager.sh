#!/bin/bash
# lib/api-manager.sh
# API Server Management for Hostfy

# ========================================
# Configuration
# ========================================
API_DIR="$COMMANDS_DIR/api"
API_PID_FILE="$API_DIR/server.pid"
API_LOG_FILE="$LOGS_DIR/api.log"
CONFIG_DIR="$(dirname "$COMMANDS_DIR")/config"
API_KEY_FILE="$CONFIG_DIR/api.key"

# ========================================
# API Management Functions
# ========================================

api_install() {
    log_step "Installing API dependencies..."
    
    if ! command -v npm &> /dev/null; then
        log_error "npm is required but not installed."
        return 1
    fi

    cd "$API_DIR"
    if npm install; then
        log_success "API dependencies installed"
    else
        log_error "Failed to install API dependencies"
        return 1
    fi
    cd "$COMMANDS_DIR"
}

api_start() {
    log_step "Starting API server..."

    if [[ -f "$API_PID_FILE" ]]; then
        local pid=$(cat "$API_PID_FILE")
        if ps -p "$pid" > /dev/null; then
            log_warning "API server is already running (PID: $pid)"
            return 0
        else
            rm "$API_PID_FILE"
        fi
    fi

    # Check dependencies
    if [[ ! -d "$API_DIR/node_modules" ]]; then
        api_install
    fi

    # Start server
    cd "$API_DIR"
    
    # Generate or load API key
    if [[ -n "${HOSTFY_API_KEY:-}" ]]; then
        # Use provided environment variable
        export API_KEY="$HOSTFY_API_KEY"
        log_info "Using API Key from environment variable"
    elif [[ -f "$API_KEY_FILE" ]]; then
        # Load from file
        export API_KEY=$(cat "$API_KEY_FILE")
        log_info "Loaded API Key from $API_KEY_FILE"
    else
        # Generate new key and save to file
        log_warning "API Key not found. Generating a new one..."
        mkdir -p "$CONFIG_DIR"
        HOSTFY_API_KEY=$(openssl rand -hex 16)
        echo "$HOSTFY_API_KEY" > "$API_KEY_FILE"
        chmod 600 "$API_KEY_FILE"
        export API_KEY="$HOSTFY_API_KEY"
        log_success "Generated new API Key and saved to $API_KEY_FILE"
    fi
    
    nohup npm start > "$API_LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$API_PID_FILE"
    
    log_success "API server started on port 3000 (PID: $pid)"
    log_info "Logs available at: $API_LOG_FILE"
    
    cd "$COMMANDS_DIR"
}

api_stop() {
    log_step "Stopping API server..."

    if [[ ! -f "$API_PID_FILE" ]]; then
        log_warning "API server is not running (PID file not found)"
        return 0
    fi

    local pid=$(cat "$API_PID_FILE")
    if kill "$pid" 2>/dev/null; then
        rm "$API_PID_FILE"
        log_success "API server stopped"
    else
        log_error "Failed to stop API server (PID: $pid)"
        # Check if process exists
        if ! ps -p "$pid" > /dev/null; then
            log_info "Process was not running, removing PID file"
            rm "$API_PID_FILE"
        fi
    fi
}

api_status() {
    if [[ -f "$API_PID_FILE" ]]; then
        local pid=$(cat "$API_PID_FILE")
        if ps -p "$pid" > /dev/null; then
            log_success "API server is running (PID: $pid)"
            echo "Port: 3000"
            return 0
        else
            log_warning "PID file exists but process is not running"
            return 1
        fi
    else
        log_info "API server is not running"
        return 1
    fi
}
