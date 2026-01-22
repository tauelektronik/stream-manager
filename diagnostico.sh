#!/bin/bash
#
# Script de Diagnóstico - Stream Manager
#

echo "======================================"
echo "  Stream Manager - Diagnóstico"
echo "======================================"
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[1] Informações do Sistema${NC}"
echo "-----------------------------------"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo ""

echo -e "${BLUE}[2] Status dos Serviços${NC}"
echo "-----------------------------------"
echo -e "${YELLOW}Stream Manager:${NC}"
systemctl status stream-manager --no-pager || echo -e "${RED}Serviço não encontrado${NC}"
echo ""

echo -e "${YELLOW}Nginx:${NC}"
systemctl status nginx --no-pager || echo -e "${RED}Serviço não encontrado${NC}"
echo ""

echo -e "${BLUE}[3] Portas em Uso${NC}"
echo "-----------------------------------"
netstat -tulpn | grep -E ':(8080|1935|5900)' || echo "Nenhuma porta ativa"
echo ""

echo -e "${BLUE}[4] Processos Ativos${NC}"
echo "-----------------------------------"
echo -e "${YELLOW}Python (Stream Manager):${NC}"
ps aux | grep stream-manager.py | grep -v grep || echo "Não encontrado"
echo ""

echo -e "${YELLOW}Nginx:${NC}"
ps aux | grep nginx | grep -v grep || echo "Não encontrado"
echo ""

echo -e "${YELLOW}Chromium/Chrome:${NC}"
ps aux | grep chromium | grep -v grep || echo "Não encontrado"
echo ""

echo -e "${YELLOW}Xvfb (Display Virtual):${NC}"
ps aux | grep Xvfb | grep -v grep || echo "Não encontrado"
echo ""

echo -e "${YELLOW}FFmpeg:${NC}"
ps aux | grep ffmpeg | grep -v grep || echo "Não encontrado"
echo ""

echo -e "${BLUE}[5] Verificar Diretórios${NC}"
echo "-----------------------------------"
if [ -d "/opt/stream-manager" ]; then
    echo -e "${GREEN}✓ /opt/stream-manager existe${NC}"
    ls -la /opt/stream-manager/
else
    echo -e "${RED}✗ /opt/stream-manager NÃO EXISTE${NC}"
fi
echo ""

echo -e "${BLUE}[6] Logs Recentes - Stream Manager${NC}"
echo "-----------------------------------"
if [ -f "/opt/stream-manager/logs/stream-manager.log" ]; then
    tail -30 /opt/stream-manager/logs/stream-manager.log
else
    echo "Verificando journalctl..."
    journalctl -u stream-manager -n 30 --no-pager 2>/dev/null || echo -e "${RED}Sem logs disponíveis${NC}"
fi
echo ""

echo -e "${BLUE}[7] Logs Recentes - Nginx${NC}"
echo "-----------------------------------"
if [ -f "/var/log/nginx/error.log" ]; then
    tail -20 /var/log/nginx/error.log
else
    echo -e "${YELLOW}Sem logs de erro do Nginx${NC}"
fi
echo ""

echo -e "${BLUE}[8] Logs FFmpeg (se houver)${NC}"
echo "-----------------------------------"
if [ -d "/opt/stream-manager/logs" ]; then
    ls -la /opt/stream-manager/logs/ffmpeg*.log 2>/dev/null || echo "Nenhum log FFmpeg"
    for logfile in /opt/stream-manager/logs/ffmpeg*.log; do
        if [ -f "$logfile" ]; then
            echo -e "\n${YELLOW}=== $logfile ===${NC}"
            tail -20 "$logfile"
        fi
    done
else
    echo "Diretório de logs não existe"
fi
echo ""

echo -e "${BLUE}[9] Configuração - streams.json${NC}"
echo "-----------------------------------"
if [ -f "/opt/stream-manager/config/streams.json" ]; then
    cat /opt/stream-manager/config/streams.json
else
    echo -e "${RED}Arquivo streams.json NÃO EXISTE${NC}"
fi
echo ""

echo -e "${BLUE}[10] Versões Instaladas${NC}"
echo "-----------------------------------"
echo "Python: $(python3 --version 2>&1 || echo 'Não instalado')"
echo "FFmpeg: $(ffmpeg -version 2>&1 | head -1 || echo 'Não instalado')"
echo "Chromium: $(chromium-browser --version 2>&1 || chromium --version 2>&1 || echo 'Não instalado')"
echo "Nginx: $(nginx -v 2>&1 || echo 'Não instalado')"
echo ""

echo -e "${BLUE}[11] Espaço em Disco${NC}"
echo "-----------------------------------"
df -h | grep -E '(Filesystem|/$|/opt)'
echo ""

echo -e "${BLUE}[12] Uso de Memória${NC}"
echo "-----------------------------------"
free -h
echo ""

echo -e "${BLUE}[13] Firewall (UFW)${NC}"
echo "-----------------------------------"
if command -v ufw &> /dev/null; then
    ufw status
else
    echo "UFW não instalado"
fi
echo ""

echo -e "${GREEN}======================================"
echo "  Diagnóstico Concluído!"
echo "======================================${NC}"
echo ""
echo "Copie TODA a saída acima e envie para análise."
echo ""
