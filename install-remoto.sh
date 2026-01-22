#!/bin/bash
#
# Stream Manager - Instalação Remota Completa
# Cole este script inteiro no terminal do servidor
#

set -e

echo "=========================================="
echo "  STREAM MANAGER - INSTALAÇÃO COMPLETA"
echo "=========================================="

# Criar estrutura
mkdir -p /opt/stream-manager/{config,scripts,profiles,logs,web/css,web/js}
mkdir -p /var/www/hls
cd /opt/stream-manager

echo "[1/8] Instalando dependências..."
apt-get update
apt-get install -y \
    build-essential libpcre3 libpcre3-dev libssl-dev zlib1g-dev \
    git wget curl unzip xvfb x11vnc pulseaudio ffmpeg \
    chromium-browser python3 python3-pip python3-venv \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1 \
    libasound2 libpango-1.0-0 libpangocairo-1.0-0 libgtk-3-0

echo "[2/8] Compilando Nginx com RTMP..."
cd /tmp
wget -q http://nginx.org/download/nginx-1.24.0.tar.gz
tar -xzf nginx-1.24.0.tar.gz
git clone https://github.com/arut/nginx-rtmp-module.git
cd nginx-1.24.0
./configure --prefix=/etc/nginx --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log --pid-path=/var/run/nginx.pid \
    --with-http_ssl_module --with-http_v2_module --add-module=../nginx-rtmp-module
make -j$(nproc)
make install
mkdir -p /var/log/nginx /etc/nginx/conf.d
cd /opt/stream-manager
rm -rf /tmp/nginx-1.24.0* /tmp/nginx-rtmp-module

echo "[3/8] Criando configuração Nginx..."
cat > /etc/nginx/nginx.conf << 'NGINXCONF'
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

rtmp {
    server {
        listen 1935;
        chunk_size 4096;
        allow publish 127.0.0.1;
        deny publish all;

        application live {
            live on;
            record off;
            hls on;
            hls_path /var/www/hls;
            hls_fragment 2s;
            hls_playlist_length 10s;
            hls_cleanup on;
            hls_nested on;
            allow play all;
        }
    }
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    types {
        application/vnd.apple.mpegurl m3u8;
        video/mp2t ts;
    }

    server {
        listen 8080;
        server_name _;
        root /opt/stream-manager/web;
        index index.html;

        add_header Access-Control-Allow-Origin * always;

        location / {
            try_files $uri $uri/ /index.html;
        }

        location /api/ {
            proxy_pass http://127.0.0.1:5000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_read_timeout 86400;
        }

        location /socket.io/ {
            proxy_pass http://127.0.0.1:5000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400;
        }

        location /hls/ {
            alias /var/www/hls/;
            add_header Cache-Control no-cache;
            add_header Access-Control-Allow-Origin * always;
        }
    }
}
NGINXCONF

echo "[4/8] Criando backend Python..."
cat > /opt/stream-manager/scripts/stream-manager.py << 'PYTHONCODE'
#!/usr/bin/env python3
import os, sys, json, signal, subprocess, threading, time, logging, psutil
from datetime import datetime
from pathlib import Path
from flask import Flask, jsonify, request, send_from_directory
from flask_socketio import SocketIO, emit
from flask_cors import CORS

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler('/opt/stream-manager/logs/stream-manager.log'), logging.StreamHandler()])
logger = logging.getLogger(__name__)

BASE_DIR = Path('/opt/stream-manager')
CONFIG_DIR = BASE_DIR / 'config'
PROFILES_DIR = BASE_DIR / 'profiles'
LOGS_DIR = BASE_DIR / 'logs'
HLS_DIR = Path('/var/www/hls')

for d in [CONFIG_DIR, PROFILES_DIR, LOGS_DIR, HLS_DIR]:
    d.mkdir(parents=True, exist_ok=True)

app = Flask(__name__, static_folder=str(BASE_DIR / 'web'))
app.config['SECRET_KEY'] = os.urandom(24).hex()
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

class StreamManager:
    def __init__(self):
        self.streams = {}
        self.processes = {}
        self.status = {}
        self.load_config()

    def load_config(self):
        config_file = CONFIG_DIR / 'streams.json'
        if config_file.exists():
            try:
                with open(config_file, 'r') as f:
                    data = json.load(f)
                    self.streams = {s['id']: s for s in data.get('streams', [])}
            except: pass

    def save_config(self):
        config_file = CONFIG_DIR / 'streams.json'
        with open(config_file, 'w') as f:
            json.dump({'streams': list(self.streams.values()), 'server': {'port': 8080}}, f, indent=2)

    def get_display_number(self, stream_id):
        return 99 + list(self.streams.keys()).index(stream_id) if stream_id in self.streams else 99 + len(self.streams)

    def start_stream(self, stream_id):
        if stream_id not in self.streams: return False, "Stream não encontrado"
        if stream_id in self.processes: return False, "Stream já está rodando"

        stream = self.streams[stream_id]
        display = self.get_display_number(stream_id)
        resolution = stream.get('resolution', '1280x720')
        width, height = resolution.split('x')

        try:
            self.processes[stream_id] = {}
            self.status[stream_id] = {'state': 'starting', 'started_at': datetime.now().isoformat(), 'display': display}
            self.emit_status_update()

            xvfb = subprocess.Popen(['Xvfb', f':{display}', '-screen', '0', f'{width}x{height}x24', '-ac'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.processes[stream_id]['xvfb'] = xvfb
            time.sleep(1)

            profile_dir = PROFILES_DIR / stream.get('profile', stream_id)
            profile_dir.mkdir(parents=True, exist_ok=True)

            browser = subprocess.Popen([
                'chromium-browser', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage',
                f'--window-size={width},{height}', '--start-maximized',
                '--autoplay-policy=no-user-gesture-required', f'--user-data-dir={profile_dir}', stream['url']
            ], env={**os.environ, 'DISPLAY': f':{display}'}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.processes[stream_id]['browser'] = browser
            time.sleep(3)

            ffmpeg_cmd = ['ffmpeg', '-y', '-f', 'x11grab', '-framerate', '30', '-video_size', resolution,
                '-i', f':{display}', '-f', 'pulse', '-i', 'default',
                '-c:v', 'libx264', '-preset', 'veryfast', '-tune', 'zerolatency', '-b:v', '2500k',
                '-pix_fmt', 'yuv420p', '-g', '60', '-c:a', 'aac', '-b:a', '128k',
                '-f', 'flv', f'rtmp://127.0.0.1:1935/live/{stream_id}']

            ffmpeg_log = open(LOGS_DIR / f'ffmpeg-{stream_id}.log', 'w')
            ffmpeg = subprocess.Popen(ffmpeg_cmd, env={**os.environ, 'DISPLAY': f':{display}'},
                stdout=ffmpeg_log, stderr=ffmpeg_log)
            self.processes[stream_id]['ffmpeg'] = ffmpeg
            self.processes[stream_id]['ffmpeg_log'] = ffmpeg_log

            self.status[stream_id]['state'] = 'running'
            self.emit_status_update()
            return True, "Stream iniciado"
        except Exception as e:
            self.stop_stream(stream_id)
            return False, str(e)

    def stop_stream(self, stream_id):
        if stream_id not in self.processes: return False, "Stream não está rodando"
        procs = self.processes.get(stream_id, {})
        for name in ['ffmpeg', 'browser', 'xvfb']:
            proc = procs.get(name)
            if proc and proc.poll() is None:
                proc.terminate()
                try: proc.wait(timeout=5)
                except: proc.kill()
        if 'ffmpeg_log' in procs: procs['ffmpeg_log'].close()
        del self.processes[stream_id]
        if stream_id in self.status: del self.status[stream_id]
        self.emit_status_update()
        return True, "Stream parado"

    def start_vnc(self, stream_id):
        if stream_id not in self.processes: return False, "Stream não está rodando", None
        display = self.status.get(stream_id, {}).get('display')
        if not display: return False, "Display não encontrado", None
        vnc_port = 5900 + display - 99
        vnc = subprocess.Popen(['x11vnc', '-display', f':{display}', '-rfbport', str(vnc_port), '-nopw', '-forever'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.processes[stream_id]['vnc'] = vnc
        return True, f"VNC na porta {vnc_port}", vnc_port

    def stop_vnc(self, stream_id):
        if stream_id in self.processes and 'vnc' in self.processes[stream_id]:
            self.processes[stream_id]['vnc'].terminate()
            del self.processes[stream_id]['vnc']
            return True, "VNC parado"
        return False, "VNC não está rodando"

    def get_all_status(self):
        result = {}
        for sid, stream in self.streams.items():
            running = sid in self.processes
            status = self.status.get(sid, {})
            result[sid] = {**stream, 'running': running, 'state': status.get('state', 'stopped'),
                'started_at': status.get('started_at'), 'display': status.get('display'),
                'hls_url': f'/hls/{sid}/index.m3u8' if running else None,
                'vnc_active': 'vnc' in self.processes.get(sid, {})}
        return result

    def emit_status_update(self):
        socketio.emit('status_update', self.get_all_status())

    def get_system_stats(self):
        return {'cpu_percent': psutil.cpu_percent(), 'memory_percent': psutil.virtual_memory().percent,
            'active_streams': len(self.processes), 'total_streams': len(self.streams)}

manager = StreamManager()

@app.route('/')
def index(): return send_from_directory(app.static_folder, 'index.html')

@app.route('/<path:path>')
def static_files(path): return send_from_directory(app.static_folder, path)

@app.route('/api/streams', methods=['GET'])
def get_streams(): return jsonify(manager.get_all_status())

@app.route('/api/streams', methods=['POST'])
def add_stream():
    data = request.json
    if not all(k in data for k in ['id', 'name', 'url']): return jsonify({'error': 'Campos obrigatórios: id, name, url'}), 400
    if data['id'] in manager.streams: return jsonify({'error': 'ID já existe'}), 400
    stream = {'id': data['id'], 'name': data['name'], 'url': data['url'],
        'profile': data.get('profile', data['id']), 'resolution': data.get('resolution', '1280x720'), 'audio': data.get('audio', True)}
    manager.streams[data['id']] = stream
    manager.save_config()
    manager.emit_status_update()
    return jsonify({'success': True, 'stream': stream})

@app.route('/api/streams/<stream_id>', methods=['PUT'])
def update_stream(stream_id):
    if stream_id not in manager.streams: return jsonify({'error': 'Não encontrado'}), 404
    data = request.json
    for key in ['name', 'url', 'profile', 'resolution', 'audio']:
        if key in data: manager.streams[stream_id][key] = data[key]
    manager.save_config()
    manager.emit_status_update()
    return jsonify({'success': True})

@app.route('/api/streams/<stream_id>', methods=['DELETE'])
def delete_stream(stream_id):
    if stream_id not in manager.streams: return jsonify({'error': 'Não encontrado'}), 404
    if stream_id in manager.processes: manager.stop_stream(stream_id)
    del manager.streams[stream_id]
    manager.save_config()
    manager.emit_status_update()
    return jsonify({'success': True})

@app.route('/api/streams/<stream_id>/start', methods=['POST'])
def start_stream(stream_id):
    success, msg = manager.start_stream(stream_id)
    return jsonify({'success': success, 'message': msg}), 200 if success else 400

@app.route('/api/streams/<stream_id>/stop', methods=['POST'])
def stop_stream(stream_id):
    success, msg = manager.stop_stream(stream_id)
    return jsonify({'success': success, 'message': msg}), 200 if success else 400

@app.route('/api/streams/<stream_id>/vnc/start', methods=['POST'])
def start_vnc(stream_id):
    success, msg, port = manager.start_vnc(stream_id)
    return jsonify({'success': success, 'message': msg, 'port': port})

@app.route('/api/streams/<stream_id>/vnc/stop', methods=['POST'])
def stop_vnc(stream_id):
    success, msg = manager.stop_vnc(stream_id)
    return jsonify({'success': success, 'message': msg})

@app.route('/api/system/stats', methods=['GET'])
def get_stats(): return jsonify(manager.get_system_stats())

@app.route('/api/logs/<stream_id>', methods=['GET'])
def get_logs(stream_id):
    log_file = LOGS_DIR / f'ffmpeg-{stream_id}.log'
    if log_file.exists():
        with open(log_file, 'r') as f: return jsonify({'logs': ''.join(f.readlines()[-100:])})
    return jsonify({'logs': ''})

@socketio.on('connect')
def handle_connect(): emit('status_update', manager.get_all_status())

def signal_handler(sig, frame):
    for sid in list(manager.processes.keys()): manager.stop_stream(sid)
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=False)
PYTHONCODE

echo "[5/8] Criando interface web..."
cat > /opt/stream-manager/web/index.html << 'HTMLCODE'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Stream Manager</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <div class="app">
        <header class="header">
            <div class="header-left"><h1>Stream Manager</h1></div>
            <div class="header-right">
                <div class="system-stats">
                    <div class="stat"><span class="stat-label">CPU</span><span class="stat-value" id="cpu-stat">0%</span></div>
                    <div class="stat"><span class="stat-label">RAM</span><span class="stat-value" id="ram-stat">0%</span></div>
                    <div class="stat"><span class="stat-label">Streams</span><span class="stat-value" id="streams-stat">0/0</span></div>
                </div>
            </div>
        </header>
        <main class="main">
            <div class="toolbar">
                <button class="btn btn-primary" id="btn-add-stream"><span class="icon">+</span> Novo Stream</button>
                <button class="btn btn-secondary" id="btn-start-all">Iniciar Todos</button>
                <button class="btn btn-danger" id="btn-stop-all">Parar Todos</button>
                <div class="toolbar-spacer"></div>
                <button class="btn btn-icon" id="btn-refresh" title="Atualizar">↻</button>
            </div>
            <div class="streams-container" id="streams-container">
                <div class="empty-state" id="empty-state">
                    <div class="empty-icon">📺</div>
                    <h3>Nenhum stream configurado</h3>
                    <p>Clique em "Novo Stream" para adicionar</p>
                </div>
            </div>
        </main>
        <div class="modal" id="modal-stream">
            <div class="modal-overlay"></div>
            <div class="modal-content">
                <div class="modal-header"><h2 id="modal-stream-title">Novo Stream</h2><button class="btn-close" id="btn-close-modal">&times;</button></div>
                <form id="form-stream">
                    <div class="form-group"><label for="stream-id">ID</label><input type="text" id="stream-id" name="id" required pattern="[a-zA-Z0-9_-]+"></div>
                    <div class="form-group"><label for="stream-name">Nome</label><input type="text" id="stream-name" name="name" required></div>
                    <div class="form-group"><label for="stream-url">URL</label><input type="url" id="stream-url" name="url" required></div>
                    <div class="form-row">
                        <div class="form-group"><label for="stream-resolution">Resolução</label>
                            <select id="stream-resolution" name="resolution">
                                <option value="1920x1080">1920x1080</option>
                                <option value="1280x720" selected>1280x720</option>
                                <option value="854x480">854x480</option>
                            </select>
                        </div>
                        <div class="form-group"><label for="stream-profile">Perfil</label><input type="text" id="stream-profile" name="profile"></div>
                    </div>
                    <div class="form-group"><label class="checkbox-label"><input type="checkbox" id="stream-audio" name="audio" checked> Capturar áudio</label></div>
                    <div class="form-actions"><button type="button" class="btn btn-secondary" id="btn-cancel-stream">Cancelar</button><button type="submit" class="btn btn-primary">Salvar</button></div>
                </form>
            </div>
        </div>
        <div class="modal" id="modal-links">
            <div class="modal-overlay"></div>
            <div class="modal-content">
                <div class="modal-header"><h2>Links do Stream</h2><button class="btn-close" id="btn-close-links">&times;</button></div>
                <div class="modal-body">
                    <div class="link-group"><label>HLS (VLC)</label><div class="link-input"><input type="text" id="link-hls" readonly><button class="btn btn-icon" onclick="copyLink('link-hls')">📋</button></div></div>
                    <div class="link-group"><label>RTMP</label><div class="link-input"><input type="text" id="link-rtmp" readonly><button class="btn btn-icon" onclick="copyLink('link-rtmp')">📋</button></div></div>
                </div>
            </div>
        </div>
        <div class="toast-container" id="toast-container"></div>
    </div>
    <script src="https://cdn.socket.io/4.7.2/socket.io.min.js"></script>
    <script src="js/app.js"></script>
</body>
</html>
HTMLCODE

cat > /opt/stream-manager/web/css/style.css << 'CSSCODE'
:root{--primary:#6366f1;--primary-hover:#4f46e5;--secondary:#64748b;--success:#22c55e;--danger:#ef4444;--bg:#0f172a;--bg-card:#1e293b;--bg-hover:#334155;--border:#334155;--text:#f8fafc;--text-muted:#94a3b8;--radius:12px;--radius-sm:8px}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:var(--bg);color:var(--text);min-height:100vh}
.app{display:flex;flex-direction:column;min-height:100vh}
.header{display:flex;justify-content:space-between;align-items:center;padding:1rem 2rem;background:var(--bg-card);border-bottom:1px solid var(--border)}
.header h1{font-size:1.5rem;background:linear-gradient(135deg,var(--primary),#a855f7);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.system-stats{display:flex;gap:1.5rem}
.stat{display:flex;flex-direction:column;align-items:center}
.stat-label{font-size:.75rem;color:var(--text-muted)}
.stat-value{font-size:1.125rem;font-weight:600}
.main{flex:1;padding:2rem;max-width:1600px;margin:0 auto;width:100%}
.toolbar{display:flex;gap:.75rem;margin-bottom:2rem;flex-wrap:wrap}
.toolbar-spacer{flex:1}
.btn{display:inline-flex;align-items:center;gap:.5rem;padding:.75rem 1.25rem;font-size:.875rem;font-weight:500;border:none;border-radius:var(--radius-sm);cursor:pointer;transition:all .2s}
.btn-primary{background:var(--primary);color:#fff}
.btn-primary:hover{background:var(--primary-hover)}
.btn-secondary{background:var(--secondary);color:#fff}
.btn-danger{background:var(--danger);color:#fff}
.btn-success{background:var(--success);color:#fff}
.btn-icon{padding:.5rem;min-width:2.5rem;justify-content:center;background:var(--bg);border:1px solid var(--border);color:var(--text)}
.btn-sm{padding:.5rem .75rem;font-size:.75rem}
.streams-container{display:grid;grid-template-columns:repeat(auto-fill,minmax(350px,1fr));gap:1.5rem}
.empty-state{grid-column:1/-1;text-align:center;padding:4rem 2rem;background:var(--bg-card);border-radius:var(--radius);border:2px dashed var(--border)}
.empty-state.hidden{display:none}
.empty-icon{font-size:4rem;margin-bottom:1rem}
.stream-card{background:var(--bg-card);border-radius:var(--radius);border:1px solid var(--border);overflow:hidden}
.stream-card:hover{border-color:var(--primary)}
.stream-card.running{border-color:var(--success)}
.stream-header{display:flex;justify-content:space-between;align-items:center;padding:1rem 1.25rem;background:var(--bg)}
.stream-title{display:flex;flex-direction:column}
.stream-name{font-weight:600}
.stream-id{font-size:.75rem;color:var(--text-muted);font-family:monospace}
.stream-status{display:flex;align-items:center;gap:.5rem;padding:.375rem .75rem;border-radius:9999px;font-size:.75rem;font-weight:500}
.stream-status.stopped{background:var(--bg-hover);color:var(--text-muted)}
.stream-status.running{background:#dcfce7;color:#15803d}
.status-dot{width:8px;height:8px;border-radius:50%;background:currentColor}
.stream-body{padding:1.25rem}
.stream-url{font-size:.875rem;color:var(--text-muted);word-break:break-all;margin-bottom:1rem;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.stream-meta{display:flex;gap:1rem;margin-bottom:1rem;font-size:.875rem;color:var(--text-muted)}
.stream-actions{display:flex;gap:.5rem;flex-wrap:wrap}
.modal{position:fixed;top:0;left:0;right:0;bottom:0;display:none;align-items:center;justify-content:center;z-index:1000;padding:1rem}
.modal.active{display:flex}
.modal-overlay{position:absolute;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.7)}
.modal-content{position:relative;background:var(--bg-card);border-radius:var(--radius);width:100%;max-width:500px;max-height:90vh;overflow:auto}
.modal-header{display:flex;justify-content:space-between;align-items:center;padding:1.25rem 1.5rem;border-bottom:1px solid var(--border)}
.btn-close{background:none;border:none;font-size:1.5rem;color:var(--text-muted);cursor:pointer}
.modal-body{padding:1.5rem}
form{padding:1.5rem}
.form-group{margin-bottom:1.25rem}
.form-row{display:grid;grid-template-columns:1fr 1fr;gap:1rem}
label{display:block;font-size:.875rem;font-weight:500;margin-bottom:.5rem;color:var(--text-muted)}
input[type="text"],input[type="url"],select{width:100%;padding:.75rem 1rem;font-size:.875rem;background:var(--bg);border:1px solid var(--border);border-radius:var(--radius-sm);color:var(--text)}
input:focus,select:focus{outline:none;border-color:var(--primary)}
.checkbox-label{display:flex;align-items:center;gap:.5rem;cursor:pointer}
.form-actions{display:flex;justify-content:flex-end;gap:.75rem;margin-top:1.5rem;padding-top:1.5rem;border-top:1px solid var(--border)}
.link-group{margin-bottom:1.25rem}
.link-input{display:flex;gap:.5rem}
.link-input input{flex:1;font-family:monospace}
.toast-container{position:fixed;bottom:2rem;right:2rem;display:flex;flex-direction:column;gap:.5rem;z-index:2000}
.toast{padding:1rem 1.25rem;background:var(--bg-card);border-radius:var(--radius-sm);border-left:4px solid var(--primary);animation:slideIn .3s}
.toast.success{border-left-color:var(--success)}
.toast.error{border-left-color:var(--danger)}
@keyframes slideIn{from{transform:translateX(100%);opacity:0}to{transform:translateX(0);opacity:1}}
CSSCODE

cat > /opt/stream-manager/web/js/app.js << 'JSCODE'
const state={streams:{},socket:null,editingStreamId:null,serverHost:window.location.hostname};
const elements={};
document.addEventListener('DOMContentLoaded',()=>{
    ['streamsContainer','emptyState','btnAddStream','btnStartAll','btnStopAll','btnRefresh','modalStream','modalStreamTitle','formStream','btnCloseModal','btnCancelStream','modalLinks','btnCloseLinks','cpuStat','ramStat','streamsStat','toastContainer'].forEach(id=>{
        const el=document.getElementById(id.replace(/([A-Z])/g,'-$1').toLowerCase());
        if(el)elements[id]=el;
    });
    elements.streamsContainer=document.getElementById('streams-container');
    elements.emptyState=document.getElementById('empty-state');
    elements.btnAddStream=document.getElementById('btn-add-stream');
    elements.btnStartAll=document.getElementById('btn-start-all');
    elements.btnStopAll=document.getElementById('btn-stop-all');
    elements.btnRefresh=document.getElementById('btn-refresh');
    elements.modalStream=document.getElementById('modal-stream');
    elements.modalStreamTitle=document.getElementById('modal-stream-title');
    elements.formStream=document.getElementById('form-stream');
    elements.btnCloseModal=document.getElementById('btn-close-modal');
    elements.btnCancelStream=document.getElementById('btn-cancel-stream');
    elements.modalLinks=document.getElementById('modal-links');
    elements.btnCloseLinks=document.getElementById('btn-close-links');
    elements.cpuStat=document.getElementById('cpu-stat');
    elements.ramStat=document.getElementById('ram-stat');
    elements.streamsStat=document.getElementById('streams-stat');
    elements.toastContainer=document.getElementById('toast-container');
    initSocket();initEventListeners();loadStreams();startStatsUpdater();
});
function initSocket(){
    state.socket=io({transports:['websocket','polling']});
    state.socket.on('status_update',data=>{state.streams=data;renderStreams();updateStreamsStat();});
}
function initEventListeners(){
    elements.btnAddStream.addEventListener('click',()=>openStreamModal());
    elements.btnStartAll.addEventListener('click',startAllStreams);
    elements.btnStopAll.addEventListener('click',stopAllStreams);
    elements.btnRefresh.addEventListener('click',loadStreams);
    elements.btnCloseModal.addEventListener('click',closeStreamModal);
    elements.btnCancelStream.addEventListener('click',closeStreamModal);
    elements.formStream.addEventListener('submit',handleStreamSubmit);
    elements.modalStream.querySelector('.modal-overlay').addEventListener('click',closeStreamModal);
    elements.btnCloseLinks.addEventListener('click',closeLinksModal);
    elements.modalLinks.querySelector('.modal-overlay').addEventListener('click',closeLinksModal);
}
async function apiCall(endpoint,method='GET',data=null){
    const options={method,headers:{'Content-Type':'application/json'}};
    if(data)options.body=JSON.stringify(data);
    const response=await fetch(`/api${endpoint}`,options);
    return response.json();
}
async function loadStreams(){state.streams=await apiCall('/streams');renderStreams();updateStreamsStat();}
async function loadSystemStats(){
    const stats=await apiCall('/system/stats');
    elements.cpuStat.textContent=`${stats.cpu_percent.toFixed(1)}%`;
    elements.ramStat.textContent=`${stats.memory_percent.toFixed(1)}%`;
}
function startStatsUpdater(){loadSystemStats();setInterval(loadSystemStats,5000);}
function updateStreamsStat(){
    const total=Object.keys(state.streams).length;
    const active=Object.values(state.streams).filter(s=>s.running).length;
    elements.streamsStat.textContent=`${active}/${total}`;
}
function renderStreams(){
    const streams=Object.values(state.streams);
    if(streams.length===0){elements.emptyState.classList.remove('hidden');document.querySelectorAll('.stream-card').forEach(c=>c.remove());return;}
    elements.emptyState.classList.add('hidden');
    document.querySelectorAll('.stream-card').forEach(c=>c.remove());
    streams.forEach(stream=>{elements.streamsContainer.appendChild(createStreamCard(stream));});
}
function createStreamCard(stream){
    const card=document.createElement('div');
    card.className=`stream-card ${stream.running?'running':'stopped'}`;
    card.innerHTML=`
        <div class="stream-header">
            <div class="stream-title"><span class="stream-name">${stream.name}</span><span class="stream-id">${stream.id}</span></div>
            <div class="stream-status ${stream.running?'running':'stopped'}"><span class="status-dot"></span>${stream.running?'Rodando':'Parado'}</div>
        </div>
        <div class="stream-body">
            <div class="stream-url">${stream.url}</div>
            <div class="stream-meta"><span>📐 ${stream.resolution}</span><span>${stream.audio?'🔊':'🔇'}</span></div>
            <div class="stream-actions">
                ${stream.running?`
                    <button class="btn btn-danger btn-sm" onclick="stopStream('${stream.id}')">Parar</button>
                    <button class="btn btn-secondary btn-sm" onclick="showLinks('${stream.id}')">Links</button>
                    <button class="btn btn-secondary btn-sm" onclick="toggleVNC('${stream.id}')">${stream.vnc_active?'Fechar VNC':'Abrir VNC'}</button>
                `:`<button class="btn btn-success btn-sm" onclick="startStream('${stream.id}')">Iniciar</button>`}
                <button class="btn btn-icon btn-sm" onclick="openStreamModal('${stream.id}')">✏️</button>
                <button class="btn btn-icon btn-sm" onclick="deleteStream('${stream.id}')">🗑️</button>
            </div>
        </div>`;
    return card;
}
async function startStream(id){await apiCall(`/streams/${id}/start`,'POST');showToast('Stream iniciando...','success');}
async function stopStream(id){await apiCall(`/streams/${id}/stop`,'POST');showToast('Stream parado','success');}
async function startAllStreams(){for(const s of Object.values(state.streams).filter(s=>!s.running)){await startStream(s.id);await new Promise(r=>setTimeout(r,2000));}}
async function stopAllStreams(){for(const s of Object.values(state.streams).filter(s=>s.running))await stopStream(s.id);}
async function deleteStream(id){if(!confirm('Excluir stream?'))return;await apiCall(`/streams/${id}`,'DELETE');showToast('Excluído','success');}
async function toggleVNC(id){
    const s=state.streams[id];
    const r=await apiCall(`/streams/${id}/vnc/${s.vnc_active?'stop':'start'}`,'POST');
    if(r.port)showToast(`VNC: ${state.serverHost}:${r.port}`,'success');
}
function openStreamModal(id=null){
    state.editingStreamId=id;
    const form=elements.formStream;
    if(id&&state.streams[id]){
        const s=state.streams[id];
        elements.modalStreamTitle.textContent='Editar Stream';
        form.elements['id'].value=s.id;form.elements['id'].disabled=true;
        form.elements['name'].value=s.name;form.elements['url'].value=s.url;
        form.elements['resolution'].value=s.resolution;form.elements['profile'].value=s.profile||'';
        form.elements['audio'].checked=s.audio;
    }else{elements.modalStreamTitle.textContent='Novo Stream';form.reset();form.elements['id'].disabled=false;}
    elements.modalStream.classList.add('active');
}
function closeStreamModal(){elements.modalStream.classList.remove('active');state.editingStreamId=null;}
async function handleStreamSubmit(e){
    e.preventDefault();
    const form=e.target;
    const data={id:form.elements['id'].value,name:form.elements['name'].value,url:form.elements['url'].value,
        resolution:form.elements['resolution'].value,profile:form.elements['profile'].value||form.elements['id'].value,audio:form.elements['audio'].checked};
    if(state.editingStreamId)await apiCall(`/streams/${state.editingStreamId}`,'PUT',data);
    else await apiCall('/streams','POST',data);
    closeStreamModal();showToast('Salvo!','success');
}
function showLinks(id){
    const port=window.location.port||'8080';
    document.getElementById('link-hls').value=`http://${state.serverHost}:${port}/hls/${id}/index.m3u8`;
    document.getElementById('link-rtmp').value=`rtmp://${state.serverHost}:1935/live/${id}`;
    elements.modalLinks.classList.add('active');
}
function closeLinksModal(){elements.modalLinks.classList.remove('active');}
function copyLink(id){document.getElementById(id).select();document.execCommand('copy');showToast('Copiado!','success');}
function showToast(msg,type='info'){
    const toast=document.createElement('div');
    toast.className=`toast ${type}`;toast.textContent=msg;
    elements.toastContainer.appendChild(toast);
    setTimeout(()=>{toast.style.opacity='0';setTimeout(()=>toast.remove(),300);},3000);
}
window.startStream=startStream;window.stopStream=stopStream;window.deleteStream=deleteStream;
window.toggleVNC=toggleVNC;window.showLinks=showLinks;window.openStreamModal=openStreamModal;window.copyLink=copyLink;
JSCODE

echo "[6/8] Criando configuração inicial..."
cat > /opt/stream-manager/config/streams.json << 'JSONCODE'
{"streams":[],"server":{"port":8080}}
JSONCODE

echo "[7/8] Configurando ambiente Python..."
cd /opt/stream-manager
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install flask flask-socketio flask-cors eventlet psutil

echo "[8/8] Criando serviços systemd..."
cat > /etc/systemd/system/nginx.service << 'EOF'
[Unit]
Description=Nginx HTTP and RTMP Server
After=network.target
[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/stream-manager.service << 'EOF'
[Unit]
Description=Stream Manager
After=network.target nginx.service
[Service]
Type=simple
User=root
WorkingDirectory=/opt/stream-manager
Environment=PATH=/opt/stream-manager/venv/bin:/usr/bin:/bin
ExecStart=/opt/stream-manager/venv/bin/python /opt/stream-manager/scripts/stream-manager.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nginx stream-manager
systemctl start nginx stream-manager

# Liberar portas
ufw allow 8080/tcp 2>/dev/null || true
ufw allow 1935/tcp 2>/dev/null || true

chown -R www-data:www-data /var/www/hls

SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================="
echo "  INSTALAÇÃO CONCLUÍDA!"
echo "=========================================="
echo ""
echo "Acesse: http://$SERVER_IP:8080"
echo ""
echo "Comandos úteis:"
echo "  systemctl status stream-manager"
echo "  systemctl restart stream-manager"
echo "  journalctl -u stream-manager -f"
echo ""
