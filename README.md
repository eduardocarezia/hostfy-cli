# 🚀 Hostfy - Container Management System

<div align="center">

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Docker](https://img.shields.io/badge/docker-20.10+-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)

**Sistema completo de gerenciamento de containers Docker com Traefik, descoberta via catálogo e domínios dinâmicos.**

[Quick Start](#-quick-start) •
[Documentação](#-comandos-principais) •
[Exemplos](#-exemplos-de-uso) •
[Troubleshooting](#-troubleshooting) •
[Contribuir](#-contribuindo)

</div>

---

## 📋 Índice

- [Quick Start](#-quick-start)
- [Features](#-features)
- [Containers Disponíveis](#-containers-disponíveis-no-catálogo)
- [Comandos Principais](#-comandos-principais)
- [Exemplos de Uso](#-exemplos-de-uso)
- [Arquitetura](#-arquitetura)
- [Requisitos](#-requisitos-do-sistema)
- [Configuração](#-configuração-avançada)
- [Domínios e SSL](#-domínios-e-ssl)
- [Backup e Restore](#-backup-e-restore)
- [Segurança](#-segurança)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)
- [Contribuindo](#-contribuindo)

---

## ⚡ Quick Start

### Instalação em 1 Comando

```bash
# Baixar e executar o script de instalação
curl -fsSL https://github.com/eduardocarezia/hostfy-cli/raw/refs/heads/main/initialize.sh | bash
```

Ou baixar primeiro e executar depois:

```bash
# Baixar
curl -fsSL https://github.com/eduardocarezia/hostfy-cli/raw/refs/heads/main/initialize.sh -o initialize.sh

# Executar
chmod +x initialize.sh
./initialize.sh
```

O script vai:
- ✅ Verificar dependências (Docker, jq, curl)
- ✅ Baixar todos os arquivos necessários do GitHub
- ✅ Criar estrutura de diretórios
- ✅ Configurar rede Docker (`hostfy-network`)
- ✅ Instalar e iniciar Traefik com SSL automático
- ✅ Configurar templates de containers
- ✅ Baixar catálogo de containers

### Após a Instalação

```bash
# Explorar catálogo disponível
./hostfy catalog list

# Buscar containers específicos
./hostfy catalog search whatsapp

# Ver detalhes completos de um container
./hostfy catalog info n8n

# Instalar container do catálogo
./hostfy install n8n --with-deps --interactive
```

---

## ✨ Features

### 🎯 Core Features
- ✅ **Instalação Zero-Config**: Bootstrap automático com um único comando
- ✅ **Catálogo de Containers**: Discovery de aplicações pré-configuradas
- ✅ **Traefik Integrado**: Reverse proxy automático com SSL via Let's Encrypt
- ✅ **Domínios Dinâmicos**: Adicione/remova domínios sem reiniciar containers
- ✅ **Gestão de Dependências**: Instalação automática de dependências (Postgres, Redis)
- ✅ **Templates Inteligentes**: Configuração automatizada baseada em templates
- ✅ **Rede Isolada**: Todos containers em rede Docker dedicada

### 🔧 Operações Suportadas
- 🔄 Lifecycle completo: install, update, delete, restart, pause, resume
- 📊 Monitoramento: status, logs, health checks
- 🌐 Domínios: adicionar, remover, listar
- 📦 Catálogo: atualizar, buscar, filtrar por categoria
- 🔍 Discovery: encontrar containers por termo de busca
- 📋 Registry: tracking de containers e domínios instalados

### 🛡️ Segurança & Produção
- 🔐 SSL automático via Let's Encrypt
- 🔒 Isolamento de rede entre containers
- 📝 Health checks automáticos
- 🔄 Rollback seguro em caso de falha
- 📊 Logs centralizados
- ⚙️ Configuração via variáveis de ambiente

---

## 📦 Containers Disponíveis no Catálogo

### 🗄️ Infraestrutura Base
- **PostgreSQL 16-alpine** - Banco de dados relacional robusto
  - Otimizado para produção
  - Persistência de dados com volumes
  - Health checks configurados

- **Redis 7-alpine** - Cache e message broker
  - Key-value store in-memory
  - Persistência opcional (AOF/RDB)
  - Suporte a pub/sub

### 🔄 Automação & Workflows
- **n8n** - Workflow automation tool (Low-code)
  - Alternativa open-source ao Zapier
  - 350+ integrações nativas
  - Execução de workflows complexos
  - Interface web intuitiva
  - Suporte a webhooks e APIs

### 📱 Messaging & Communication
- **Evolution API** - WhatsApp Multi-Device API completa
  - API REST completa para WhatsApp
  - Multi-device support
  - Webhooks para eventos
  - Envio de mídia (imagens, vídeos, áudios)
  - Grupos e listas de transmissão
  - QR Code para conexão

### 💬 Customer Support & CRM
- **Chatwoot** - Plataforma omnichannel de atendimento
  - Alternativa open-source ao Intercom
  - Suporte a múltiplos canais (WhatsApp, Email, Web)
  - Caixas de entrada compartilhadas
  - Chatbots e automação
  - Integrações com CRMs
  - Relatórios e analytics

---

## 🛠️ Comandos Principais

### Container Operations

```bash
# Instalar container do catálogo
./hostfy install <name> [options]

# Instalar container customizado
./hostfy install <name> --image <image:tag> [options]

# Atualizar container existente
./hostfy update <name>

# Remover container
./hostfy delete <name>              # Mantém volumes
./hostfy delete <name> --volumes    # Remove volumes também

# Reiniciar container
./hostfy restart <name>

# Pausar/Resumir containers
./hostfy pause <name>
./hostfy resume <name>

# Listar todos containers instalados
./hostfy list

# Ver status detalhado de um container
./hostfy status <name>

# Ver logs do container
./hostfy logs <name>                 # Últimas 50 linhas
./hostfy logs <name> --follow        # Seguir logs em tempo real
./hostfy logs <name> --tail 100      # Últimas 100 linhas
```

### Domain Management

```bash
# Adicionar domínio a um container
./hostfy domain <name> --add example.com
./hostfy domain <name> --add api.example.com --port 8080

# Remover domínio de um container
./hostfy domain <name> --remove example.com

# Listar todos domínios de um container
./hostfy domain <name> --list
```

### Catalog Discovery

```bash
# Atualizar catálogo do GitHub
./hostfy catalog update

# Listar todos containers disponíveis
./hostfy catalog list

# Filtrar por categoria
./hostfy catalog list --category automation
./hostfy catalog list --category messaging
./hostfy catalog list --category database
./hostfy catalog list --category cache
./hostfy catalog list --category customer-support

# Buscar por termo
./hostfy catalog search workflow
./hostfy catalog search whatsapp
./hostfy catalog search automation

# Ver detalhes completos de um container
./hostfy catalog info n8n
./hostfy catalog info evolution-api
./hostfy catalog info chatwoot

# Ver versões disponíveis
./hostfy catalog versions n8n

# Listar todas categorias
./hostfy catalog categories

# Estatísticas do catálogo
./hostfy catalog stats
```

### System Commands

```bash
# (Re)Inicializar sistema Hostfy
./hostfy init

# Ver versão do Hostfy
./hostfy version

# Ver ajuda
./hostfy help
./hostfy --help
./hostfy -h
```

---

## 💡 Exemplos de Uso

### Exemplo 1: Instalar n8n (Workflow Automation)

```bash
# Opção 1: Instalação interativa (recomendado para primeira vez)
./hostfy install n8n \
  --with-deps \
  --interactive \
  --domain n8n.myapp.com

# Opção 2: Instalação com variáveis explícitas
./hostfy install n8n \
  --with-deps \
  --domain n8n.myapp.com \
  --env N8N_BASIC_AUTH_ACTIVE=true \
  --env N8N_BASIC_AUTH_USER=admin \
  --env N8N_BASIC_AUTH_PASSWORD=senha-segura \
  --env WEBHOOK_URL=https://n8n.myapp.com

# Acessar
# https://n8n.myapp.com
```

**O que acontece:**
1. Instala PostgreSQL (dependência)
2. Cria banco de dados `n8n`
3. Configura n8n com conexão ao banco
4. Gera configuração Traefik com SSL
5. Inicia container e aguarda health check

### Exemplo 2: Instalar Evolution API (WhatsApp)

```bash
# Gerar token de autenticação seguro
API_KEY=$(openssl rand -hex 32)

# Instalar com todas dependências
./hostfy install evolution-api \
  --with-deps \
  --domain evolution.myapp.com \
  --env AUTHENTICATION_API_KEY=$API_KEY \
  --env SERVER_URL=https://evolution.myapp.com \
  --env DATABASE_ENABLED=true \
  --env REDIS_ENABLED=true \
  --env RABBITMQ_ENABLED=false

# Guardar o API_KEY em local seguro!
echo "Evolution API Key: $API_KEY" >> ~/evolution-credentials.txt

# Testar API
curl -X GET https://evolution.myapp.com/instance/fetchInstances \
  -H "apikey: $API_KEY"

# Conectar WhatsApp
curl -X POST https://evolution.myapp.com/instance/create \
  -H "apikey: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "minha-instancia",
    "token": "token-da-instancia"
  }'
```

### Exemplo 3: Instalar Chatwoot (Atendimento)

```bash
# Gerar chaves seguras
SECRET_KEY=$(openssl rand -hex 64)
POSTGRES_PASSWORD=$(openssl rand -base64 32)

# Instalar com configuração completa
./hostfy install chatwoot \
  --with-deps \
  --domain chatwoot.myapp.com \
  --env SECRET_KEY_BASE=$SECRET_KEY \
  --env FRONTEND_URL=https://chatwoot.myapp.com \
  --env POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  --env MAILER_SENDER_EMAIL=noreply@myapp.com \
  --env SMTP_ADDRESS=smtp.sendgrid.net \
  --env SMTP_PORT=587 \
  --env SMTP_USERNAME=apikey \
  --env SMTP_PASSWORD=sua-api-key-sendgrid

# Criar primeira conta (executar após instalação)
docker exec -it chatwoot bundle exec rails runner '
  user = User.new(
    email: "admin@myapp.com",
    password: "senha-inicial-123",
    name: "Administrador"
  )
  user.skip_confirmation!
  user.save!
  Account.create!(name: "Minha Empresa")
'

# Acessar: https://chatwoot.myapp.com
```

### Exemplo 4: Stack Completo (WhatsApp + Automação + Atendimento)

```bash
#!/bin/bash
# deploy-stack.sh - Deploy completo de stack de atendimento

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Iniciando deploy da stack completa...${NC}\n"

# 1. Infraestrutura base
echo -e "${GREEN}📦 Instalando infraestrutura base...${NC}"
./hostfy install postgres --env POSTGRES_PASSWORD=$(openssl rand -base64 32)
./hostfy install redis --env REDIS_PASSWORD=$(openssl rand -base64 32)

# Aguardar containers ficarem healthy
sleep 10

# 2. Criar bancos de dados
echo -e "${GREEN}🗄️  Criando bancos de dados...${NC}"
docker exec postgres psql -U admin -c "CREATE DATABASE n8n;"
docker exec postgres psql -U admin -c "CREATE DATABASE evolution;"
docker exec postgres psql -U admin -c "CREATE DATABASE chatwoot;"

# 3. Instalar aplicações
echo -e "${GREEN}🔧 Instalando n8n...${NC}"
./hostfy install n8n --domain n8n.myapp.com --interactive

echo -e "${GREEN}📱 Instalando Evolution API...${NC}"
./hostfy install evolution-api --domain evolution.myapp.com --interactive

echo -e "${GREEN}💬 Instalando Chatwoot...${NC}"
./hostfy install chatwoot --domain chatwoot.myapp.com --interactive

# 4. Verificar instalação
echo -e "${GREEN}✅ Verificando instalação...${NC}"
./hostfy list

echo -e "${BLUE}🎉 Deploy concluído!${NC}\n"
echo "Serviços disponíveis:"
echo "  - n8n: https://n8n.myapp.com"
echo "  - Evolution API: https://evolution.myapp.com"
echo "  - Chatwoot: https://chatwoot.myapp.com"
echo "  - Traefik Dashboard: http://traefik.localhost:8080"
```

### Exemplo 5: Container Customizado (Não está no catálogo)

```bash
# Instalar aplicação customizada
./hostfy install myapp \
  --image mycompany/myapp:v1.2.3 \
  --port 3000 \
  --domain myapp.example.com \
  --volume ./data:/app/data \
  --volume ./config:/app/config \
  --env NODE_ENV=production \
  --env DATABASE_URL=postgresql://user:pass@postgres:5432/myapp \
  --env REDIS_URL=redis://redis:6379

# Adicionar domínio adicional depois
./hostfy domain myapp --add api.myapp.com --port 3000
./hostfy domain myapp --add admin.myapp.com --port 3000
```

### Exemplo 6: Desenvolvimento Local

```bash
# Instalar para desenvolvimento (sem domínio real)
./hostfy install n8n --env N8N_HOST=localhost

# Acessar via localhost
# http://localhost:5678

# Ver logs em tempo real
./hostfy logs n8n --follow

# Reiniciar após mudanças
./hostfy restart n8n
```

---

## 🏗️ Arquitetura

### Componentes Principais

```
┌─────────────────────────────────────────────────────────────┐
│                     Hostfy CLI (Bash)                       │
├─────────────────────────────────────────────────────────────┤
│  • Container Manager    • Domain Manager                    │
│  • Catalog Manager      • Network Manager                   │
│  • Template Engine      • Utils & Registry                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    Docker Network (hostfy-network)          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌─────────────┐ │
│  │   Traefik    │←───│  Container1  │    │ Container2  │ │
│  │ (Port 80/443)│    │   (n8n)      │    │ (Evolution) │ │
│  └──────────────┘    └──────────────┘    └─────────────┘ │
│         ↑                    ↓                    ↓        │
│         │            ┌──────────────┐    ┌─────────────┐ │
│         │            │  PostgreSQL  │    │    Redis    │ │
│         │            └──────────────┘    └─────────────┘ │
│         │                                                  │
└─────────┼──────────────────────────────────────────────────┘
          │
          ↓
     Internet (SSL via Let's Encrypt)
```

### Fluxo de Instalação

```
1. Bootstrap (initialize.sh)
   ↓
2. Validar Dependências (Docker, jq, curl)
   ↓
3. Download de Arquivos do GitHub
   ↓
4. Criação de Estrutura de Diretórios
   ↓
5. Setup de Rede Docker (hostfy-network)
   ↓
6. Instalação do Traefik
   ↓
7. Configuração de Templates
   ↓
8. Download do Catálogo
   ↓
9. Sistema Pronto ✅
```

### Fluxo de Container Lifecycle

```
Install Request
   ↓
1. Validar nome do container
   ↓
2. Verificar se existe no catálogo
   ↓
3. Resolver dependências (se --with-deps)
   ↓
4. Coletar variáveis de ambiente (se --interactive)
   ↓
5. Gerar docker-compose.yml do template
   ↓
6. Aplicar labels do Traefik (se --domain)
   ↓
7. Registrar no containers.json
   ↓
8. docker compose up -d
   ↓
9. Aguardar health check
   ↓
10. Confirmar instalação ✅
```

---

## 🔧 Requisitos do Sistema

### Obrigatórios

- ✅ **Docker** (v20.10+)
  - macOS: [Docker Desktop](https://docs.docker.com/desktop/mac/install/)
  - Linux: [Docker Engine](https://docs.docker.com/engine/install/)
  - Windows: [Docker Desktop](https://docs.docker.com/desktop/windows/install/)

- ✅ **Docker Compose** (v2.0+ ou v1.29+)
  - Geralmente incluído com Docker Desktop
  - Linux: `sudo apt-get install docker-compose-plugin`

- ✅ **jq** - JSON processor (v1.6+)
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt-get install jq`
  - CentOS/RHEL: `sudo yum install jq`
  - Alpine: `apk add jq`

- ✅ **curl** - Geralmente pré-instalado
  - Linux: `sudo apt-get install curl`

### Recomendados

- 🔹 **openssl** - Para gerar tokens/senhas seguras
- 🔹 **git** - Para contribuir com o projeto
- 🔹 **lsof** - Para debug de portas

### Hardware Mínimo

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Disco | 20 GB | 50+ GB SSD |
| Rede | 10 Mbps | 100+ Mbps |

### Verificar Instalação

```bash
# Script de verificação completa
cat << 'EOF' > check-requirements.sh
#!/bin/bash

echo "🔍 Verificando requisitos do Hostfy..."
echo ""

# Docker
if command -v docker &> /dev/null; then
    docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    echo "✅ Docker: $docker_version"
else
    echo "❌ Docker: não instalado"
fi

# Docker Compose
if docker compose version &> /dev/null; then
    compose_version=$(docker compose version --short)
    echo "✅ Docker Compose: $compose_version"
elif command -v docker-compose &> /dev/null; then
    compose_version=$(docker-compose --version | awk '{print $3}' | sed 's/,//')
    echo "✅ Docker Compose: $compose_version (standalone)"
else
    echo "❌ Docker Compose: não instalado"
fi

# jq
if command -v jq &> /dev/null; then
    jq_version=$(jq --version | sed 's/jq-//')
    echo "✅ jq: $jq_version"
else
    echo "❌ jq: não instalado"
fi

# curl
if command -v curl &> /dev/null; then
    curl_version=$(curl --version | head -1 | awk '{print $2}')
    echo "✅ curl: $curl_version"
else
    echo "❌ curl: não instalado"
fi

# openssl (opcional)
if command -v openssl &> /dev/null; then
    openssl_version=$(openssl version | awk '{print $2}')
    echo "✅ openssl: $openssl_version"
else
    echo "⚠️  openssl: não instalado (opcional)"
fi

echo ""
echo "📊 Sistema:"
echo "  OS: $(uname -s)"
echo "  Kernel: $(uname -r)"
echo "  Arch: $(uname -m)"

EOF

chmod +x check-requirements.sh
./check-requirements.sh
```

---

## ⚙️ Configuração Avançada

### Variáveis de Ambiente Globais

```bash
# Configurar antes de executar comandos

# Habilitar modo debug (logs detalhados)
export HOSTFY_DEBUG=true

# Pular confirmações interativas
export HOSTFY_FORCE=true

# Customizar nome da rede Docker
export HOSTFY_NETWORK=minha-rede-custom

# URL customizada do catálogo
export CATALOG_URL=https://meuservidor.com/catalog.json

# Diretório raiz customizado
export HOSTFY_ROOT=/opt/hostfy
```

### Customizar Traefik

Editar configuração do Traefik:

```bash
# Editar docker-compose do Traefik
nano docker/traefik/docker-compose.yml

# Editar configuração estática
nano docker/traefik/traefik.yml

# Reiniciar Traefik
docker compose -f docker/traefik/docker-compose.yml restart
```

**Exemplo: Adicionar middleware de autenticação**

```yaml
# docker/traefik/traefik.yml
http:
  middlewares:
    basic-auth:
      basicAuth:
        users:
          - "admin:$apr1$xyz..."  # htpasswd format
```

### Templates Customizados

Criar templates próprios para containers:

```bash
# Template customizado
cat > docker/templates/minha-app.yml << 'EOF'
version: '3.8'

services:
  {{CONTAINER_NAME}}:
    image: {{IMAGE}}
    container_name: {{CONTAINER_NAME}}
    restart: unless-stopped
    networks:
      - hostfy-network
    environment:
      - NODE_ENV=production
      - API_URL={{API_URL}}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.{{CONTAINER_NAME}}.rule=Host(\`{{DOMAIN}}\`)"
      - "traefik.http.services.{{CONTAINER_NAME}}.loadbalancer.server.port={{PORT}}"
    volumes:
      - {{CONTAINER_NAME}}-data:/app/data

volumes:
  {{CONTAINER_NAME}}-data:

networks:
  hostfy-network:
    external: true
EOF

# Usar template customizado
./hostfy install minha-app --template docker/templates/minha-app.yml
```

---

## 🌐 Domínios e SSL

### Configuração de DNS

**Para usar domínios em produção:**

1. **Aponte o DNS para seu servidor:**
   ```
   Tipo A: n8n.myapp.com → 123.45.67.89
   Tipo A: evolution.myapp.com → 123.45.67.89
   Tipo A: *.myapp.com → 123.45.67.89  (wildcard)
   ```

2. **Aguarde propagação do DNS (pode levar até 48h)**
   ```bash
   # Verificar DNS
   dig n8n.myapp.com
   nslookup n8n.myapp.com
   ```

3. **Instale o container com o domínio**
   ```bash
   ./hostfy install n8n --domain n8n.myapp.com
   ```

4. **Traefik gerará SSL automaticamente via Let's Encrypt**

### SSL Certificates (Let's Encrypt)

O Traefik gerencia SSL automaticamente:

```yaml
# docker/traefik/traefik.yml
certificatesResolvers:
  letsencrypt:
    acme:
      email: seu-email@exemplo.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
```

**Certificados são salvos em:**
```
docker/traefik/acme.json
```

**Para usar certificados customizados:**

```bash
# Adicionar certificado customizado
mkdir -p docker/traefik/certs
cp meu-certificado.crt docker/traefik/certs/
cp minha-chave.key docker/traefik/certs/

# Configurar no traefik.yml
# tls:
#   certificates:
#     - certFile: /certs/meu-certificado.crt
#       keyFile: /certs/minha-chave.key
```

### Múltiplos Domínios

```bash
# Container com múltiplos domínios
./hostfy install n8n --domain n8n.myapp.com

# Adicionar domínios adicionais
./hostfy domain n8n --add automation.myapp.com
./hostfy domain n8n --add workflows.myapp.com

# Listar todos domínios
./hostfy domain n8n --list

# Resultado:
# n8n.myapp.com
# automation.myapp.com
# workflows.myapp.com
```

---

## 💾 Backup e Restore

### Backup Manual

```bash
#!/bin/bash
# backup.sh - Backup completo do Hostfy

BACKUP_DIR="$HOME/hostfy-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "🔄 Iniciando backup..."

# 1. Backup de configurações
cp -r config/ "$BACKUP_DIR/config/"
cp -r docker/ "$BACKUP_DIR/docker/"

# 2. Backup de volumes Docker
docker run --rm \
  -v hostfy-postgres-data:/source:ro \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf /backup/postgres-data.tar.gz -C /source .

docker run --rm \
  -v hostfy-redis-data:/source:ro \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf /backup/redis-data.tar.gz -C /source .

# 3. Dump de bancos de dados
docker exec postgres pg_dumpall -U admin > "$BACKUP_DIR/postgres-dump.sql"

# 4. Backup de certificados SSL
cp docker/traefik/acme.json "$BACKUP_DIR/"

echo "✅ Backup concluído em: $BACKUP_DIR"
```

### Restore de Backup

```bash
#!/bin/bash
# restore.sh - Restaurar backup do Hostfy

BACKUP_DIR="$1"

if [[ -z "$BACKUP_DIR" ]]; then
    echo "Uso: ./restore.sh <diretorio-backup>"
    exit 1
fi

echo "⚠️  Isso vai sobrescrever a instalação atual!"
read -p "Continuar? (y/N): " confirm
[[ "$confirm" != "y" ]] && exit 0

echo "🔄 Iniciando restore..."

# 1. Parar todos containers
./hostfy list | grep -v "NAME" | awk '{print $1}' | xargs -I {} ./hostfy pause {}

# 2. Restaurar configurações
cp -r "$BACKUP_DIR/config/" ./
cp -r "$BACKUP_DIR/docker/" ./

# 3. Restaurar volumes
docker run --rm \
  -v hostfy-postgres-data:/target \
  -v "$BACKUP_DIR":/backup \
  alpine sh -c "cd /target && tar xzf /backup/postgres-data.tar.gz"

docker run --rm \
  -v hostfy-redis-data:/target \
  -v "$BACKUP_DIR":/backup \
  alpine sh -c "cd /target && tar xzf /backup/redis-data.tar.gz"

# 4. Restaurar dump de banco
docker exec -i postgres psql -U admin < "$BACKUP_DIR/postgres-dump.sql"

# 5. Restaurar certificados
cp "$BACKUP_DIR/acme.json" docker/traefik/
chmod 600 docker/traefik/acme.json

# 6. Reiniciar containers
./hostfy list | grep -v "NAME" | awk '{print $1}' | xargs -I {} ./hostfy resume {}

echo "✅ Restore concluído!"
```

### Backup Automático (Cron)

```bash
# Criar script de backup automático
cat > /usr/local/bin/hostfy-backup.sh << 'EOF'
#!/bin/bash
BACKUP_BASE="$HOME/hostfy-backups"
KEEP_DAYS=30

# Executar backup
cd /path/to/hostfy
./backup.sh

# Limpar backups antigos
find "$BACKUP_BASE" -type d -mtime +$KEEP_DAYS -exec rm -rf {} +
EOF

chmod +x /usr/local/bin/hostfy-backup.sh

# Adicionar ao crontab (backup diário às 2AM)
crontab -e
# Adicionar linha:
# 0 2 * * * /usr/local/bin/hostfy-backup.sh >> /var/log/hostfy-backup.log 2>&1
```

---

## 🔒 Segurança

### Checklist de Segurança

- [ ] **Firewall configurado** - Permitir apenas portas 80, 443, 22
- [ ] **SSH com chave pública** - Desabilitar senha
- [ ] **Fail2ban instalado** - Proteção contra brute force
- [ ] **SSL/TLS ativo** - Certificados válidos
- [ ] **Senhas fortes** - Usar `openssl rand -base64 32`
- [ ] **Volumes com permissões corretas** - Evitar root desnecessário
- [ ] **Backups regulares** - Automatizar e testar restore
- [ ] **Updates do sistema** - `apt update && apt upgrade`
- [ ] **Monitoramento ativo** - Logs e alertas
- [ ] **Rate limiting no Traefik** - Prevenir DDoS

### Configurar Firewall (UFW)

```bash
# Instalar UFW
sudo apt-get install ufw

# Regras básicas
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Permitir SSH (ajustar porta se customizada)
sudo ufw allow 22/tcp

# Permitir HTTP e HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Ativar firewall
sudo ufw enable

# Verificar status
sudo ufw status
```

### Hardening do Docker

```bash
# 1. Executar daemon Docker como usuário não-root
sudo usermod -aG docker $USER

# 2. Limitar recursos de containers
# Adicionar ao docker-compose.yml:
services:
  myapp:
    mem_limit: 512m
    cpus: '0.5'

# 3. Usar imagens oficiais e verificadas
# Preferir imagens do Docker Hub Official ou Verified Publisher

# 4. Scan de vulnerabilidades
docker scan myimage:tag

# 5. Não expor Docker socket
# Evitar: -v /var/run/docker.sock:/var/run/docker.sock
```

### Secrets Management

```bash
# Usar Docker secrets ao invés de environment variables

# 1. Criar secret
echo "minha-senha-super-secreta" | docker secret create db_password -

# 2. Usar no compose
services:
  myapp:
    secrets:
      - db_password
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password

secrets:
  db_password:
    external: true
```

### Rate Limiting no Traefik

```yaml
# docker/traefik/traefik.yml
http:
  middlewares:
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1m
```

---

## 🔍 Troubleshooting

### Problema: Docker daemon not running

**Sintomas:**
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

**Solução:**
```bash
# macOS/Windows: Abrir Docker Desktop e aguardar inicialização
# Linux:
sudo systemctl status docker
sudo systemctl start docker
sudo systemctl enable docker

# Verificar se usuário está no grupo docker
groups $USER
sudo usermod -aG docker $USER
# Fazer logout e login novamente
```

### Problema: Porta 80/443 já em uso

**Sintomas:**
```
Error: Port 80 is already in use
```

**Solução:**
```bash
# Verificar o que está usando a porta
sudo lsof -i :80
sudo lsof -i :443
sudo netstat -tulpn | grep :80

# Parar serviço conflitante
sudo systemctl stop apache2
sudo systemctl stop nginx

# Ou mudar porta do Traefik
nano docker/traefik/docker-compose.yml
# Alterar ports:
#   - "8080:80"
#   - "8443:443"
```

### Problema: Permissões negadas

**Sintomas:**
```
Got permission denied while trying to connect to the Docker daemon socket
```

**Solução:**
```bash
# Adicionar usuário ao grupo docker
sudo usermod -aG docker $USER

# Fazer logout e login novamente
# Ou:
newgrp docker

# Verificar
docker ps
```

### Problema: Catálogo não baixa

**Sintomas:**
```
Failed to download catalog from GitHub
```

**Solução:**
```bash
# 1. Verificar conectividade
curl -I https://github.com

# 2. Tentar download manual
curl -fsSL https://github.com/eduardocarezia/hostfy-cli/raw/refs/heads/main/commands/catalog/containers-catalog.json \
  -o commands/catalog/containers-catalog.json

# 3. Validar JSON
jq empty commands/catalog/containers-catalog.json

# 4. Atualizar forçado
./hostfy catalog update
```

### Problema: SSL não funciona

**Sintomas:**
```
Certificate verification failed
Your connection is not private
```

**Solução:**
```bash
# 1. Verificar DNS
dig +short seu-dominio.com
# Deve retornar o IP do servidor

# 2. Verificar se porta 80 está acessível (Let's Encrypt precisa)
curl -I http://seu-dominio.com

# 3. Ver logs do Traefik
docker logs traefik

# 4. Verificar acme.json
ls -la docker/traefik/acme.json
# Permissões devem ser 600

# 5. Forçar renovação
docker compose -f docker/traefik/docker-compose.yml restart

# 6. Aguardar até 5 minutos para Let's Encrypt
tail -f docker/traefik/traefik.log | grep acme
```

### Problema: Container não inicia

**Sintomas:**
```
Container exits immediately
Health check failed
```

**Solução:**
```bash
# 1. Ver logs do container
./hostfy logs nome-container

# 2. Verificar health check
docker inspect nome-container | jq '.[0].State.Health'

# 3. Ver configuração gerada
cat docker/containers/nome-container.yml

# 4. Verificar se dependências estão rodando
./hostfy status postgres
./hostfy status redis

# 5. Testar conexão de rede
docker exec nome-container ping -c 3 postgres

# 6. Reiniciar com logs
docker compose -f docker/containers/nome-container.yml up

# 7. Verificar recursos
docker stats nome-container
```

### Problema: Banco de dados não conecta

**Sintomas:**
```
Connection refused
ECONNREFUSED postgres:5432
```

**Solução:**
```bash
# 1. Verificar se PostgreSQL está rodando
./hostfy status postgres
docker exec postgres pg_isready

# 2. Verificar conexão de rede
docker exec meu-container ping postgres

# 3. Verificar credenciais
docker exec postgres psql -U admin -c "SELECT version();"

# 4. Verificar se banco existe
docker exec postgres psql -U admin -c "\l"

# 5. Criar banco manualmente se necessário
docker exec postgres psql -U admin -c "CREATE DATABASE meu_app;"

# 6. Testar conexão do container
docker exec meu-container nc -zv postgres 5432
```

### Logs Detalhados

```bash
# Habilitar debug global
export HOSTFY_DEBUG=true

# Ver logs do sistema
tail -f logs/hostfy.log

# Ver logs de um container específico
./hostfy logs nome-container --follow --tail 100

# Ver logs do Traefik
docker logs traefik --follow

# Ver logs de todos containers
docker compose -f docker/containers/* logs --follow

# Filtrar erros
./hostfy logs nome-container | grep -i error
./hostfy logs nome-container | grep -i warning
```

---

## ❓ FAQ

### Instalação e Setup

**P: Posso instalar em Windows?**
R: Sim! Mas você precisa do Docker Desktop instalado. Recomendamos usar WSL2 para melhor performance.

**P: Funciona no ARM (Apple Silicon, Raspberry Pi)?**
R: Sim! A maioria das imagens do catálogo suporta ARM64. Verifique a documentação específica de cada container.

**P: Preciso ser root?**
R: Não! Basta que seu usuário esteja no grupo `docker`. Execute: `sudo usermod -aG docker $USER`

**P: Quanto espaço em disco é necessário?**
R: Mínimo 20GB, recomendado 50GB+. Cada container varia, mas PostgreSQL + Redis + 3 apps ≈ 10-15GB.

### Containers e Catálogo

**P: Como adiciono um container que não está no catálogo?**
R: Use o comando `install` com a flag `--image`:
```bash
./hostfy install meu-app --image username/meu-app:latest --port 8080
```

**P: Posso modificar o catálogo?**
R: Sim! Edite `commands/catalog/containers-catalog.json` e faça um PR no GitHub para compartilhar.

**P: Como atualizo um container para nova versão?**
R: Use `./hostfy update nome-container` ou edite a versão no arquivo compose e execute `docker compose up -d`.

**P: Containers podem se comunicar entre si?**
R: Sim! Todos estão na mesma rede (`hostfy-network`). Use o nome do container como hostname.

### Domínios e SSL

**P: Funciona com domínios localhost?**
R: Sim! Use `.localhost` (ex: `n8n.localhost`). Mas SSL só funciona com domínios reais.

**P: Posso usar wildcard DNS (\*.meuapp.com)?**
R: Sim! Configure um registro wildcard no DNS e use qualquer subdomínio.

**P: Let's Encrypt não gera certificado, por quê?**
R: Verifique se:
1. DNS aponta para seu servidor
2. Porta 80 está acessível externamente
3. Email está configurado no Traefik
4. Aguardou pelo menos 5 minutos

**P: Posso usar certificados próprios?**
R: Sim! Coloque em `docker/traefik/certs/` e configure no `traefik.yml`.

### Dependências e Integrações

**P: Como integro n8n com Evolution API?**
R: No n8n, use o nó HTTP Request com a URL `http://evolution-api:8080` e o API key configurado.

**P: Como conecto Chatwoot com WhatsApp?**
R: Instale Evolution API, configure um canal no Chatwoot e use a URL da API Evolution.

**P: Posso usar MySQL ao invés de PostgreSQL?**
R: Sim! Instale um container MySQL customizado e configure a URL de conexão nas apps.

### Performance e Recursos

**P: Quanto de RAM cada container usa?**
R: Varia muito:
- PostgreSQL: 256MB-1GB
- Redis: 50MB-200MB
- n8n: 256MB-512MB
- Evolution API: 512MB-1GB
- Chatwoot: 1GB-2GB

**P: Como limito recursos de um container?**
R: Edite o compose file e adicione:
```yaml
deploy:
  resources:
    limits:
      cpus: '0.5'
      memory: 512M
```

**P: Containers consomem muito disco, como limpar?**
R: Execute periodicamente:
```bash
docker system prune -a
docker volume prune
```

### Backup e Segurança

**P: Como faço backup automático?**
R: Configure um cronjob (veja seção [Backup e Restore](#-backup-e-restore)).

**P: Onde ficam os dados dos containers?**
R: Em volumes Docker. Liste com `docker volume ls | grep hostfy`.

**P: É seguro expor para internet?**
R: Sim, desde que:
1. Use SSL (Let's Encrypt automático)
2. Configure firewall
3. Use senhas fortes
4. Mantenha sistema atualizado
5. Faça backups regulares

### Troubleshooting

**P: Container para depois de um tempo, por quê?**
R: Pode ser falta de recursos. Verifique com `docker stats` e aumente limites se necessário.

**P: Logs dizem "Killed", o que fazer?**
R: Provavelmente OOM (Out of Memory). Aumente RAM disponível ou limite uso de outros containers.

**P: Como removo TUDO e começo do zero?**
R:
```bash
./hostfy list | awk '{print $1}' | xargs -I {} ./hostfy delete {} --volumes
docker compose -f docker/traefik/docker-compose.yml down -v
rm -rf docker/ config/ logs/
./hostfy init
```

---

## 🤝 Contribuindo

Contribuições são muito bem-vindas! Veja como você pode ajudar:

### Reportar Bugs

1. Verifique se já não existe uma [issue](https://github.com/eduardocarezia/hostfy-cli/issues)
2. Crie uma nova issue com:
   - Descrição clara do problema
   - Passos para reproduzir
   - Comportamento esperado vs atual
   - Versão do Hostfy, Docker, SO
   - Logs relevantes

### Sugerir Features

1. Abra uma issue com tag `enhancement`
2. Descreva o problema que a feature resolve
3. Proponha uma solução
4. Discuta com a comunidade

### Adicionar Container ao Catálogo

1. Fork do repositório
2. Adicione entrada em `commands/catalog/containers-catalog.json`
3. Teste a instalação:
   ```bash
   ./hostfy install seu-container --interactive
   ```
4. Documente variáveis de ambiente obrigatórias
5. Crie Pull Request com descrição detalhada

**Template de entrada no catálogo:**

```json
{
  "id": "unique-id",
  "name": "Display Name",
  "slug": "slug-for-cli",
  "description": "Brief description",
  "category": "category-name",
  "tags": ["tag1", "tag2"],
  "official": false,
  "maintainer": "Your Name <email@example.com>",
  "repository": "https://github.com/your/repo",
  "documentation": "https://docs.yourapp.com",
  "image": {
    "repository": "docker-username/image-name",
    "registry": "docker.io",
    "versions": [
      {
        "tag": "latest",
        "description": "Latest stable version",
        "recommended": true
      },
      {
        "tag": "v1.2.3",
        "description": "Specific version",
        "recommended": false
      }
    ],
    "default_version": "latest"
  },
  "ports": [
    {
      "external": 80,
      "internal": 8080,
      "protocol": "tcp",
      "description": "Web interface"
    }
  ],
  "volumes": [
    {
      "name": "data",
      "mount": "/app/data",
      "description": "Application data storage"
    }
  ],
  "environment": [
    {
      "key": "API_KEY",
      "description": "API authentication key",
      "required": true,
      "default": null,
      "secret": true,
      "example": "random-generated-key"
    },
    {
      "key": "DEBUG",
      "description": "Enable debug mode",
      "required": false,
      "default": "false",
      "secret": false,
      "example": "true"
    }
  ],
  "healthcheck": {
    "test": ["CMD", "curl", "-f", "http://localhost:8080/health"],
    "interval": "30s",
    "timeout": "10s",
    "retries": 3,
    "start_period": "40s"
  },
  "traefik": {
    "enabled": true,
    "port": 8080,
    "default_domain": "myapp.localhost",
    "middlewares": []
  },
  "dependencies": ["postgres", "redis"]
}
```

### Código de Conduta

- Seja respeitoso e inclusivo
- Aceite feedback construtivo
- Foque no que é melhor para a comunidade
- Mostre empatia

### Desenvolvimento Local

```bash
# 1. Fork e clone
git clone https://github.com/seu-usuario/hostfy-cli.git
cd hostfy-cli

# 2. Criar branch
git checkout -b feature/minha-feature

# 3. Fazer mudanças
# ... editar arquivos ...

# 4. Testar localmente
cd commands
./initialize.sh
./hostfy <seu-comando>

# 5. Commit e push
git add .
git commit -m "feat: adiciona nova feature"
git push origin feature/minha-feature

# 6. Abrir Pull Request no GitHub
```

---

## 📝 Licença

MIT License - Veja [LICENSE](LICENSE) para detalhes.

Copyright (c) 2024 Eduardo Carezia

---

## 🔗 Links Úteis

- **📦 Repositório:** https://github.com/eduardocarezia/hostfy-cli
- **🐛 Issues:** https://github.com/eduardocarezia/hostfy-cli/issues
- **💬 Discussions:** https://github.com/eduardocarezia/hostfy-cli/discussions
- **📖 Traefik Docs:** https://doc.traefik.io/traefik/
- **🐳 Docker Docs:** https://docs.docker.com/
- **🔧 n8n Docs:** https://docs.n8n.io/
- **📱 Evolution API:** https://github.com/EvolutionAPI/evolution-api
- **💬 Chatwoot:** https://www.chatwoot.com/docs/

---

## 📊 Status do Projeto

| Feature | Status |
|---------|--------|
| Container Management | ✅ Completo |
| Traefik Integration | ✅ Completo |
| Domain Management | ✅ Completo |
| Catalog System | ✅ Completo |
| SSL/Let's Encrypt | ✅ Completo |
| Health Checks | ✅ Completo |
| Backup Tools | ✅ Completo |
| Web UI | 🚧 Planejado |
| API REST | 🚧 Planejado |
| Monitoring Dashboard | 🚧 Planejado |

---

## ⭐ Star History

Se este projeto foi útil para você, considere dar uma ⭐!

[![Star History Chart](https://api.star-history.com/svg?repos=eduardocarezia/hostfy-cli&type=Date)](https://star-history.com/#eduardocarezia/hostfy-cli&Date)

---

## 🙏 Agradecimentos

Obrigado a todos que contribuíram para este projeto!

Tecnologias utilizadas:
- [Docker](https://www.docker.com/) - Containerização
- [Traefik](https://traefik.io/) - Reverse Proxy & SSL
- [jq](https://stedolan.github.io/jq/) - JSON Processing
- [n8n](https://n8n.io/) - Workflow Automation
- [Evolution API](https://github.com/EvolutionAPI/evolution-api) - WhatsApp API
- [Chatwoot](https://www.chatwoot.com/) - Customer Support

---

<div align="center">

**Feito com ❤️ por [Eduardo Carezia](https://github.com/eduardocarezia)**

[⬆ Voltar ao topo](#-hostfy---container-management-system)

</div>
