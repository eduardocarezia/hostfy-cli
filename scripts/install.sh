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
echo -e "${CYAN}║${NC}      ${BOLD}hostfy${NC} - Self-hosted Made Simple   ${CYAN}║${NC}"
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

# 2. Instalar hostfy
info "[2/5] Instalando hostfy..."

# Instalar Go se não existir
if ! command -v go &> /dev/null; then
    log "Instalando Go..."
    GO_VERSION="1.21.5"
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    log "Go instalado ✓"
fi

# Clonar e compilar
log "Compilando hostfy..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git clone "https://github.com/${GITHUB_REPO}.git" . || error "Falha ao clonar repositório"
/usr/local/go/bin/go mod tidy
/usr/local/go/bin/go build -ldflags "-s -w" -o "${HOSTFY_BIN}" ./cmd/hostfy
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
echo -e "${GREEN}║${NC}    ${BOLD}hostfy instalado com sucesso!${NC} 🎉     ${GREEN}║${NC}"
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
