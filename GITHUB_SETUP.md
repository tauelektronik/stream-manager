# Como subir para o GitHub

## 1. Criar repositório no GitHub

1. Acesse: https://github.com/new
2. Nome do repositório: `stream-manager`
3. Deixe público
4. NÃO inicialize com README
5. Clique em "Create repository"

## 2. Subir os arquivos (PowerShell/Terminal)

```powershell
cd "c:\Users\TAU\Documents\VS Code\str\stream-manager"

git init
git add .
git commit -m "Initial commit - Stream Manager v1.0"
git branch -M main
git remote add origin https://github.com/tautop/stream-manager.git
git push -u origin main
```

## 3. Instalar no servidor

Depois que estiver no GitHub, no servidor execute:

```bash
# Instalação com uma linha:
curl -sSL https://raw.githubusercontent.com/tautop/stream-manager/main/install.sh | sudo bash

# OU clone manual:
cd /opt
git clone https://github.com/tautop/stream-manager.git
cd stream-manager
sudo ./install.sh
```

## 4. Acessar

Após instalação:
- Interface Web: http://SEU_IP:8080
- HLS: http://SEU_IP:8080/hls/{stream}/index.m3u8
- RTMP: rtmp://SEU_IP:1935/live/{stream}
