# Script PowerShell para Diagnóstico Remoto
# Conecta ao servidor e executa diagnóstico completo

$servidor = "186.233.119.88"
$usuario = "root"
$porta = "22"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Stream Manager - Diagnóstico Remoto" -ForegroundColor Cyan
Write-Host "  Servidor: $servidor" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Criar arquivo temporário com o script de diagnóstico
$scriptDiagnostico = @"
#!/bin/bash
echo '======================================'
echo '  Stream Manager - Diagnóstico'
echo '======================================'
echo ''

echo '[1] Status dos Serviços'
echo '-----------------------------------'
echo 'Stream Manager:'
systemctl status stream-manager --no-pager 2>&1 || echo 'Serviço não encontrado'
echo ''
echo 'Nginx:'
systemctl status nginx --no-pager 2>&1 || echo 'Serviço não encontrado'
echo ''

echo '[2] Processos Ativos'
echo '-----------------------------------'
echo 'Python:'
ps aux | grep stream-manager.py | grep -v grep || echo 'Não encontrado'
echo ''
echo 'Nginx:'
ps aux | grep nginx | grep -v grep || echo 'Não encontrado'
echo ''
echo 'Chromium:'
ps aux | grep chromium | grep -v grep || echo 'Não encontrado'
echo ''

echo '[3] Portas em Uso'
echo '-----------------------------------'
netstat -tulpn 2>/dev/null | grep -E ':(8080|1935)' || ss -tulpn | grep -E ':(8080|1935)' || echo 'Nenhuma porta ativa'
echo ''

echo '[4] Logs Stream Manager (últimas 50 linhas)'
echo '-----------------------------------'
journalctl -u stream-manager -n 50 --no-pager 2>/dev/null || echo 'Sem logs'
echo ''

echo '[5] Logs Nginx Error'
echo '-----------------------------------'
tail -30 /var/log/nginx/error.log 2>/dev/null || echo 'Sem logs'
echo ''

echo '[6] Estrutura de Diretórios'
echo '-----------------------------------'
if [ -d '/opt/stream-manager' ]; then
    echo 'Diretório existe:'
    ls -la /opt/stream-manager/ 2>/dev/null
    echo ''
    echo 'Config:'
    ls -la /opt/stream-manager/config/ 2>/dev/null || echo 'Não existe'
    echo ''
    echo 'Scripts:'
    ls -la /opt/stream-manager/scripts/ 2>/dev/null || echo 'Não existe'
    echo ''
    echo 'Web:'
    ls -la /opt/stream-manager/web/ 2>/dev/null || echo 'Não existe'
else
    echo '/opt/stream-manager NÃO EXISTE'
fi
echo ''

echo '[7] Arquivo de Configuração - streams.json'
echo '-----------------------------------'
cat /opt/stream-manager/config/streams.json 2>/dev/null || echo 'Arquivo não existe'
echo ''

echo '[8] Configuração Nginx'
echo '-----------------------------------'
nginx -t 2>&1 || echo 'Nginx não configurado corretamente'
echo ''

echo '[9] Versões'
echo '-----------------------------------'
echo 'Python:' \$(python3 --version 2>&1)
echo 'FFmpeg:' \$(ffmpeg -version 2>&1 | head -1)
echo 'Nginx:' \$(nginx -v 2>&1)
echo ''

echo '[10] Recursos do Sistema'
echo '-----------------------------------'
echo 'Memória:'
free -h
echo ''
echo 'Disco:'
df -h | grep -E '(Filesystem|/$|/opt)'
echo ''

echo '[11] Teste de Conectividade'
echo '-----------------------------------'
echo 'Testando porta 8080:'
curl -s -o /dev/null -w 'HTTP Status: %{http_code}\n' http://localhost:8080/ 2>&1 || echo 'Falhou'
echo ''

echo '======================================'
echo '  Diagnóstico Concluído!'
echo '======================================'
"@

# Salvar script em arquivo temporário
$tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
$scriptDiagnostico | Out-File -FilePath $tempScript -Encoding ASCII -NoNewline

Write-Host "Conectando ao servidor..." -ForegroundColor Yellow
Write-Host ""

# Executar via SSH
# Nota: Você precisará digitar a senha quando solicitado
try {
    $comando = "bash -s"
    Get-Content $tempScript | ssh -p $porta "${usuario}@${servidor}" $comando

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "Diagnóstico concluído com sucesso!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
}
catch {
    Write-Host "Erro ao conectar: $_" -ForegroundColor Red
}
finally {
    # Limpar arquivo temporário
    Remove-Item $tempScript -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Pressione qualquer tecla para sair..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
