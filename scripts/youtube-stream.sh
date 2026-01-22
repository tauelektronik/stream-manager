#!/bin/bash
#
# YouTube Stream via yt-dlp
# Extrai URL do stream e passa para FFmpeg gerar HLS
#

set -e

YOUTUBE_URL="${1}"
STREAM_ID="${2}"
HLS_DIR="/var/www/hls/${STREAM_ID}"
LOG_FILE="/opt/stream-manager/logs/youtube-${STREAM_ID}.log"

echo "[$(date)] YouTube Stream iniciado" >> "$LOG_FILE"
echo "[$(date)] URL: $YOUTUBE_URL" >> "$LOG_FILE"
echo "[$(date)] Stream ID: $STREAM_ID" >> "$LOG_FILE"

# Criar diretório HLS
mkdir -p "$HLS_DIR"
chmod 755 "$HLS_DIR"

# Auto-update do yt-dlp (se ativado)
YTDLP_MANAGER="/opt/stream-manager/scripts/ytdlp-manager.sh"
if [ -f "$YTDLP_MANAGER" ]; then
    bash "$YTDLP_MANAGER" check >> "$LOG_FILE" 2>&1
fi

# Obter URL direta do stream com yt-dlp
echo "[$(date)] Extraindo URL do stream..." >> "$LOG_FILE"

# Para lives e vídeos
STREAM_URL=$(yt-dlp -f "best[ext=mp4]/best" -g "$YOUTUBE_URL" 2>> "$LOG_FILE" | head -1)

if [ -z "$STREAM_URL" ]; then
    echo "[$(date)] ERRO: Não foi possível extrair URL" >> "$LOG_FILE"
    exit 1
fi

echo "[$(date)] URL extraída com sucesso" >> "$LOG_FILE"
echo "[$(date)] Iniciando FFmpeg..." >> "$LOG_FILE"

# Transmitir via FFmpeg
ffmpeg -hide_banner -loglevel error \
    -i "$STREAM_URL" \
    -c:v copy \
    -c:a aac -b:a 128k \
    -f hls \
    -hls_time 2 \
    -hls_list_size 10 \
    -hls_flags delete_segments+append_list \
    -hls_segment_filename "$HLS_DIR/segment_%03d.ts" \
    "$HLS_DIR/index.m3u8" \
    2>> "$LOG_FILE"

echo "[$(date)] Stream finalizado" >> "$LOG_FILE"
