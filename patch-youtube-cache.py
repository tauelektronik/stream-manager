#!/usr/bin/env python3
"""
Patch para adicionar suporte a captura de cache do YouTube
Modifica o stream-manager.py para usar cache-capture em vez de screen capture
"""

import sys

# Ler arquivo original
with open('/opt/stream-manager/scripts/stream-manager.py', 'r') as f:
    content = f.read()

# Adicionar método para detectar YouTube
youtube_detection = '''
    def is_youtube(self, url):
        """Detecta se URL é do YouTube"""
        return 'youtube.com' in url or 'youtu.be' in url
'''

# Adicionar método de captura de cache
cache_capture_method = '''
    def start_youtube_cache_stream(self, stream_id):
        """Inicia stream do YouTube usando captura de cache"""
        if stream_id not in self.streams:
            return False, "Stream não encontrado"

        if stream_id in self.processes:
            return False, "Stream já está rodando"

        stream = self.streams[stream_id]
        display = self.get_display_number(stream_id)
        resolution = stream.get('resolution', '1280x720')
        width, height = resolution.split('x')

        try:
            self.processes[stream_id] = {}
            self.status[stream_id] = {
                'state': 'starting',
                'started_at': datetime.now().isoformat(),
                'display': display
            }
            self.emit_status_update()

            # 1. Iniciar Xvfb
            xvfb_cmd = [
                'Xvfb', f':{display}',
                '-screen', '0', f'{width}x{height}x24',
                '-ac'
            ]
            xvfb_proc = subprocess.Popen(
                xvfb_cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                start_new_session=True
            )
            self.processes[stream_id]['xvfb'] = xvfb_proc
            time.sleep(1)
            logger.info(f"[{stream_id}] Xvfb iniciado no display :{display}")

            # 2. Criar perfil
            profile_name = stream.get('profile', stream_id)
            profile_dir = PROFILES_DIR / profile_name
            profile_dir.mkdir(parents=True, exist_ok=True)

            # 3. Iniciar navegador (sem FFmpeg de tela!)
            browser_cmd = [
                'chromium-browser',
                '--no-sandbox',
                '--disable-gpu',
                '--disable-dev-shm-usage',
                '--disk-cache-size=524288000',  # 500MB de cache
                f'--window-size={width},{height}',
                '--start-maximized',
                '--autoplay-policy=no-user-gesture-required',
                f'--user-data-dir={profile_dir}',
                stream['url']
            ]
            browser_env = {**os.environ, 'DISPLAY': f':{display}'}
            browser_proc = subprocess.Popen(
                browser_cmd,
                env=browser_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                start_new_session=True
            )
            self.processes[stream_id]['browser'] = browser_proc
            time.sleep(5)  # Dar tempo para carregar
            logger.info(f"[{stream_id}] Browser iniciado (modo cache)")

            # 4. Iniciar cache capture
            cache_script = BASE_DIR / 'scripts' / 'cache-capture.py'
            cache_cmd = [
                sys.executable,
                str(cache_script),
                str(profile_dir),
                stream_id
            ]
            cache_log = open(LOGS_DIR / f'cache-{stream_id}.log', 'w')
            cache_proc = subprocess.Popen(
                cache_cmd,
                stdout=cache_log,
                stderr=cache_log,
                stdin=subprocess.DEVNULL,
                start_new_session=True
            )
            self.processes[stream_id]['cache_capture'] = cache_proc
            self.processes[stream_id]['cache_log'] = cache_log
            logger.info(f"[{stream_id}] Cache capture iniciado")

            self.status[stream_id]['state'] = 'running'
            self.status[stream_id]['method'] = 'cache'
            self.emit_status_update()

            return True, "Stream YouTube iniciado (captura de cache)"

        except Exception as e:
            logger.error(f"Erro ao iniciar stream YouTube {stream_id}: {e}")
            self.stop_stream(stream_id)
            return False, str(e)
'''

# Modificar o método start_stream original
original_start = '''    def start_stream(self, stream_id):
        """Inicia um stream"""
        if stream_id not in self.streams:
            return False, "Stream não encontrado"'''

new_start = '''    def start_stream(self, stream_id):
        """Inicia um stream"""
        if stream_id not in self.streams:
            return False, "Stream não encontrado"

        # Detectar YouTube e usar método de cache
        stream = self.streams[stream_id]
        if self.is_youtube(stream['url']):
            logger.info(f"[{stream_id}] Detectado YouTube - usando captura de cache")
            return self.start_youtube_cache_stream(stream_id)'''

# Modificar stop_stream para incluir cache_capture
original_stop = '''            # Parar na ordem inversa
            for proc_name in ['ffmpeg', 'browser', 'xvfb']:'''

new_stop = '''            # Parar na ordem inversa (incluindo cache_capture)
            for proc_name in ['cache_capture', 'ffmpeg', 'browser', 'xvfb']:'''

# Aplicar patches
if youtube_detection not in content:
    # Adicionar métodos após a classe StreamManager
    class_end = content.find('\n\n# Flask app')
    if class_end > 0:
        content = (content[:class_end] +
                   youtube_detection +
                   cache_capture_method +
                   content[class_end:])

content = content.replace(original_start, new_start, 1)
content = content.replace(original_stop, new_stop, 1)

# Salvar backup
with open('/opt/stream-manager/scripts/stream-manager.py.before-cache-patch', 'w') as f:
    with open('/opt/stream-manager/scripts/stream-manager.py', 'r') as orig:
        f.write(orig.read())

# Salvar modificado
with open('/opt/stream-manager/scripts/stream-manager.py', 'w') as f:
    f.write(content)

print("✅ Patch aplicado com sucesso!")
print("Backup salvo em: stream-manager.py.before-cache-patch")
print("")
print("Próximos passos:")
print("1. Instalar dependências: pip3 install watchdog python-magic")
print("2. Reiniciar serviço: systemctl restart stream-manager")
print("3. Testar YouTube: curl -X POST http://localhost:8080/api/streams/youtube_exemplo/start")
