#!/bin/bash
#
# Script de Deploy Automatizado para Servidor
# IP: 186.233.119.88
#

set -e

echo "======================================"
echo "Stream Manager - Deploy Automatizado"
echo "======================================"
echo ""

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configurações
GITHUB_REPO="https://github.com/tauelektronik/stream-manager.git"
INSTALL_DIR="/opt/stream-manager"

echo -e "${YELLOW}[1/4] Atualizando sistema...${NC}"
apt-get update -qq

echo -e "${YELLOW}[2/4] Instalando Git...${NC}"
apt-get install -y git curl wget

echo -e "${YELLOW}[3/4] Clonando repositório do GitHub...${NC}"
# Remover diretório existente se houver
rm -rf $INSTALL_DIR
# Clonar repositório
git clone $GITHUB_REPO $INSTALL_DIR

echo -e "${YELLOW}[4/4] Executando instalação...${NC}"
cd $INSTALL_DIR
chmod +x install.sh
./install.sh

echo -e ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   DEPLOY CONCLUÍDO COM SUCESSO!        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "${YELLOW}Acesse a interface web em:${NC}"
echo -e "http://186.233.119.88:8080"
echo -e ""
echo -e "${RED}IMPORTANTE: Altere a senha do servidor root!${NC}"
echo -e "Execute: passwd"
echo -e ""
