# Guia de Instalação no Servidor
## IP: 186.233.119.88

---

## ⚠️ SEGURANÇA IMPORTANTE
**PRIMEIRA COISA A FAZER:** Altere a senha do servidor após a instalação!
```bash
passwd
```

---

## Método 1: Instalação com um único comando (RECOMENDADO)

### Passo 1: Conecte ao servidor via SSH

Abra o **PowerShell** ou **Terminal** e execute:

```bash
ssh root@186.233.119.88
```

Quando pedir a senha, digite: `Conect89123@`

### Passo 2: Execute o comando de instalação

Copie e cole este comando (instala tudo automaticamente):

```bash
curl -sSL https://raw.githubusercontent.com/tauelektronik/stream-manager/main/deploy-servidor.sh | sudo bash
```

**Pronto!** O script vai:
- Atualizar o sistema
- Instalar Git
- Baixar o projeto do GitHub
- Executar a instalação completa (Nginx RTMP + Python + Dependências)
- Iniciar os serviços

### Passo 3: Acesse a interface web

Após a instalação, abra no navegador:

```
http://186.233.119.88:8080
```

---

## Método 2: Instalação Manual (se preferir ver cada passo)

### 1. Conecte ao servidor
```bash
ssh root@186.233.119.88
# Senha: Conect89123@
```

### 2. Instale Git
```bash
apt-get update
apt-get install -y git
```

### 3. Baixe o projeto
```bash
cd /opt
git clone https://github.com/tauelektronik/stream-manager.git
cd stream-manager
```

### 4. Execute a instalação
```bash
chmod +x install.sh
./install.sh
```

### 5. Aguarde a instalação (5-15 minutos)

O script vai instalar:
- Nginx com módulo RTMP
- Python 3 e dependências
- FFmpeg, Xvfb, x11vnc
- Chromium browser
- PulseAudio

### 6. Acesse a interface
```
http://186.233.119.88:8080
```

---

## Comandos Úteis Após Instalação

### Ver status dos serviços
```bash
sudo systemctl status stream-manager
sudo systemctl status nginx
```

### Ver logs em tempo real
```bash
# Logs do Stream Manager
sudo journalctl -u stream-manager -f

# Logs do FFmpeg
tail -f /opt/stream-manager/logs/ffmpeg-*.log
```

### Reiniciar serviços
```bash
sudo systemctl restart stream-manager
sudo systemctl restart nginx
```

### Parar serviços
```bash
sudo systemctl stop stream-manager
sudo systemctl stop nginx
```

---

## Como Usar o Sistema

### 1. Adicionar um Stream

Na interface web, clique em **"Adicionar Stream"** e preencha:
- **Nome**: globoplay (ou qualquer nome sem espaços)
- **URL**: https://globoplay.globo.com
- **Resolução**: 1920x1080
- **FPS**: 30
- **Bitrate**: 4000k

### 2. Iniciar o Stream

Clique em **"Start"** no stream criado.

### 3. Configurar Login (se necessário)

Se o site exigir login (Globoplay, YouTube, etc.):

1. Clique em **"Abrir VNC"**
2. Use um cliente VNC para conectar:
   - **Host**: `186.233.119.88:5900`
   - **Senha**: (será exibida na interface)
3. No navegador virtual, faça login no site
4. Feche o VNC - o login ficará salvo

### 4. Acessar o Stream

Após iniciar, você terá:

**HLS (para VLC, navegadores):**
```
http://186.233.119.88:8080/hls/globoplay/index.m3u8
```

**RTMP (para OBS, FFmpeg):**
```
rtmp://186.233.119.88:1935/live/globoplay
```

**Testar no VLC:**
```bash
vlc http://186.233.119.88:8080/hls/globoplay/index.m3u8
```

---

## Portas Utilizadas

| Porta | Serviço | Descrição |
|-------|---------|-----------|
| 8080  | HTTP | Interface Web + HLS Streams |
| 1935  | RTMP | RTMP Streaming |
| 5900+ | VNC | Acesso ao navegador virtual |

---

## Firewall

Se o firewall estiver ativo, as portas já foram liberadas automaticamente:
```bash
sudo ufw status
```

Se precisar liberar manualmente:
```bash
sudo ufw allow 8080/tcp
sudo ufw allow 1935/tcp
```

---

## Solução de Problemas

### Stream não inicia
```bash
# Ver logs do FFmpeg
tail -f /opt/stream-manager/logs/ffmpeg-*.log

# Verificar se Xvfb está rodando
ps aux | grep Xvfb
```

### Interface web não abre
```bash
# Verificar status
sudo systemctl status stream-manager
sudo systemctl status nginx

# Reiniciar
sudo systemctl restart stream-manager
sudo systemctl restart nginx
```

### VNC não conecta
```bash
# Verificar se x11vnc está rodando
ps aux | grep x11vnc

# Verificar firewall
sudo ufw status
```

### Servidor ficou lento
```bash
# Ver uso de CPU/RAM
htop

# Ver quantos streams estão rodando
ps aux | grep chromium

# Para streams específicos via interface web
```

---

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
├── logs/                 # Logs do sistema
├── hls/                  # Arquivos HLS temporários
└── venv/                 # Ambiente Python
```

---

## ⚠️ LEMBRE-SE: ALTERAR A SENHA DO ROOT!

Após tudo instalado e funcionando:

```bash
passwd
```

Digite uma senha forte e guarde em local seguro.

---

## Suporte

Se tiver problemas:
1. Verifique os logs: `sudo journalctl -u stream-manager -f`
2. Reinicie os serviços
3. Verifique o firewall e as portas
4. Consulte a documentação no GitHub

---

**Instalação criada em:** 2026-01-22
**Repositório:** https://github.com/tauelektronik/stream-manager
