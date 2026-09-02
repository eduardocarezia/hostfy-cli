#!/bin/bash
set -e

HOSTFY_BIN="/usr/local/bin/hostfy"
HOSTFY_DIR="/etc/hostfy"
GITHUB_REPO="${GITHUB_REPO:-eduardocarezia/hostfy-cli}"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${GREEN}[hostfy]${NC} $1"; }
warn() { echo -e "${YELLOW}[hostfy]${NC} $1"; }
error() { echo -e "${RED}[hostfy]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[hostfy]${NC} $1"; }

# Header
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}     ${BOLD}hostfy${NC} - Self-hosted Made Simple   ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# Verificar root
if [ "$EUID" -ne 0 ]; then
    error "Este script precisa ser executado como root (sudo)"
fi

# Detectar arquitetura
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l) ARCH="arm" ;;
    *) error "Arquitetura não suportada: $ARCH" ;;
esac

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
if [ "$OS" != "linux" ]; then
    error "Sistema operacional não suportado: $OS (apenas Linux)"
fi

log "Detectado: ${OS}/${ARCH}"
log "Instalando hostfy..."
echo ""

# 1. Verificar/Instalar Docker
info "[1/5] Verificando Docker..."
if ! command -v docker &> /dev/null; then
    log "Docker não encontrado. Instalando..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log "Docker instalado ✓"
else
    DOCKER_VERSION=$(docker --version | cut -d ' ' -f3 | tr -d ',')
    log "Docker já instalado (${DOCKER_VERSION}) ✓"
fi

# Verificar se Docker está rodando
if ! docker info &> /dev/null; then
    log "Iniciando Docker..."
    systemctl start docker
fi

# Configurar Docker para aceitar API 1.24 (compatibilidade com Traefik)
log "Configurando compatibilidade Docker API..."
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/api-version.conf << 'EOF'
[Service]
Environment="DOCKER_MIN_API_VERSION=1.24"
EOF
systemctl daemon-reload
systemctl restart docker
log "Docker API configurado ✓"

# 2. Instalar hostfy
info "[2/5] Instalando hostfy..."

# Instalar Go se não existir ou se versão for antiga (< 1.25)
GO_VERSION="1.25.0"
GO_MIN_MAJOR=1
GO_MIN_MINOR=25
NEED_GO_INSTALL=0

if [ ! -x /usr/local/go/bin/go ]; then
    NEED_GO_INSTALL=1
else
    CURRENT_GO=$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
    CURRENT_MAJOR=$(echo "$CURRENT_GO" | cut -d. -f1)
    CURRENT_MINOR=$(echo "$CURRENT_GO" | cut -d. -f2)
    if [ "$CURRENT_MAJOR" -lt "$GO_MIN_MAJOR" ] || \
       { [ "$CURRENT_MAJOR" -eq "$GO_MIN_MAJOR" ] && [ "$CURRENT_MINOR" -lt "$GO_MIN_MINOR" ]; }; then
        warn "Go $CURRENT_GO é antigo, atualizando para $GO_VERSION"
        NEED_GO_INSTALL=1
    else
        log "Go $CURRENT_GO já instalado ✓"
    fi
fi

if [ "$NEED_GO_INSTALL" -eq 1 ]; then
    log "Instalando Go ${GO_VERSION}..."
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
    log "Go ${GO_VERSION} instalado ✓"
fi
export PATH=/usr/local/go/bin:$PATH

# Baixar e compilar
log "Compilando hostfy..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
# Tarball HTTPS: evita o bug Git 2.34 + HTTP/2 do Ubuntu 22.04 (exit 128).
if ! curl -fsSL "https://codeload.github.com/${GITHUB_REPO}/tar.gz/refs/heads/main" | tar -xz --strip-components=1; then
    warn "Download via HTTPS falhou, tentando git clone (HTTP/1.1)..."
    GIT_TERMINAL_PROMPT=0 git -c http.version=HTTP/1.1 clone --depth 1 "https://github.com/${GITHUB_REPO}.git" . \
        || error "Falha ao baixar repositório"
fi
log "Baixando dependências..."
# go.sum é commitado: download é determinístico (sem mutar go.mod). GOTOOLCHAIN=auto
# permite ao Go local baixar toolchain mais nova se a directive em go.mod exigir,
# garantindo que o build não trava se Go local for menor que o pinado em go.mod.
GOTOOLCHAIN=auto /usr/local/go/bin/go mod download || error "Falha ao baixar dependências"
log "Compilando binário..."
VERSION=$(tr -d '[:space:]' < VERSION 2>/dev/null || true)
VERSION=${VERSION:-dev}
GOTOOLCHAIN=auto /usr/local/go/bin/go build -ldflags "-s -w -X github.com/eduardocarezia/hostfy-cli/internal/cli.Version=${VERSION}" -o "${HOSTFY_BIN}" ./cmd/hostfy || error "Falha ao compilar binário"
chmod +x "${HOSTFY_BIN}"
cd /
rm -rf "$TEMP_DIR"
log "hostfy compilado ✓"

# 3. Criar diretórios
info "[3/5] Criando diretórios..."
mkdir -p "${HOSTFY_DIR}/apps"
chmod 755 "${HOSTFY_DIR}"
log "Diretórios criados ✓"

# 4. Criar rede Docker
info "[4/5] Configurando rede Docker..."
if ! docker network inspect hostfy_network &> /dev/null; then
    docker network create hostfy_network
    log "Rede hostfy_network criada ✓"
else
    log "Rede hostfy_network já existe ✓"
fi

# 5. Setup systemd watchdog para auto-restart
info "[5/5] Configurando watchdog service..."
cat > /etc/systemd/system/hostfy-watchdog.service << 'EOF'
[Unit]
Description=Hostfy Watchdog - Auto-restart de serviços críticos
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do \
    for container in hostfy_traefik hostfy_postgres hostfy_redis; do \
        if docker ps -q -f name="^${container}$" | grep -q .; then \
            : ; \
        else \
            if docker ps -aq -f name="^${container}$" | grep -q .; then \
                docker start "$container" 2>/dev/null || true; \
            fi; \
        fi; \
    done; \
    sleep 30; \
done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hostfy-watchdog
systemctl start hostfy-watchdog
log "Watchdog service configurado ✓"

# Finalização
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}   ${BOLD}hostfy instalado com sucesso!${NC} 🎉     ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Próximos passos:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Inicialize o hostfy:"
echo -e "     ${BOLD}hostfy init${NC}"
echo ""
echo -e "  ${CYAN}2.${NC} Veja apps disponíveis:"
echo -e "     ${BOLD}hostfy catalog${NC}"
echo ""
echo -e "  ${CYAN}3.${NC} Instale seu primeiro app:"
echo -e "     ${BOLD}hostfy install n8n --domain n8n.seudominio.com${NC}"
echo ""
echo -e "  ${CYAN}4.${NC} Configure o DNS na Cloudflare:"
echo -e "     Aponte seus subdomínios para o IP deste servidor"
echo ""
echo -e "${YELLOW}Documentação:${NC} https://github.com/${GITHUB_REPO}"
echo ""
