#!/bin/bash
echo "=== REINICIANDO STREAM MANAGER ==="
systemctl restart stream-manager
sleep 3

echo ""
echo "=== STATUS DO SERVIÇO ==="
systemctl status stream-manager --no-pager | head -15

echo ""
echo "=== TESTAR API ==="
curl -s http://localhost:8080/api/streams | python3 -c "import sys,json; print('Streams carregados:', len(json.load(sys.stdin)))"

echo ""
echo "=== INICIAR YOUTUBE ==="
curl -s -X POST http://localhost:8080/api/streams/youtube_exemplo/start | python3 -m json.tool

echo ""
echo "Aguardando 20 segundos..."
sleep 20

echo ""
echo "=== VERIFICAR STATUS DO YOUTUBE ==="
curl -s http://localhost:8080/api/streams/youtube_exemplo | python3 -m json.tool | head -30

echo ""
echo "=== VERIFICAR ARQUIVOS HLS ==="
ls -lah /var/www/hls/youtube_exemplo/ | head -15

echo ""
echo "=== LOGS RECENTES ==="
journalctl -u stream-manager -n 20 --no-pager | tail -15

echo ""
echo "CONCLUÍDO!"
