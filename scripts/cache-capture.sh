#!/bin/bash
#
# Cache Capture - Captura fragmentos de vídeo do cache do Chrome
# Uso: ./cache-capture.sh <profile_dir> <stream_id>
#

set -e

PROFILE_DIR="${1}"
STREAM_ID="${2}"
HLS_DIR="/var/www/hls/${STREAM_ID}"
CACHE_DIR="${PROFILE_DIR}/Default/Cache/Cache_Data"
TEMP_DIR="/tmp/stream-cache-${STREAM_ID}"

echo "[$(date)] Cache Capture iniciado"
echo "[$(date)] Profile: ${PROFILE_DIR}"
echo "[$(date)] Stream: ${STREAM_ID}"
echo "[$(date)] Cache: ${CACHE_DIR}"

# Criar diretórios
mkdir -p "$HLS_DIR"
mkdir -p "$TEMP_DIR"

# Arquivo de lista para FFmpeg
CONCAT_FILE="$TEMP_DIR/concat.txt"
> "$CONCAT_FILE"

# Contador de segmentos
segment_num=0

# Função para processar fragmentos
process_fragments() {
    # Procurar fragmentos de vídeo no cache
    # Chrome armazena como f_XXXXXX (sem extensão)
    find "$CACHE_DIR" -type f -size +100k -newer "$TEMP_DIR/last_check" 2>/dev/null | while read -r file; do
        # Verificar se é vídeo (magic bytes)
        file_type=$(file -b "$file" | head -c 20)

        if [[ "$file_type" =~ "ISO Media" ]] || [[ "$file_type" =~ "MPEG" ]] || [[ "$file_type" =~ "data" ]]; then
            # Copiar para temp
            fragment_file="$TEMP_DIR/fragment_$(date +%s%N).ts"
            cp "$file" "$fragment_file"

            # Adicionar à lista de concatenação
            echo "file '$fragment_file'" >> "$CONCAT_FILE"

            echo "[$(date)] Fragmento capturado: $(basename $file) -> $(basename $fragment_file)"
        fi
    done
}

# Criar arquivo de timestamp
touch "$TEMP_DIR/last_check"

# Loop principal
echo "[$(date)] Monitorando cache..."
while true; do
    # Processar novos fragmentos
    process_fragments

    # Se temos fragmentos suficientes, gerar HLS
    num_fragments=$(wc -l < "$CONCAT_FILE")
    if [ "$num_fragments" -ge 5 ]; then
        echo "[$(date)] Gerando HLS com $num_fragments fragmentos..."

        # Concatenar e gerar HLS
        ffmpeg -f concat -safe 0 -i "$CONCAT_FILE" \
            -c copy \
            -f hls \
            -hls_time 2 \
            -hls_list_size 10 \
            -hls_flags delete_segments+append_list \
            -hls_segment_filename "$HLS_DIR/segment_%03d.ts" \
            "$HLS_DIR/index.m3u8" \
            -y -loglevel warning 2>&1 | head -5

        # Limpar lista (manter últimos 2 fragmentos para continuidade)
        tail -2 "$CONCAT_FILE" > "$CONCAT_FILE.tmp"
        mv "$CONCAT_FILE.tmp" "$CONCAT_FILE"

        # Limpar fragmentos antigos
        find "$TEMP_DIR" -name "fragment_*.ts" -mmin +2 -delete
    fi

    # Atualizar timestamp
    touch "$TEMP_DIR/last_check"

    # Aguardar antes do próximo check
    sleep 2
done
