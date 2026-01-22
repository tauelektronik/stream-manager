#!/bin/bash
#
# Stream Manager - Script de Instalação
# Para Ubuntu/Debian
#

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Diretório de instalação
INSTALL_DIR="/opt/stream-manager"
NGINX_RTMP_VERSION="1.2.2"

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           STREAM MANAGER - INSTALAÇÃO                      ║"
echo "║     Sistema de Captura e Streaming de Navegadores          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Este script deve ser executado como root (sudo)${NC}"
    exit 1
fi

# Detectar distribuição
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
else
    echo -e "${RED}Não foi possível detectar a distribuição Linux${NC}"
    exit 1
fi

echo -e "${GREEN}Distribuição detectada: $DISTRO $VERSION${NC}"

# Função para instalar dependências
install_dependencies() {
    echo -e "\n${YELLOW}[1/7] Instalando dependências do sistema...${NC}"

    apt-get update
    apt-get install -y \
        build-essential \
        libpcre3 \
        libpcre3-dev \
        libssl-dev \
        zlib1g-dev \
        git \
        wget \
        curl \
        unzip \
        xvfb \
        x11vnc \
        pulseaudio \
        ffmpeg \
        chromium-browser \
        python3 \
        python3-pip \
        python3-venv \
        libnss3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxrandr2 \
        libgbm1 \
        libasound2 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libgtk-3-0

    echo -e "${GREEN}✓ Dependências instaladas${NC}"
}

# Função para compilar e instalar Nginx com módulo RTMP
install_nginx_rtmp() {
    echo -e "\n${YELLOW}[2/7] Instalando Nginx com módulo RTMP...${NC}"

    # Verificar se já existe
    if nginx -v 2>&1 | grep -q "rtmp"; then
        echo -e "${GREEN}✓ Nginx RTMP já está instalado${NC}"
        return
    fi

    # Parar nginx existente se houver
    systemctl stop nginx 2>/dev/null || true

    cd /tmp

    # Baixar nginx
    NGINX_VERSION="1.24.0"
    wget -q http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
    tar -xzf nginx-${NGINX_VERSION}.tar.gz

    # Baixar módulo RTMP
    git clone https://github.com/arut/nginx-rtmp-module.git

    # Compilar
    cd nginx-${NGINX_VERSION}
    ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib64/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_stub_status_module \
        --add-module=../nginx-rtmp-module

    make -j$(nproc)
    make install

    # Criar diretórios necessários
    mkdir -p /var/log/nginx
    mkdir -p /etc/nginx/conf.d

    # Criar serviço systemd para nginx
    cat > /etc/systemd/system/nginx.service << 'EOF'
[Unit]
Description=Nginx HTTP and RTMP Server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # Limpar
    cd /
    rm -rf /tmp/nginx-${NGINX_VERSION}*
    rm -rf /tmp/nginx-rtmp-module

    systemctl daemon-reload
    systemctl enable nginx

    echo -e "${GREEN}✓ Nginx RTMP instalado${NC}"
}

# Função para criar estrutura de diretórios
create_directories() {
    echo -e "\n${YELLOW}[3/7] Criando estrutura de diretórios...${NC}"

    mkdir -p $INSTALL_DIR/{config,scripts,profiles,logs,hls,web/css,web/js}
    mkdir -p /var/www/hls

    # Permissões
    chown -R www-data:www-data /var/www/hls
    chmod -R 755 $INSTALL_DIR

    echo -e "${GREEN}✓ Diretórios criados${NC}"
}

# Função para copiar arquivos
copy_files() {
    echo -e "\n${YELLOW}[4/7] Copiando arquivos do projeto...${NC}"

    # Detectar diretório do script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Copiar arquivos Python e scripts
    cp -f "$SCRIPT_DIR/scripts/stream-manager.py" "$INSTALL_DIR/scripts/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/scripts/browser-launcher.sh" "$INSTALL_DIR/scripts/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/requirements.txt" "$INSTALL_DIR/" 2>/dev/null || true

    # Copiar configurações
    cp -f "$SCRIPT_DIR/config/streams.json" "$INSTALL_DIR/config/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/config/nginx-rtmp.conf" "/etc/nginx/nginx.conf" 2>/dev/null || true

    # Copiar web
    cp -rf "$SCRIPT_DIR/web/"* "$INSTALL_DIR/web/" 2>/dev/null || true

    # Tornar scripts executáveis
    chmod +x $INSTALL_DIR/scripts/*.sh 2>/dev/null || true
    chmod +x $INSTALL_DIR/scripts/*.py 2>/dev/null || true

    echo -e "${GREEN}✓ Arquivos copiados${NC}"
}

# Função para configurar ambiente Python
setup_python() {
    echo -e "\n${YELLOW}[5/7] Configurando ambiente Python...${NC}"

    cd $INSTALL_DIR

    # Criar ambiente virtual
    python3 -m venv venv

    # Ativar e instalar dependências
    source venv/bin/activate
    pip install --upgrade pip
    pip install flask flask-socketio flask-cors eventlet psutil

    echo -e "${GREEN}✓ Ambiente Python configurado${NC}"
}

# Função para configurar serviço systemd
setup_systemd() {
    echo -e "\n${YELLOW}[6/7] Configurando serviço systemd...${NC}"

    cat > /etc/systemd/system/stream-manager.service << EOF
[Unit]
Description=Stream Manager - Browser Streaming Service
After=network.target nginx.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/scripts/stream-manager.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable stream-manager

    echo -e "${GREEN}✓ Serviço systemd configurado${NC}"
}

# Função para configurar firewall
setup_firewall() {
    echo -e "\n${YELLOW}[7/7] Configurando firewall...${NC}"

    if command -v ufw &> /dev/null; then
        ufw allow 8080/tcp comment 'Stream Manager Web'
        ufw allow 1935/tcp comment 'RTMP Streaming'
        echo -e "${GREEN}✓ Regras UFW adicionadas${NC}"
    else
        echo -e "${YELLOW}UFW não encontrado, configure o firewall manualmente${NC}"
        echo "  - Porta 8080/tcp: Interface Web e HLS"
        echo "  - Porta 1935/tcp: RTMP"
    fi
}

# Função para exibir informações finais
show_info() {
    # Obter IP
    SERVER_IP=$(hostname -I | awk '{print $1}')

    echo -e "\n${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              INSTALAÇÃO CONCLUÍDA!                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${BLUE}Diretório de instalação:${NC} $INSTALL_DIR"
    echo ""
    echo -e "${BLUE}Comandos úteis:${NC}"
    echo "  sudo systemctl start stream-manager   # Iniciar serviço"
    echo "  sudo systemctl stop stream-manager    # Parar serviço"
    echo "  sudo systemctl status stream-manager  # Ver status"
    echo "  sudo systemctl restart nginx          # Reiniciar Nginx"
    echo ""
    echo -e "${BLUE}Acessos:${NC}"
    echo "  Interface Web: http://$SERVER_IP:8080"
    echo "  HLS Streams:   http://$SERVER_IP:8080/hls/{nome}/index.m3u8"
    echo "  RTMP Streams:  rtmp://$SERVER_IP:1935/live/{nome}"
    echo ""
    echo -e "${YELLOW}Próximos passos:${NC}"
    echo "  1. Inicie o serviço: sudo systemctl start stream-manager"
    echo "  2. Acesse a interface web"
    echo "  3. Adicione seus streams"
    echo "  4. Configure os logins nos perfis do navegador"
    echo ""
    echo -e "${GREEN}Para iniciar agora, execute:${NC}"
    echo "  sudo systemctl start nginx && sudo systemctl start stream-manager"
}

# Função para iniciar serviços
start_services() {
    echo -e "\n${YELLOW}Iniciando serviços...${NC}"

    systemctl start nginx
    systemctl start stream-manager

    sleep 2

    if systemctl is-active --quiet nginx && systemctl is-active --quiet stream-manager; then
        echo -e "${GREEN}✓ Serviços iniciados com sucesso!${NC}"
    else
        echo -e "${RED}Erro ao iniciar serviços. Verifique os logs.${NC}"
    fi
}

# Executar instalação
main() {
    install_dependencies
    install_nginx_rtmp
    create_directories
    copy_files
    setup_python
    setup_systemd
    setup_firewall
    start_services
    show_info
}

# Executar
main "$@"
