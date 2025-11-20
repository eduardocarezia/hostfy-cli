# 🚀 Hostfy - Container Management System

Sistema completo de gerenciamento de containers Docker com Traefik, descoberta via catálogo e domínios dinâmicos.

## ⚡ Quick Start

### Instalação em 1 Comando

```bash
# Baixar e executar o script de instalação
curl -fsSL https://github.com/eduardocarezia/hostfy-cli/raw/refs/heads/main/commands/initialize.sh | bash
```

Ou baixar primeiro e executar depois:

```bash
# Baixar
curl -fsSL https://github.com/eduardocarezia/hostfy-cli/raw/refs/heads/main/commands/initialize.sh -o initialize.sh

# Executar
chmod +x initialize.sh
./initialize.sh
```

O script vai:
- ✅ Verificar dependências (Docker, jq, curl)
- ✅ Baixar todos os arquivos necessários do GitHub
- ✅ Criar estrutura de diretórios
- ✅ Configurar rede Docker
- ✅ Instalar e iniciar Traefik
- ✅ Configurar templates
- ✅ Baixar catálogo de containers

### Após a Instalação

```bash
# Explorar catálogo
./hostfy catalog list

# Buscar containers
./hostfy catalog search whatsapp

# Ver detalhes
./hostfy catalog info n8n

# Instalar container
./hostfy install n8n --with-deps --interactive
```

---

## 📦 Containers Disponíveis no Catálogo

### 🗄️ Infraestrutura Base
- **PostgreSQL** - Banco de dados relacional
- **Redis** - Cache e key-value store

### 🔄 Automação
- **n8n** - Workflow automation tool (Low-code)

### 📱 Messaging
- **Evolution API** - WhatsApp Multi-Device API completa

### 💬 Customer Support
- **Chatwoot** - Plataforma omnichannel de atendimento

---

## 🛠️ Comandos Principais

### Container Operations

```bash
# Instalar container
./hostfy install <name> [options]

# Atualizar container
./hostfy update <name>

# Remover container
./hostfy delete <name> [--volumes]

# Reiniciar container
./hostfy restart <name>

# Pausar/Resumir
./hostfy pause <name>
./hostfy resume <name>

# Listar todos
./hostfy list

# Ver status
./hostfy status <name>

# Ver logs
./hostfy logs <name> [--follow] [--tail 100]
```

### Domain Management

```bash
# Adicionar domínio
./hostfy domain <name> --add example.com

# Remover domínio
./hostfy domain <name> --remove example.com

# Listar domínios
./hostfy domain <name> --list
```

### Catalog Discovery

```bash
# Atualizar catálogo
./hostfy catalog update

# Listar todos
./hostfy catalog list

# Filtrar por categoria
./hostfy catalog list --category automation
./hostfy catalog list --category messaging

# Buscar
./hostfy catalog search workflow
./hostfy catalog search whatsapp

# Ver detalhes
./hostfy catalog info n8n
./hostfy catalog info evolution-api

# Ver versões
./hostfy catalog versions n8n

# Ver categorias
./hostfy catalog categories

# Estatísticas
./hostfy catalog stats
```

---

## 💡 Exemplos de Uso

### Exemplo 1: Instalar n8n com dependências

```bash
# Instalação interativa (vai perguntar as variáveis obrigatórias)
./hostfy install n8n \
  --with-deps \
  --interactive \
  --domain n8n.myapp.com
```

### Exemplo 2: Instalar Evolution API

```bash
# Gerar token de autenticação
API_KEY=$(openssl rand -hex 32)

# Instalar com dependências (PostgreSQL + Redis)
./hostfy install evolution-api \
  --with-deps \
  --domain evolution.myapp.com \
  --env AUTHENTICATION_API_KEY=$API_KEY \
  --env SERVER_URL=https://evolution.myapp.com
```

### Exemplo 3: Instalar Chatwoot

```bash
# Gerar secret key
SECRET_KEY=$(openssl rand -hex 64)

# Instalar
./hostfy install chatwoot \
  --with-deps \
  --domain chatwoot.myapp.com \
  --env SECRET_KEY_BASE=$SECRET_KEY \
  --env FRONTEND_URL=https://chatwoot.myapp.com \
  --env POSTGRES_PASSWORD=senha-postgres
```

### Exemplo 4: Stack Completo

```bash
# 1. Infraestrutura base
./hostfy install postgres --env POSTGRES_PASSWORD=senha-segura
./hostfy install redis --env REDIS_PASSWORD=senha-redis

# 2. Criar bancos específicos
docker exec postgres psql -U admin -c "CREATE DATABASE n8n;"
docker exec postgres psql -U admin -c "CREATE DATABASE evolution;"
docker exec postgres psql -U admin -c "CREATE DATABASE chatwoot;"

# 3. Instalar aplicações
./hostfy install n8n --domain n8n.myapp.com --interactive
./hostfy install evolution-api --domain evolution.myapp.com --interactive
./hostfy install chatwoot --domain chatwoot.myapp.com --interactive

# 4. Verificar
./hostfy list
```

### Exemplo 5: Container Customizado

```bash
# Instalar container que não está no catálogo
./hostfy install myapp \
  --image nginx:latest \
  --port 80 \
  --domain myapp.example.com \
  --volume ./html:/usr/share/nginx/html
```

---

## 🌐 URLs e Acessos

### Localhost (Desenvolvimento)

Após instalação, os serviços estarão disponíveis em:

- **Traefik Dashboard:** http://traefik.localhost:8080
- **n8n:** https://n8n.localhost
- **Evolution API:** https://evolution-api.localhost
- **Chatwoot:** https://chatwoot.localhost

### Produção

Configure domínios reais usando a flag `--domain`:

```bash
./hostfy install n8n --domain n8n.meudominio.com.br
```

**Requisitos:**
- DNS apontando para o servidor
- Portas 80 e 443 abertas
- Let's Encrypt automático via Traefik

---

## 📋 Opções de Instalação

### Flags Comuns

```bash
--image <image:tag>      # Imagem do container (obrigatório para custom)
--port <port>            # Porta a expor (padrão: 80)
--domain <domain>        # Domínio para Traefik
--env KEY=VALUE          # Variável de ambiente
--env-file <path>        # Arquivo de variáveis
--volume <vol>           # Volume a montar
--with-deps              # Instalar dependências automaticamente
--interactive            # Wizard interativo para configuração
--version <tag>          # Versão específica (para catálogo)
```

### Variáveis de Ambiente

```bash
HOSTFY_DEBUG=true        # Habilitar logs debug
HOSTFY_FORCE=true        # Pular confirmações
HOSTFY_NETWORK=nome      # Nome da rede Docker
CATALOG_URL=url          # URL customizada do catálogo
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

- ✅ **jq** - JSON processor
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt-get install jq`
  - CentOS/RHEL: `sudo yum install jq`

- ✅ **curl** - Geralmente pré-instalado

### Verificar Instalação

```bash
docker --version
docker compose version
jq --version
curl --version
```

---

## 📁 Estrutura de Diretórios

Após instalação, a estrutura criada será:

```
.
├── hostfy                          # Symlink para commands/hostfy.sh
├── commands/
│   ├── initialize.sh               # Script de instalação/bootstrap
│   ├── hostfy.sh                   # CLI principal
│   ├── catalog/                    # Catálogo de containers
│   │   └── containers-catalog.json
│   └── lib/                        # Bibliotecas
│       ├── utils.sh
│       ├── network-manager.sh
│       ├── template-engine.sh
│       ├── domain-manager.sh
│       ├── container-manager.sh
│       └── catalog-manager.sh
├── docker/
│   ├── traefik/                    # Configuração Traefik
│   │   ├── docker-compose.yml
│   │   ├── traefik.yml
│   │   └── acme.json
│   ├── templates/                  # Templates de containers
│   │   ├── postgres.yml
│   │   ├── redis.yml
│   │   └── base-container.yml
│   └── containers/                 # Compose files gerados
├── config/
│   ├── containers.json             # Registry de containers instalados
│   ├── domains.json                # Registry de domínios
│   └── settings.json               # Configurações globais
└── logs/
    └── hostfy.log                  # Logs do sistema
```

---

## 🔍 Troubleshooting

### Problema: Docker daemon not running

```bash
# macOS/Windows: Abrir Docker Desktop
# Linux:
sudo systemctl start docker
```

### Problema: Porta 80/443 já em uso

```bash
# Verificar o que está usando a porta
sudo lsof -i :80
sudo lsof -i :443

# Parar serviço conflitante ou mudar porta do Traefik
# Editar: docker/traefik/docker-compose.yml
```

### Problema: Permissões negadas

```bash
# Adicionar usuário ao grupo docker
sudo usermod -aG docker $USER

# Fazer logout e login novamente
```

### Problema: Catálogo não baixa

```bash
# Atualizar manualmente
./hostfy catalog update

# Ou baixar diretamente
curl -fsSL https://github.com/eduardocarezia/hostfy-cli/raw/refs/heads/main/catalog/containers-catalog.json \
  -o catalog/containers-catalog.json
```

### Ver logs detalhados

```bash
# Habilitar debug
export HOSTFY_DEBUG=true
./hostfy <comando>

# Ver logs do sistema
tail -f logs/hostfy.log

# Ver logs de um container
./hostfy logs <container-name> --follow
```

---

## 🤝 Contribuindo

### Adicionar Container ao Catálogo

1. Fork do repositório
2. Editar `catalog/containers-catalog.json`
3. Adicionar nova entrada seguindo o schema
4. Testar instalação
5. Criar Pull Request

Exemplo de entrada no catálogo:

```json
{
  "id": "myapp",
  "name": "My Application",
  "slug": "myapp",
  "description": "Description here",
  "category": "category-name",
  "tags": ["tag1", "tag2"],
  "official": false,
  "maintainer": "Your Name",
  "image": {
    "repository": "username/myapp",
    "registry": "docker.io",
    "versions": [
      {
        "tag": "latest",
        "description": "Latest version",
        "recommended": true
      }
    ],
    "default_version": "latest"
  },
  "ports": [...],
  "volumes": [...],
  "environment": [...],
  "healthcheck": {...},
  "traefik": {...},
  "dependencies": []
}
```

---

## 📝 Licença

MIT License - Veja [LICENSE](LICENSE) para detalhes.

---

## 🔗 Links Úteis

- **Repositório:** https://github.com/eduardocarezia/hostfy-cli
- **Issues:** https://github.com/eduardocarezia/hostfy-cli/issues
- **Documentação Traefik:** https://doc.traefik.io/traefik/
- **Docker Docs:** https://docs.docker.com/

---

## ⭐ Star History

Se este projeto foi útil para você, considere dar uma ⭐!

```bash
# Compartilhar
git clone https://github.com/eduardocarezia/hostfy-cli.git
```

---

**Feito com ❤️ por Eduardo Carezia**
