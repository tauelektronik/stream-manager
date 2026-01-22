#!/usr/bin/env python3
"""
Patch para adicionar suporte ao yt-dlp para YouTube
Substitui screen capture por extração direta de stream
"""

import sys
from pathlib import Path

print("Aplicando patch yt-dlp para YouTube...")

# Ler arquivo original
with open('/opt/stream-manager/scripts/stream-manager.py', 'r') as f:
    content = f.read()

# Criar backup
backup_file = '/opt/stream-manager/scripts/stream-manager.py.before-ytdlp'
with open(backup_file, 'w') as f:
    f.write(content)
print(f"✓ Backup criado: {backup_file}")

# Adicionar método para YouTube com yt-dlp
ytdlp_method = '''
    def start_youtube_stream(self, stream_id):
        """Inicia stream do YouTube usando yt-dlp"""
        if stream_id not in self.streams:
            return False, "Stream não encontrado"

        if stream_id in self.processes:
            return False, "Stream já está rodando"

        stream = self.streams[stream_id]

        try:
            self.processes[stream_id] = {}
            self.status[stream_id] = {
                'state': 'starting',
                'started_at': datetime.now().isoformat(),
                'method': 'ytdlp'
            }
            self.emit_status_update()

            # Criar diretório HLS
            hls_stream_dir = HLS_DIR / stream_id
            hls_stream_dir.mkdir(parents=True, exist_ok=True)
            os.chmod(hls_stream_dir, 0o755)
            logger.info(f"[{stream_id}] Diretório HLS criado: {hls_stream_dir}")

            # Usar script youtube-stream.sh
            youtube_script = BASE_DIR / 'scripts' / 'youtube-stream.sh'
            youtube_cmd = [
                'bash',
                str(youtube_script),
                stream['url'],
                stream_id
            ]

            youtube_log = open(LOGS_DIR / f'youtube-{stream_id}.log', 'w')
            youtube_proc = subprocess.Popen(
                youtube_cmd,
                stdout=youtube_log,
                stderr=youtube_log,
                stdin=subprocess.DEVNULL,
                start_new_session=True
            )

            self.processes[stream_id]['youtube'] = youtube_proc
            self.processes[stream_id]['youtube_log'] = youtube_log
            logger.info(f"[{stream_id}] YouTube stream iniciado via yt-dlp")

            # Aguardar um pouco para começar
            time.sleep(3)

            self.status[stream_id]['state'] = 'running'
            self.emit_status_update()

            return True, "Stream YouTube iniciado via yt-dlp"

        except Exception as e:
            logger.error(f"Erro ao iniciar stream YouTube {stream_id}: {e}")
            self.stop_stream(stream_id)
            return False, str(e)
'''

# Adicionar detecção de YouTube
youtube_detection = '''
    def is_youtube(self, url):
        """Detecta se URL é do YouTube"""
        return 'youtube.com' in url.lower() or 'youtu.be' in url.lower()
'''

# Modificar start_stream para detectar YouTube
find_str = '''    def start_stream(self, stream_id):
        """Inicia um stream"""
        if stream_id not in self.streams:
            return False, "Stream não encontrado"

        if stream_id in self.processes:
            return False, "Stream já está rodando"

        stream = self.streams[stream_id]'''

replace_str = '''    def start_stream(self, stream_id):
        """Inicia um stream"""
        if stream_id not in self.streams:
            return False, "Stream não encontrado"

        # Detectar YouTube e usar yt-dlp
        stream = self.streams[stream_id]
        if self.is_youtube(stream['url']):
            logger.info(f"[{stream_id}] Detectado YouTube - usando yt-dlp")
            return self.start_youtube_stream(stream_id)

        if stream_id in self.processes:
            return False, "Stream já está rodando"'''

# Modificar stop_stream para incluir processo youtube
find_stop = '''            # Parar na ordem inversa
            for proc_name in ['ffmpeg', 'browser', 'xvfb']:'''

replace_stop = '''            # Parar na ordem inversa
            for proc_name in ['youtube', 'ffmpeg', 'browser', 'xvfb']:'''

# Aplicar modificações
if youtube_detection not in content:
    # Encontrar local para inserir (após classe StreamManager)
    insert_pos = content.find('\n    def start_stream(self, stream_id):')
    if insert_pos > 0:
        content = (content[:insert_pos] +
                   youtube_detection +
                   ytdlp_method +
                   content[insert_pos:])
        print("✓ Métodos YouTube adicionados")

content = content.replace(find_str, replace_str)
print("✓ start_stream modificado para detectar YouTube")

content = content.replace(find_stop, replace_stop)
print("✓ stop_stream modificado")

# Salvar arquivo modificado
with open('/opt/stream-manager/scripts/stream-manager.py', 'w') as f:
    f.write(content)

print("\n✅ Patch yt-dlp aplicado com sucesso!")
print("\nPróximos passos:")
print("1. Instalar yt-dlp: pip3 install yt-dlp")
print("2. Tornar script executável: chmod +x /opt/stream-manager/scripts/youtube-stream.sh")
print("3. Reiniciar: systemctl restart stream-manager")
