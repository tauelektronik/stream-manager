#!/bin/bash
#
# Script de atualização rápida do Stream Manager
# Execute no servidor: curl -sSL https://raw.githubusercontent.com/tauelektronik/stream-manager/main/update-server.sh | sudo bash
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Atualizando Stream Manager...${NC}"

# Parar serviços
echo "[1/5] Parando serviços..."
systemctl stop stream-manager 2>/dev/null || true
pkill -f stream-manager.py 2>/dev/null || true

# Baixar arquivos atualizados
echo "[2/5] Baixando arquivos atualizados..."
cd /opt/stream-manager

# Fazer backup
cp scripts/stream-manager.py scripts/stream-manager.py.bak 2>/dev/null || true

# Baixar nova versão
curl -sSL https://raw.githubusercontent.com/tauelektronik/stream-manager/main/scripts/stream-manager.py -o scripts/stream-manager.py
curl -sSL https://raw.githubusercontent.com/tauelektronik/stream-manager/main/config/nginx-hls-only.conf -o config/nginx-hls-only.conf

# Atualizar nginx config
echo "[3/5] Atualizando configuração do Nginx..."
cp config/nginx-hls-only.conf /etc/nginx/nginx.conf

# Garantir diretórios
echo "[4/5] Verificando diretórios..."
mkdir -p /var/www/hls
chmod 755 /var/www/hls
chown -R www-data:www-data /var/www/hls

mkdir -p /opt/stream-manager/logs
chmod 755 /opt/stream-manager/logs

# Reiniciar serviços
echo "[5/5] Reiniciando serviços..."
systemctl restart nginx 2>/dev/null || nginx
systemctl start stream-manager 2>/dev/null || true

# Se stream-manager não funcionar via systemd, iniciar manualmente
if ! systemctl is-active --quiet stream-manager 2>/dev/null; then
    echo -e "${YELLOW}Iniciando stream-manager manualmente...${NC}"
    cd /opt/stream-manager
    source venv/bin/activate 2>/dev/null || true
    nohup python3 scripts/stream-manager.py > logs/stream-manager.log 2>&1 &
    sleep 2
fi

echo -e "${GREEN}Atualização concluída!${NC}"
echo ""
echo "Acesse: http://$(hostname -I | awk '{print $1}'):7070"
