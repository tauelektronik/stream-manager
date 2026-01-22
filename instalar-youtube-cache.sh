#!/bin/bash
#
# Instalação da Solução de Captura de Cache para YouTube
# Executa no servidor
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     INSTALAÇÃO: YouTube Cache Capture                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}[1/6] Instalando dependências Python...${NC}"
pip3 install watchdog python-magic python-magic-bin 2>&1 | grep -i 'success\|installed' || true
echo -e "${GREEN}✓ Dependências instaladas${NC}"

echo ""
echo -e "${YELLOW}[2/6] Parando Stream Manager...${NC}"
systemctl stop stream-manager
echo -e "${GREEN}✓ Serviço parado${NC}"

echo ""
echo -e "${YELLOW}[3/6] Copiando scripts...${NC}"
# Scripts já devem estar no repositório
cd /opt/stream-manager
git pull origin main 2>&1 | tail -3 || echo "Git pull falhou, usando arquivos locais"

chmod +x scripts/cache-capture.sh scripts/cache-capture.py
echo -e "${GREEN}✓ Scripts copiados${NC}"

echo ""
echo -e "${YELLOW}[4/6] Aplicando patch no stream-manager.py...${NC}"
python3 patch-youtube-cache.py
echo -e "${GREEN}✓ Patch aplicado${NC}"

echo ""
echo -e "${YELLOW}[5/6] Reiniciando Stream Manager...${NC}"
systemctl start stream-manager
sleep 3
systemctl status stream-manager --no-pager | head -10
echo -e "${GREEN}✓ Serviço reiniciado${NC}"

echo ""
echo -e "${YELLOW}[6/6] Testando YouTube...${NC}"
sleep 2

# Parar streams antigos
curl -s -X POST http://localhost:8080/api/streams/youtube_exemplo/stop 2>/dev/null || true
sleep 1

# Iniciar
echo "Iniciando stream YouTube..."
response=$(curl -s -X POST http://localhost:8080/api/streams/youtube_exemplo/start)
echo "$response" | python3 -m json.tool || echo "$response"

echo ""
echo "Aguardando 20 segundos para cache começar a capturar..."
sleep 20

echo ""
echo -e "${BLUE}[STATUS]${NC}"
curl -s http://localhost:8080/api/streams/youtube_exemplo | python3 -c "
import sys, json
try:
    s = json.load(sys.stdin)
    print(f\"Estado: {s.get('state', 'unknown')}\")
    print(f\"Método: {s.get('method', 'N/A')}\")
    print(f\"Link HLS: {s.get('hls_url', 'N/A')}\")
except:
    print('Erro ao parsear JSON')
"

echo ""
echo -e "${BLUE}[ARQUIVOS HLS]${NC}"
ls -lh /var/www/hls/youtube_exemplo/ 2>/dev/null | tail -10 || echo "Ainda gerando..."

echo ""
echo -e "${BLUE}[LOGS CACHE CAPTURE]${NC}"
tail -20 /opt/stream-manager/logs/cache-youtube_exemplo.log 2>/dev/null || echo "Log não disponível ainda"

echo ""
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              INSTALAÇÃO CONCLUÍDA!                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo "Link HLS: http://186.233.119.88:8080/hls/youtube_exemplo/index.m3u8"
echo ""
echo "Monitorar logs:"
echo "  sudo journalctl -u stream-manager -f"
echo "  tail -f /opt/stream-manager/logs/cache-youtube_exemplo.log"
echo ""
