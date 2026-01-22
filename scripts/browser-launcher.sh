#!/bin/bash
#
# Browser Launcher - Inicia navegador em display virtual
# Uso: ./browser-launcher.sh <display> <url> <profile> <resolution>
#

set -e

DISPLAY_NUM="${1:-99}"
URL="${2:-https://www.google.com}"
PROFILE="${3:-default}"
RESOLUTION="${4:-1280x720}"

PROFILE_DIR="/opt/stream-manager/profiles/${PROFILE}"
LOG_DIR="/opt/stream-manager/logs"

# Criar diretórios se não existirem
mkdir -p "$PROFILE_DIR"
mkdir -p "$LOG_DIR"

# Extrair largura e altura
WIDTH=$(echo $RESOLUTION | cut -d'x' -f1)
HEIGHT=$(echo $RESOLUTION | cut -d'x' -f2)

# Configurar display
export DISPLAY=:${DISPLAY_NUM}

echo "[$(date)] Iniciando browser no display :${DISPLAY_NUM}"
echo "[$(date)] URL: ${URL}"
echo "[$(date)] Perfil: ${PROFILE_DIR}"
echo "[$(date)] Resolução: ${RESOLUTION}"

# Verificar se Xvfb está rodando
if ! xdpyinfo -display :${DISPLAY_NUM} >/dev/null 2>&1; then
    echo "[$(date)] Iniciando Xvfb..."
    Xvfb :${DISPLAY_NUM} -screen 0 ${WIDTH}x${HEIGHT}x24 -ac &
    sleep 2
fi

# Iniciar Chromium
echo "[$(date)] Iniciando Chromium..."
chromium-browser \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-software-rasterizer \
    --window-size=${WIDTH},${HEIGHT} \
    --start-maximized \
    --autoplay-policy=no-user-gesture-required \
    --disable-features=PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies \
    --user-data-dir="${PROFILE_DIR}" \
    --disable-translate \
    --disable-extensions \
    --disable-background-networking \
    --disable-sync \
    --disable-default-apps \
    --mute-audio=false \
    --no-first-run \
    --no-default-browser-check \
    "${URL}" \
    2>&1 | tee -a "${LOG_DIR}/browser-${PROFILE}.log"
