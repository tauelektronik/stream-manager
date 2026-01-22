#!/usr/bin/env python3
"""
Cache Capture - Captura fragmentos de vídeo do cache do navegador
Monitora o cache do Chrome e extrai fragmentos de vídeo em tempo real
"""

import os
import sys
import time
import subprocess
import logging
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import magic

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class CacheCaptureHandler(FileSystemEventHandler):
    """Handler para monitorar arquivos do cache"""

    def __init__(self, stream_id, hls_dir, temp_dir):
        self.stream_id = stream_id
        self.hls_dir = Path(hls_dir)
        self.temp_dir = Path(temp_dir)
        self.fragments = []
        self.segment_num = 0

        # Criar diretórios
        self.hls_dir.mkdir(parents=True, exist_ok=True)
        self.temp_dir.mkdir(parents=True, exist_ok=True)

        # Detector de tipo MIME
        self.mime = magic.Magic(mime=True)

        logger.info(f"Cache Capture iniciado para {stream_id}")
        logger.info(f"HLS Dir: {self.hls_dir}")
        logger.info(f"Temp Dir: {self.temp_dir}")

    def is_video_fragment(self, file_path):
        """Verifica se arquivo é fragmento de vídeo"""
        try:
            # Verificar tamanho mínimo (100KB)
            if os.path.getsize(file_path) < 100 * 1024:
                return False

            # Verificar tipo MIME
            mime_type = self.mime.from_file(file_path)

            # Aceitar vídeo, MPEG, ou dados binários (fragmentos podem não ter MIME correto)
            if any(x in mime_type.lower() for x in ['video', 'mpeg', 'mp4', 'webm', 'octet-stream']):
                return True

            # Verificar magic bytes manualmente
            with open(file_path, 'rb') as f:
                header = f.read(12)

            # MPEG-TS: 0x47 (sync byte)
            # MP4/M4S: ftyp, mdat, moov
            # WebM: 0x1A45DFA3
            if (header[0:1] == b'\x47' or  # MPEG-TS
                b'ftyp' in header or
                b'mdat' in header or
                b'moov' in header or
                header[0:4] == b'\x1A\x45\xDF\xA3'):  # WebM
                return True

        except Exception as e:
            logger.debug(f"Erro ao verificar {file_path}: {e}")

        return False

    def on_created(self, event):
        """Callback quando arquivo é criado no cache"""
        if event.is_directory:
            return

        file_path = Path(event.src_path)

        # Dar tempo para o arquivo ser escrito completamente
        time.sleep(0.5)

        # Verificar se é fragmento de vídeo
        if self.is_video_fragment(str(file_path)):
            self.capture_fragment(file_path)

    def on_modified(self, event):
        """Callback quando arquivo é modificado"""
        # Chrome pode modificar arquivos durante download
        if not event.is_directory:
            file_path = Path(event.src_path)
            if self.is_video_fragment(str(file_path)):
                self.capture_fragment(file_path)

    def capture_fragment(self, file_path):
        """Captura fragmento de vídeo"""
        try:
            # Nome único para o fragmento
            timestamp = int(time.time() * 1000000)
            fragment_name = f"fragment_{timestamp}.ts"
            fragment_path = self.temp_dir / fragment_name

            # Copiar fragmento
            subprocess.run(['cp', str(file_path), str(fragment_path)], check=True)

            # Adicionar à lista
            self.fragments.append(fragment_path)
            logger.info(f"Fragmento capturado: {file_path.name} -> {fragment_name}")

            # Se temos fragmentos suficientes, gerar HLS
            if len(self.fragments) >= 3:
                self.generate_hls()

        except Exception as e:
            logger.error(f"Erro ao capturar fragmento: {e}")

    def generate_hls(self):
        """Gera playlist HLS a partir dos fragmentos"""
        try:
            # Criar arquivo de concatenação
            concat_file = self.temp_dir / 'concat.txt'
            with open(concat_file, 'w') as f:
                for frag in self.fragments[-10:]:  # Últimos 10 fragmentos
                    if frag.exists():
                        f.write(f"file '{frag}'\n")

            # Gerar HLS com FFmpeg
            output_file = self.hls_dir / 'index.m3u8'
            segment_pattern = self.hls_dir / 'segment_%03d.ts'

            cmd = [
                'ffmpeg',
                '-f', 'concat',
                '-safe', '0',
                '-i', str(concat_file),
                '-c', 'copy',
                '-f', 'hls',
                '-hls_time', '2',
                '-hls_list_size', '10',
                '-hls_flags', 'delete_segments+append_list',
                '-hls_segment_filename', str(segment_pattern),
                str(output_file),
                '-y'
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                timeout=5
            )

            if result.returncode == 0:
                logger.info(f"HLS gerado: {len(self.fragments)} fragmentos")
                self.segment_num += 1

                # Limpar fragmentos antigos
                self.cleanup_old_fragments()
            else:
                logger.warning(f"FFmpeg warning: {result.stderr.decode()[:200]}")

        except subprocess.TimeoutExpired:
            logger.warning("FFmpeg timeout - continuando...")
        except Exception as e:
            logger.error(f"Erro ao gerar HLS: {e}")

    def cleanup_old_fragments(self):
        """Remove fragmentos antigos"""
        # Manter apenas últimos 20 fragmentos na memória
        if len(self.fragments) > 20:
            old_fragments = self.fragments[:-10]
            for frag in old_fragments:
                try:
                    if frag.exists():
                        frag.unlink()
                except:
                    pass
            self.fragments = self.fragments[-10:]

        # Remover arquivos .ts antigos do temp
        for old_file in self.temp_dir.glob('fragment_*.ts'):
            try:
                # Deletar se mais de 2 minutos
                if time.time() - old_file.stat().st_mtime > 120:
                    old_file.unlink()
            except:
                pass


def main():
    if len(sys.argv) != 3:
        print("Uso: cache-capture.py <profile_dir> <stream_id>")
        sys.exit(1)

    profile_dir = Path(sys.argv[1])
    stream_id = sys.argv[2]

    # Diretórios
    cache_dir = profile_dir / 'Default' / 'Cache' / 'Cache_Data'
    hls_dir = Path('/var/www/hls') / stream_id
    temp_dir = Path('/tmp') / f'stream-cache-{stream_id}'

    # Verificar se cache existe
    if not cache_dir.exists():
        logger.error(f"Diretório de cache não existe: {cache_dir}")
        # Tentar alternativas
        cache_dir = profile_dir / 'Default' / 'Service Worker' / 'CacheStorage'
        if not cache_dir.exists():
            cache_dir = profile_dir / 'Default' / 'Code Cache'

    logger.info(f"Monitorando: {cache_dir}")

    # Criar handler e observer
    handler = CacheCaptureHandler(stream_id, hls_dir, temp_dir)
    observer = Observer()
    observer.schedule(handler, str(cache_dir), recursive=True)

    # Iniciar monitoramento
    observer.start()

    try:
        logger.info("Monitoramento ativo. Ctrl+C para parar.")
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
        logger.info("Parando...")

    observer.join()


if __name__ == '__main__':
    main()
