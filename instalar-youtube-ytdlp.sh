#!/bin/bash
#
# Instalação Completa: YouTube via yt-dlp
# Instala yt-dlp, aplica patch, configura auto-update
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║    INSTALAÇÃO: YouTube Stream via yt-dlp                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Ir para diretório do projeto
cd /opt/stream-manager

echo -e "${YELLOW}[1/7] Atualizando repositório...${NC}"
git pull origin main 2>&1 | tail -3 || echo "Usando arquivos locais"
echo -e "${GREEN}✓ Repositório atualizado${NC}"

echo ""
echo -e "${YELLOW}[2/7] Instalando yt-dlp...${NC}"
chmod +x scripts/ytdlp-manager.sh
bash scripts/ytdlp-manager.sh install
echo -e "${GREEN}✓ yt-dlp instalado${NC}"

echo ""
echo -e "${YELLOW}[3/7] Ativando auto-update do yt-dlp...${NC}"
bash scripts/ytdlp-manager.sh auto-on
echo -e "${GREEN}✓ Auto-update ativado (atualização a cada 7 dias)${NC}"

echo ""
echo -e "${YELLOW}[4/7] Tornando scripts executáveis...${NC}"
chmod +x scripts/youtube-stream.sh
chmod +x scripts/ytdlp-manager.sh
chmod +x patch-youtube-ytdlp.py
echo -e "${GREEN}✓ Permissões configuradas${NC}"

echo ""
echo -e "${YELLOW}[5/7] Parando Stream Manager...${NC}"
systemctl stop stream-manager
sleep 2
echo -e "${GREEN}✓ Serviço parado${NC}"

echo ""
echo -e "${YELLOW}[6/7] Aplicando patch no código...${NC}"
python3 patch-youtube-ytdlp.py
echo -e "${GREEN}✓ Patch aplicado${NC}"

echo ""
echo -e "${YELLOW}[7/7] Reiniciando Stream Manager...${NC}"
systemctl start stream-manager
sleep 3

# Verificar status
if systemctl is-active --quiet stream-manager; then
    echo -e "${GREEN}✓ Stream Manager iniciado com sucesso${NC}"
    echo ""
    systemctl status stream-manager --no-pager | head -12
else
    echo -e "${RED}✗ Erro ao iniciar Stream Manager${NC}"
    echo "Logs:"
    journalctl -u stream-manager -n 20 --no-pager
    exit 1
fi

echo ""
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║            INSTALAÇÃO CONCLUÍDA COM SUCESSO!               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${BLUE}ℹ  INFORMAÇÕES:${NC}"
echo ""
bash scripts/ytdlp-manager.sh version

echo ""
echo -e "${BLUE}🎬 TESTAR YOUTUBE:${NC}"
echo ""
echo "1. Parar stream antigo:"
echo "   curl -X POST http://localhost:8080/api/streams/youtube_exemplo/stop"
echo ""
echo "2. Iniciar stream:"
echo "   curl -X POST http://localhost:8080/api/streams/youtube_exemplo/start"
echo ""
echo "3. Aguardar 10-15 segundos e verificar:"
echo "   ls -lh /var/www/hls/youtube_exemplo/"
echo ""
echo "4. Assistir:"
echo "   vlc http://186.233.119.88:8080/hls/youtube_exemplo/index.m3u8"
echo ""
echo -e "${BLUE}📝 LOGS:${NC}"
echo "   journalctl -u stream-manager -f"
echo "   tail -f /opt/stream-manager/logs/youtube-youtube_exemplo.log"
echo ""
echo -e "${BLUE}🔄 GERENCIAR yt-dlp:${NC}"
echo "   bash scripts/ytdlp-manager.sh version    # Ver versão"
echo "   bash scripts/ytdlp-manager.sh update     # Atualizar agora"
echo "   bash scripts/ytdlp-manager.sh auto-off   # Desativar auto-update"
echo ""
