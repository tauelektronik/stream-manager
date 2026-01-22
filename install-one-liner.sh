#!/bin/bash
# Stream Manager - Instalação com uma linha
# Execute: curl -sSL https://raw.githubusercontent.com/tautop/stream-manager/main/install.sh | sudo bash

set -e

echo "=========================================="
echo "  STREAM MANAGER - INSTALAÇÃO"
echo "=========================================="

cd /opt
rm -rf stream-manager 2>/dev/null || true

echo "[1/3] Baixando do GitHub..."
git clone https://github.com/tautop/stream-manager.git
cd stream-manager

echo "[2/3] Executando instalação..."
chmod +x install.sh
./install.sh

echo "[3/3] Concluído!"
