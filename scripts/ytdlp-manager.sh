#!/bin/bash
#
# yt-dlp Manager - Gerenciador e auto-updater do yt-dlp
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

YTDLP_UPDATE_FILE="/opt/stream-manager/.ytdlp-last-update"
AUTO_UPDATE_ENABLED="/opt/stream-manager/.ytdlp-auto-update"

show_version() {
    echo -e "${BLUE}yt-dlp Version Manager${NC}"
    echo ""

    if command -v yt-dlp &> /dev/null; then
        current_version=$(yt-dlp --version)
        echo -e "Versão instalada: ${GREEN}${current_version}${NC}"

        # Verificar última atualização
        if [ -f "$YTDLP_UPDATE_FILE" ]; then
            last_update=$(cat "$YTDLP_UPDATE_FILE")
            echo "Última atualização: $last_update"

            # Calcular dias desde última atualização
            last_epoch=$(date -d "$last_update" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            days_ago=$(( (now_epoch - last_epoch) / 86400 ))

            if [ $days_ago -gt 7 ]; then
                echo -e "${YELLOW}⚠️  Atualização disponível (última há $days_ago dias)${NC}"
            else
                echo -e "${GREEN}✓ Atualizado recentemente (há $days_ago dias)${NC}"
            fi
        else
            echo -e "${YELLOW}Sem registro de atualização${NC}"
        fi

        # Status do auto-update
        if [ -f "$AUTO_UPDATE_ENABLED" ]; then
            echo -e "Auto-update: ${GREEN}ATIVADO${NC}"
        else
            echo -e "Auto-update: ${RED}DESATIVADO${NC}"
        fi
    else
        echo -e "${RED}yt-dlp NÃO INSTALADO${NC}"
    fi
}

install_ytdlp() {
    echo -e "${YELLOW}Instalando yt-dlp...${NC}"

    # Tentar via pip primeiro
    if command -v pip3 &> /dev/null; then
        pip3 install yt-dlp
    elif command -v pip &> /dev/null; then
        pip install yt-dlp
    else
        # Fallback: instalação direta
        echo "pip não encontrado, instalando via curl..."
        sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
        sudo chmod a+rx /usr/local/bin/yt-dlp
    fi

    if command -v yt-dlp &> /dev/null; then
        echo -e "${GREEN}✓ yt-dlp instalado com sucesso${NC}"
        date "+%Y-%m-%d %H:%M:%S" > "$YTDLP_UPDATE_FILE"
        show_version
    else
        echo -e "${RED}✗ Falha na instalação${NC}"
        exit 1
    fi
}

update_ytdlp() {
    echo -e "${YELLOW}Atualizando yt-dlp...${NC}"

    if ! command -v yt-dlp &> /dev/null; then
        echo -e "${RED}yt-dlp não está instalado${NC}"
        echo "Execute: $0 install"
        exit 1
    fi

    # Versão atual
    old_version=$(yt-dlp --version)
    echo "Versão atual: $old_version"

    # Atualizar
    if command -v pip3 &> /dev/null; then
        pip3 install --upgrade yt-dlp
    elif command -v pip &> /dev/null; then
        pip install --upgrade yt-dlp
    else
        # Via download direto
        sudo yt-dlp -U || sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
    fi

    # Nova versão
    new_version=$(yt-dlp --version)

    if [ "$old_version" != "$new_version" ]; then
        echo -e "${GREEN}✓ Atualizado: $old_version → $new_version${NC}"
        date "+%Y-%m-%d %H:%M:%S" > "$YTDLP_UPDATE_FILE"
    else
        echo -e "${BLUE}ℹ Já está na versão mais recente${NC}"
    fi
}

enable_auto_update() {
    touch "$AUTO_UPDATE_ENABLED"
    echo -e "${GREEN}✓ Auto-update ATIVADO${NC}"
    echo ""
    echo "yt-dlp será atualizado automaticamente a cada 7 dias"
    echo "quando um stream do YouTube for iniciado."
}

disable_auto_update() {
    rm -f "$AUTO_UPDATE_ENABLED"
    echo -e "${YELLOW}Auto-update DESATIVADO${NC}"
}

check_and_auto_update() {
    # Verificar se auto-update está ativado
    if [ ! -f "$AUTO_UPDATE_ENABLED" ]; then
        return 0
    fi

    # Verificar última atualização
    if [ -f "$YTDLP_UPDATE_FILE" ]; then
        last_update_epoch=$(date -d "$(cat $YTDLP_UPDATE_FILE)" +%s 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        days_since=$(( (now_epoch - last_update_epoch) / 86400 ))

        if [ $days_since -ge 7 ]; then
            echo "[$(date)] Auto-update: Atualizando yt-dlp (última atualização há $days_since dias)"
            update_ytdlp
        fi
    else
        # Primeira execução
        update_ytdlp
    fi
}

show_help() {
    echo "yt-dlp Manager - Gerenciador do yt-dlp"
    echo ""
    echo "Uso: $0 <comando>"
    echo ""
    echo "Comandos:"
    echo "  version         Mostra versão e status"
    echo "  install         Instala yt-dlp"
    echo "  update          Atualiza yt-dlp para versão mais recente"
    echo "  auto-on         Ativa atualização automática (a cada 7 dias)"
    echo "  auto-off        Desativa atualização automática"
    echo "  check           Verifica e atualiza se necessário (usado internamente)"
    echo "  help            Mostra esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  $0 install          # Instalar yt-dlp"
    echo "  $0 update           # Atualizar agora"
    echo "  $0 auto-on          # Ativar auto-update"
    echo ""
}

# Comando principal
case "${1:-help}" in
    version|v)
        show_version
        ;;
    install|i)
        install_ytdlp
        ;;
    update|u)
        update_ytdlp
        ;;
    auto-on|enable)
        enable_auto_update
        ;;
    auto-off|disable)
        disable_auto_update
        ;;
    check)
        check_and_auto_update
        ;;
    help|h|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Comando desconhecido: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
