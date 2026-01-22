# Stream Manager

Sistema para capturar streams de navegadores (YouTube, Globoplay, etc.) e redistribuir via HLS/RTMP.

## Requisitos

- Ubuntu 20.04+ ou Debian 11+
- 4+ cores CPU (8+ recomendado para 8+ streams)
- 16GB+ RAM
- Acesso root

## Instalação

### 1. Copiar arquivos para o servidor

```bash
# Via SCP
scp -r stream-manager/ root@seu-servidor:/opt/

# Ou via SFTP/FTP
```

### 2. Executar instalação

```bash
cd /opt/stream-manager
chmod +x install.sh
sudo ./install.sh
```

### 3. Iniciar serviços

```bash
sudo systemctl start nginx
sudo systemctl start stream-manager
```

## Uso

### Interface Web

Acesse: `http://SEU_IP:8080`

Na interface você pode:
- Adicionar novos streams
- Iniciar/parar streams
- Ver status em tempo real
- Copiar links HLS/RTMP
- Abrir VNC para configurar login
- Ver logs

### Configurar Login nos Serviços

1. Adicione um stream (ex: Globoplay)
2. Inicie o stream
3. Clique em "Abrir VNC"
4. Use um cliente VNC (TigerVNC, RealVNC) para conectar: `SEU_IP:5900`
5. Faça login no serviço pelo navegador virtual
6. Feche o VNC - o login ficará salvo no perfil

### Links dos Streams

**HLS (para VLC, navegadores):**
```
http://SEU_IP:8080/hls/NOME_DO_STREAM/index.m3u8
```

**RTMP (para OBS, FFmpeg):**
```
rtmp://SEU_IP:1935/live/NOME_DO_STREAM
```

**Abrir no VLC:**
```bash
vlc http://SEU_IP:8080/hls/NOME_DO_STREAM/index.m3u8
```

## Comandos Úteis

```bash
# Status dos serviços
sudo systemctl status stream-manager
sudo systemctl status nginx

# Logs
sudo journalctl -u stream-manager -f
tail -f /opt/stream-manager/logs/*.log

# Reiniciar
sudo systemctl restart stream-manager
sudo systemctl restart nginx

# Parar tudo
sudo systemctl stop stream-manager
sudo systemctl stop nginx
```

## Estrutura de Arquivos

```
/opt/stream-manager/
├── config/
│   ├── streams.json      # Configuração dos streams
│   └── nginx-rtmp.conf   # Config do Nginx
├── scripts/
│   ├── stream-manager.py # Backend principal
│   └── browser-launcher.sh
├── web/                  # Interface web
├── profiles/             # Perfis do Chrome (logins salvos)
├── logs/                 # Logs
├── hls/                  # Arquivos HLS temporários
└── venv/                 # Ambiente Python
```

## Portas

| Porta | Serviço |
|-------|---------|
| 8080  | Interface Web + HLS |
| 1935  | RTMP |
| 5900+ | VNC (quando ativo) |

## Firewall

```bash
sudo ufw allow 8080/tcp
sudo ufw allow 1935/tcp
```

## Problemas Comuns

### Stream não inicia
- Verifique os logs: `tail -f /opt/stream-manager/logs/ffmpeg-*.log`
- Verifique se Xvfb está rodando: `ps aux | grep Xvfb`

### VNC não conecta
- Certifique-se de que o stream está rodando
- Verifique se a porta está liberada no firewall

### Áudio não funciona
- Verifique se PulseAudio está rodando
- O stream precisa ter `audio: true` na configuração

## Limitações

- **Netflix/Amazon Prime**: DRM Widevine impede captura
- **YouTube/Globoplay**: Funcionam normalmente
- Cada stream consome ~1-2 cores de CPU para encoding

## Licença

Uso pessoal apenas. Não redistribua conteúdo protegido.
