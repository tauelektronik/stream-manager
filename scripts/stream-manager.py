#!/usr/bin/env python3
"""
Stream Manager - Backend Principal
Sistema de gerenciamento de streams de navegador
"""

import os
import sys
import json
import signal
import subprocess
import threading
import time
import logging
import psutil
from datetime import datetime
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory
from flask_socketio import SocketIO, emit
from flask_cors import CORS

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/stream-manager/logs/stream-manager.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Diretórios
BASE_DIR = Path('/opt/stream-manager')
CONFIG_DIR = BASE_DIR / 'config'
PROFILES_DIR = BASE_DIR / 'profiles'
LOGS_DIR = BASE_DIR / 'logs'
HLS_DIR = Path('/var/www/hls')
SCRIPTS_DIR = BASE_DIR / 'scripts'

# Criar diretórios se não existirem
for dir_path in [CONFIG_DIR, PROFILES_DIR, LOGS_DIR, HLS_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)

# Flask app
app = Flask(__name__, static_folder=str(BASE_DIR / 'web'))
app.config['SECRET_KEY'] = os.urandom(24).hex()
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

# Estado global dos streams
class StreamManager:
    def __init__(self):
        self.streams = {}  # Configuração dos streams
        self.processes = {}  # Processos ativos {stream_id: {xvfb, browser, ffmpeg, vnc}}
        self.status = {}  # Status dos streams
        self.load_config()

    def load_config(self):
        """Carrega configuração do arquivo JSON"""
        config_file = CONFIG_DIR / 'streams.json'
        if config_file.exists():
            try:
                with open(config_file, 'r') as f:
                    data = json.load(f)
                    self.streams = {s['id']: s for s in data.get('streams', [])}
                    self.server_config = data.get('server', {})
                logger.info(f"Configuração carregada: {len(self.streams)} streams")
            except Exception as e:
                logger.error(f"Erro ao carregar config: {e}")
                self.streams = {}
                self.server_config = {}
        else:
            self.streams = {}
            self.server_config = {'port': 8080, 'hls_time': 2, 'hls_list_size': 5}

    def save_config(self):
        """Salva configuração no arquivo JSON"""
        config_file = CONFIG_DIR / 'streams.json'
        try:
            data = {
                'streams': list(self.streams.values()),
                'server': self.server_config
            }
            with open(config_file, 'w') as f:
                json.dump(data, f, indent=2)
            logger.info("Configuração salva")
        except Exception as e:
            logger.error(f"Erro ao salvar config: {e}")

    def get_display_number(self, stream_id):
        """Gera número de display único para cada stream"""
        base = 99
        index = list(self.streams.keys()).index(stream_id) if stream_id in self.streams else len(self.streams)
        return base + index

    def start_stream(self, stream_id):
        """Inicia um stream"""
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

            # 1. Iniciar Xvfb (display virtual)
            xvfb_cmd = [
                'Xvfb', f':{display}',
                '-screen', '0', f'{width}x{height}x24',
                '-ac'
            ]
            xvfb_proc = subprocess.Popen(
                xvfb_cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            self.processes[stream_id]['xvfb'] = xvfb_proc
            time.sleep(1)
            logger.info(f"[{stream_id}] Xvfb iniciado no display :{display}")

            # 2. Iniciar PulseAudio virtual
            pulse_cmd = [
                'pulseaudio',
                '--start',
                '--exit-idle-time=-1',
                f'--high-priority'
            ]
            subprocess.run(pulse_cmd, env={**os.environ, 'DISPLAY': f':{display}'}, capture_output=True)

            # 3. Criar diretório do perfil se não existir
            profile_name = stream.get('profile', stream_id)
            profile_dir = PROFILES_DIR / profile_name
            profile_dir.mkdir(parents=True, exist_ok=True)

            # 4. Iniciar navegador
            browser_cmd = [
                'chromium-browser',
                '--no-sandbox',
                '--disable-gpu',
                '--disable-dev-shm-usage',
                '--disable-software-rasterizer',
                f'--window-size={width},{height}',
                '--start-maximized',
                '--autoplay-policy=no-user-gesture-required',
                '--disable-features=PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies',
                f'--user-data-dir={profile_dir}',
                stream['url']
            ]
            browser_env = {**os.environ, 'DISPLAY': f':{display}'}
            browser_proc = subprocess.Popen(
                browser_cmd,
                env=browser_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            self.processes[stream_id]['browser'] = browser_proc
            time.sleep(3)
            logger.info(f"[{stream_id}] Browser iniciado")

            # 5. Iniciar FFmpeg para capturar e enviar para RTMP
            audio_opts = []
            if stream.get('audio', True):
                audio_opts = [
                    '-f', 'pulse',
                    '-i', 'default'
                ]

            ffmpeg_cmd = [
                'ffmpeg',
                '-y',
                '-f', 'x11grab',
                '-framerate', '30',
                '-video_size', resolution,
                '-i', f':{display}',
            ] + audio_opts + [
                '-c:v', 'libx264',
                '-preset', 'veryfast',
                '-tune', 'zerolatency',
                '-b:v', '2500k',
                '-maxrate', '2500k',
                '-bufsize', '5000k',
                '-pix_fmt', 'yuv420p',
                '-g', '60',
                '-c:a', 'aac',
                '-b:a', '128k',
                '-ar', '44100',
                '-f', 'flv',
                f'rtmp://127.0.0.1:1935/live/{stream_id}'
            ]

            ffmpeg_log = open(LOGS_DIR / f'ffmpeg-{stream_id}.log', 'w')
            ffmpeg_proc = subprocess.Popen(
                ffmpeg_cmd,
                env={**os.environ, 'DISPLAY': f':{display}'},
                stdout=ffmpeg_log,
                stderr=ffmpeg_log
            )
            self.processes[stream_id]['ffmpeg'] = ffmpeg_proc
            self.processes[stream_id]['ffmpeg_log'] = ffmpeg_log
            logger.info(f"[{stream_id}] FFmpeg iniciado")

            self.status[stream_id]['state'] = 'running'
            self.emit_status_update()

            return True, "Stream iniciado com sucesso"

        except Exception as e:
            logger.error(f"Erro ao iniciar stream {stream_id}: {e}")
            self.stop_stream(stream_id)
            return False, str(e)

    def stop_stream(self, stream_id):
        """Para um stream"""
        if stream_id not in self.processes:
            return False, "Stream não está rodando"

        try:
            procs = self.processes.get(stream_id, {})

            # Parar na ordem inversa
            for proc_name in ['ffmpeg', 'browser', 'xvfb']:
                proc = procs.get(proc_name)
                if proc and proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                    logger.info(f"[{stream_id}] {proc_name} parado")

            # Fechar log do ffmpeg
            if 'ffmpeg_log' in procs:
                procs['ffmpeg_log'].close()

            # Limpar
            del self.processes[stream_id]
            if stream_id in self.status:
                del self.status[stream_id]

            # Limpar arquivos HLS
            hls_stream_dir = HLS_DIR / stream_id
            if hls_stream_dir.exists():
                import shutil
                shutil.rmtree(hls_stream_dir, ignore_errors=True)

            self.emit_status_update()
            return True, "Stream parado com sucesso"

        except Exception as e:
            logger.error(f"Erro ao parar stream {stream_id}: {e}")
            return False, str(e)

    def start_vnc(self, stream_id):
        """Inicia VNC para configurar login"""
        if stream_id not in self.processes:
            return False, "Stream não está rodando", None

        display = self.status.get(stream_id, {}).get('display')
        if not display:
            return False, "Display não encontrado", None

        vnc_port = 5900 + display - 99

        try:
            vnc_cmd = [
                'x11vnc',
                '-display', f':{display}',
                '-rfbport', str(vnc_port),
                '-nopw',
                '-forever',
                '-shared'
            ]
            vnc_proc = subprocess.Popen(
                vnc_cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            self.processes[stream_id]['vnc'] = vnc_proc
            logger.info(f"[{stream_id}] VNC iniciado na porta {vnc_port}")
            return True, f"VNC disponível na porta {vnc_port}", vnc_port
        except Exception as e:
            return False, str(e), None

    def stop_vnc(self, stream_id):
        """Para o VNC"""
        if stream_id in self.processes and 'vnc' in self.processes[stream_id]:
            vnc = self.processes[stream_id]['vnc']
            if vnc.poll() is None:
                vnc.terminate()
            del self.processes[stream_id]['vnc']
            return True, "VNC parado"
        return False, "VNC não está rodando"

    def get_all_status(self):
        """Retorna status de todos os streams"""
        result = {}
        for stream_id, stream in self.streams.items():
            is_running = stream_id in self.processes
            status = self.status.get(stream_id, {})

            result[stream_id] = {
                **stream,
                'running': is_running,
                'state': status.get('state', 'stopped'),
                'started_at': status.get('started_at'),
                'display': status.get('display'),
                'hls_url': f'/hls/{stream_id}/index.m3u8' if is_running else None,
                'rtmp_url': f'rtmp://{{server}}:1935/live/{stream_id}' if is_running else None,
                'vnc_active': 'vnc' in self.processes.get(stream_id, {})
            }
        return result

    def emit_status_update(self):
        """Envia atualização de status via WebSocket"""
        socketio.emit('status_update', self.get_all_status())

    def get_system_stats(self):
        """Retorna estatísticas do sistema"""
        return {
            'cpu_percent': psutil.cpu_percent(interval=1),
            'memory_percent': psutil.virtual_memory().percent,
            'disk_percent': psutil.disk_usage('/').percent,
            'active_streams': len(self.processes),
            'total_streams': len(self.streams)
        }


# Instância global
manager = StreamManager()


# Rotas da API
@app.route('/')
def index():
    return send_from_directory(app.static_folder, 'index.html')


@app.route('/<path:path>')
def static_files(path):
    return send_from_directory(app.static_folder, path)


@app.route('/api/streams', methods=['GET'])
def get_streams():
    """Lista todos os streams"""
    return jsonify(manager.get_all_status())


@app.route('/api/streams', methods=['POST'])
def add_stream():
    """Adiciona um novo stream"""
    data = request.json

    required = ['id', 'name', 'url']
    if not all(k in data for k in required):
        return jsonify({'error': 'Campos obrigatórios: id, name, url'}), 400

    if data['id'] in manager.streams:
        return jsonify({'error': 'Stream com este ID já existe'}), 400

    stream = {
        'id': data['id'],
        'name': data['name'],
        'url': data['url'],
        'profile': data.get('profile', data['id']),
        'resolution': data.get('resolution', '1280x720'),
        'audio': data.get('audio', True)
    }

    manager.streams[data['id']] = stream
    manager.save_config()
    manager.emit_status_update()

    return jsonify({'success': True, 'stream': stream})


@app.route('/api/streams/<stream_id>', methods=['PUT'])
def update_stream(stream_id):
    """Atualiza um stream existente"""
    if stream_id not in manager.streams:
        return jsonify({'error': 'Stream não encontrado'}), 404

    data = request.json
    stream = manager.streams[stream_id]

    for key in ['name', 'url', 'profile', 'resolution', 'audio']:
        if key in data:
            stream[key] = data[key]

    manager.save_config()
    manager.emit_status_update()

    return jsonify({'success': True, 'stream': stream})


@app.route('/api/streams/<stream_id>', methods=['DELETE'])
def delete_stream(stream_id):
    """Remove um stream"""
    if stream_id not in manager.streams:
        return jsonify({'error': 'Stream não encontrado'}), 404

    # Parar se estiver rodando
    if stream_id in manager.processes:
        manager.stop_stream(stream_id)

    del manager.streams[stream_id]
    manager.save_config()
    manager.emit_status_update()

    return jsonify({'success': True})


@app.route('/api/streams/<stream_id>/start', methods=['POST'])
def start_stream(stream_id):
    """Inicia um stream"""
    success, message = manager.start_stream(stream_id)
    status_code = 200 if success else 400
    return jsonify({'success': success, 'message': message}), status_code


@app.route('/api/streams/<stream_id>/stop', methods=['POST'])
def stop_stream(stream_id):
    """Para um stream"""
    success, message = manager.stop_stream(stream_id)
    status_code = 200 if success else 400
    return jsonify({'success': success, 'message': message}), status_code


@app.route('/api/streams/<stream_id>/vnc/start', methods=['POST'])
def start_vnc(stream_id):
    """Inicia VNC para um stream"""
    success, message, port = manager.start_vnc(stream_id)
    return jsonify({'success': success, 'message': message, 'port': port})


@app.route('/api/streams/<stream_id>/vnc/stop', methods=['POST'])
def stop_vnc(stream_id):
    """Para VNC de um stream"""
    success, message = manager.stop_vnc(stream_id)
    return jsonify({'success': success, 'message': message})


@app.route('/api/system/stats', methods=['GET'])
def get_system_stats():
    """Retorna estatísticas do sistema"""
    return jsonify(manager.get_system_stats())


@app.route('/api/profiles', methods=['GET'])
def get_profiles():
    """Lista perfis disponíveis"""
    profiles = []
    for profile_dir in PROFILES_DIR.iterdir():
        if profile_dir.is_dir():
            profiles.append({
                'name': profile_dir.name,
                'path': str(profile_dir),
                'size_mb': sum(f.stat().st_size for f in profile_dir.rglob('*') if f.is_file()) / (1024 * 1024)
            })
    return jsonify(profiles)


@app.route('/api/logs/<stream_id>', methods=['GET'])
def get_logs(stream_id):
    """Retorna logs do FFmpeg de um stream"""
    log_file = LOGS_DIR / f'ffmpeg-{stream_id}.log'
    if log_file.exists():
        with open(log_file, 'r') as f:
            lines = f.readlines()[-100:]  # Últimas 100 linhas
            return jsonify({'logs': ''.join(lines)})
    return jsonify({'logs': ''})


# WebSocket events
@socketio.on('connect')
def handle_connect():
    """Cliente conectou"""
    emit('status_update', manager.get_all_status())
    logger.info("Cliente WebSocket conectado")


@socketio.on('disconnect')
def handle_disconnect():
    """Cliente desconectou"""
    logger.info("Cliente WebSocket desconectado")


@socketio.on('request_status')
def handle_request_status():
    """Cliente solicitou atualização de status"""
    emit('status_update', manager.get_all_status())


# Thread para atualizar status periodicamente
def status_updater():
    """Atualiza status dos streams periodicamente"""
    while True:
        time.sleep(5)

        # Verificar processos mortos
        for stream_id in list(manager.processes.keys()):
            procs = manager.processes[stream_id]
            all_alive = all(
                procs.get(p) and procs[p].poll() is None
                for p in ['xvfb', 'browser', 'ffmpeg']
            )
            if not all_alive:
                logger.warning(f"[{stream_id}] Processo morreu, reiniciando...")
                manager.stop_stream(stream_id)
                time.sleep(2)
                manager.start_stream(stream_id)

        manager.emit_status_update()


# Handler para shutdown gracioso
def signal_handler(sig, frame):
    """Handle shutdown signals"""
    logger.info("Encerrando Stream Manager...")
    for stream_id in list(manager.processes.keys()):
        manager.stop_stream(stream_id)
    sys.exit(0)


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


if __name__ == '__main__':
    # Iniciar thread de atualização
    updater_thread = threading.Thread(target=status_updater, daemon=True)
    updater_thread.start()

    logger.info("Stream Manager iniciado")
    logger.info(f"Streams configurados: {len(manager.streams)}")

    # Iniciar servidor
    socketio.run(app, host='0.0.0.0', port=5000, debug=False)
