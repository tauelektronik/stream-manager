/**
 * Stream Manager - Frontend Application
 */

// Estado global
const state = {
    streams: {},
    socket: null,
    editingStreamId: null,
    serverHost: window.location.hostname
};

// Elementos DOM
const elements = {
    streamsContainer: document.getElementById('streams-container'),
    emptyState: document.getElementById('empty-state'),
    btnAddStream: document.getElementById('btn-add-stream'),
    btnStartAll: document.getElementById('btn-start-all'),
    btnStopAll: document.getElementById('btn-stop-all'),
    btnRefresh: document.getElementById('btn-refresh'),
    modalStream: document.getElementById('modal-stream'),
    modalStreamTitle: document.getElementById('modal-stream-title'),
    formStream: document.getElementById('form-stream'),
    btnCloseModal: document.getElementById('btn-close-modal'),
    btnCancelStream: document.getElementById('btn-cancel-stream'),
    modalLinks: document.getElementById('modal-links'),
    btnCloseLinks: document.getElementById('btn-close-links'),
    modalLogs: document.getElementById('modal-logs'),
    btnCloseLogs: document.getElementById('btn-close-logs'),
    logsContent: document.getElementById('logs-content'),
    logsStreamName: document.getElementById('logs-stream-name'),
    cpuStat: document.getElementById('cpu-stat'),
    ramStat: document.getElementById('ram-stat'),
    streamsStat: document.getElementById('streams-stat'),
    toastContainer: document.getElementById('toast-container')
};

// Inicialização
document.addEventListener('DOMContentLoaded', () => {
    initSocket();
    initEventListeners();
    loadStreams();
    startStatsUpdater();
});

// WebSocket
function initSocket() {
    state.socket = io({
        transports: ['websocket', 'polling']
    });

    state.socket.on('connect', () => {
        console.log('WebSocket conectado');
    });

    state.socket.on('disconnect', () => {
        console.log('WebSocket desconectado');
    });

    state.socket.on('status_update', (data) => {
        state.streams = data;
        renderStreams();
        updateStreamsStat();
    });
}

// Event Listeners
function initEventListeners() {
    // Botões da toolbar
    elements.btnAddStream.addEventListener('click', () => openStreamModal());
    elements.btnStartAll.addEventListener('click', startAllStreams);
    elements.btnStopAll.addEventListener('click', stopAllStreams);
    elements.btnRefresh.addEventListener('click', loadStreams);

    // Modal de stream
    elements.btnCloseModal.addEventListener('click', closeStreamModal);
    elements.btnCancelStream.addEventListener('click', closeStreamModal);
    elements.formStream.addEventListener('submit', handleStreamSubmit);
    elements.modalStream.querySelector('.modal-overlay').addEventListener('click', closeStreamModal);

    // Modal de links
    elements.btnCloseLinks.addEventListener('click', closeLinksModal);
    elements.modalLinks.querySelector('.modal-overlay').addEventListener('click', closeLinksModal);

    // Modal de logs
    elements.btnCloseLogs.addEventListener('click', closeLogsModal);
    elements.modalLogs.querySelector('.modal-overlay').addEventListener('click', closeLogsModal);

    // Tecla ESC para fechar modais
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closeStreamModal();
            closeLinksModal();
            closeLogsModal();
        }
    });
}

// API Calls
async function apiCall(endpoint, method = 'GET', data = null) {
    const options = {
        method,
        headers: {
            'Content-Type': 'application/json'
        }
    };

    if (data) {
        options.body = JSON.stringify(data);
    }

    try {
        const response = await fetch(`/api${endpoint}`, options);
        const result = await response.json();

        if (!response.ok) {
            throw new Error(result.error || 'Erro na requisição');
        }

        return result;
    } catch (error) {
        console.error('API Error:', error);
        throw error;
    }
}

async function loadStreams() {
    try {
        const streams = await apiCall('/streams');
        state.streams = streams;
        renderStreams();
        updateStreamsStat();
    } catch (error) {
        showToast('Erro ao carregar streams', 'error');
    }
}

async function loadSystemStats() {
    try {
        const stats = await apiCall('/system/stats');
        elements.cpuStat.textContent = `${stats.cpu_percent.toFixed(1)}%`;
        elements.ramStat.textContent = `${stats.memory_percent.toFixed(1)}%`;
    } catch (error) {
        console.error('Erro ao carregar stats:', error);
    }
}

function startStatsUpdater() {
    loadSystemStats();
    setInterval(loadSystemStats, 5000);
}

function updateStreamsStat() {
    const total = Object.keys(state.streams).length;
    const active = Object.values(state.streams).filter(s => s.running).length;
    elements.streamsStat.textContent = `${active}/${total}`;
}

// Render
function renderStreams() {
    const streams = Object.values(state.streams);

    if (streams.length === 0) {
        elements.emptyState.classList.remove('hidden');
        // Remover cards existentes
        const cards = elements.streamsContainer.querySelectorAll('.stream-card');
        cards.forEach(card => card.remove());
        return;
    }

    elements.emptyState.classList.add('hidden');

    // Remover cards antigos
    const existingCards = elements.streamsContainer.querySelectorAll('.stream-card');
    existingCards.forEach(card => card.remove());

    // Criar novos cards
    streams.forEach(stream => {
        const card = createStreamCard(stream);
        elements.streamsContainer.appendChild(card);
    });
}

function createStreamCard(stream) {
    const card = document.createElement('div');
    card.className = `stream-card ${stream.state || 'stopped'}`;
    card.dataset.id = stream.id;

    const statusClass = stream.running ? 'running' : stream.state === 'starting' ? 'starting' : 'stopped';
    const statusText = stream.running ? 'Rodando' : stream.state === 'starting' ? 'Iniciando...' : 'Parado';

    card.innerHTML = `
        <div class="stream-header">
            <div class="stream-title">
                <span class="stream-name">${escapeHtml(stream.name)}</span>
                <span class="stream-id">${escapeHtml(stream.id)}</span>
            </div>
            <div class="stream-status ${statusClass}">
                <span class="status-dot"></span>
                ${statusText}
            </div>
        </div>
        <div class="stream-body">
            <div class="stream-url">${escapeHtml(stream.url)}</div>
            <div class="stream-meta">
                <span>📐 ${stream.resolution}</span>
                <span>${stream.audio ? '🔊 Áudio' : '🔇 Sem áudio'}</span>
                ${stream.vnc_active ? '<span class="vnc-badge">🖥️ VNC ativo</span>' : ''}
            </div>
            <div class="stream-actions">
                ${stream.running ? `
                    <button class="btn btn-danger btn-sm" onclick="stopStream('${stream.id}')">
                        Parar
                    </button>
                    <button class="btn btn-secondary btn-sm" onclick="showLinks('${stream.id}')">
                        Links
                    </button>
                    <button class="btn btn-secondary btn-sm" onclick="toggleVNC('${stream.id}')">
                        ${stream.vnc_active ? 'Fechar VNC' : 'Abrir VNC'}
                    </button>
                ` : `
                    <button class="btn btn-success btn-sm" onclick="startStream('${stream.id}')">
                        Iniciar
                    </button>
                `}
                <button class="btn btn-icon btn-sm" onclick="openStreamModal('${stream.id}')" title="Editar">
                    ✏️
                </button>
                <button class="btn btn-icon btn-sm" onclick="showLogs('${stream.id}')" title="Logs">
                    📋
                </button>
                <button class="btn btn-icon btn-sm" onclick="deleteStream('${stream.id}')" title="Excluir">
                    🗑️
                </button>
            </div>
        </div>
    `;

    return card;
}

// Stream Actions
async function startStream(streamId) {
    try {
        await apiCall(`/streams/${streamId}/start`, 'POST');
        showToast(`Stream "${streamId}" iniciando...`, 'success');
    } catch (error) {
        showToast(`Erro ao iniciar stream: ${error.message}`, 'error');
    }
}

async function stopStream(streamId) {
    try {
        await apiCall(`/streams/${streamId}/stop`, 'POST');
        showToast(`Stream "${streamId}" parado`, 'success');
    } catch (error) {
        showToast(`Erro ao parar stream: ${error.message}`, 'error');
    }
}

async function startAllStreams() {
    const streams = Object.values(state.streams).filter(s => !s.running);
    for (const stream of streams) {
        await startStream(stream.id);
        await new Promise(resolve => setTimeout(resolve, 2000)); // Delay entre starts
    }
}

async function stopAllStreams() {
    const streams = Object.values(state.streams).filter(s => s.running);
    for (const stream of streams) {
        await stopStream(stream.id);
    }
}

async function deleteStream(streamId) {
    if (!confirm(`Tem certeza que deseja excluir o stream "${streamId}"?`)) {
        return;
    }

    try {
        await apiCall(`/streams/${streamId}`, 'DELETE');
        showToast(`Stream "${streamId}" excluído`, 'success');
    } catch (error) {
        showToast(`Erro ao excluir stream: ${error.message}`, 'error');
    }
}

async function toggleVNC(streamId) {
    const stream = state.streams[streamId];
    const endpoint = stream.vnc_active ? 'stop' : 'start';

    try {
        const result = await apiCall(`/streams/${streamId}/vnc/${endpoint}`, 'POST');
        if (result.port) {
            showToast(`VNC disponível: ${state.serverHost}:${result.port}`, 'success');
        } else {
            showToast('VNC fechado', 'success');
        }
    } catch (error) {
        showToast(`Erro com VNC: ${error.message}`, 'error');
    }
}

// Modal de Stream
function openStreamModal(streamId = null) {
    state.editingStreamId = streamId;
    const form = elements.formStream;

    if (streamId && state.streams[streamId]) {
        // Editar stream existente
        const stream = state.streams[streamId];
        elements.modalStreamTitle.textContent = 'Editar Stream';
        form.elements['id'].value = stream.id;
        form.elements['id'].disabled = true;
        form.elements['name'].value = stream.name;
        form.elements['url'].value = stream.url;
        form.elements['resolution'].value = stream.resolution;
        form.elements['profile'].value = stream.profile || '';
        form.elements['audio'].checked = stream.audio;
    } else {
        // Novo stream
        elements.modalStreamTitle.textContent = 'Novo Stream';
        form.reset();
        form.elements['id'].disabled = false;
    }

    elements.modalStream.classList.add('active');
}

function closeStreamModal() {
    elements.modalStream.classList.remove('active');
    state.editingStreamId = null;
}

async function handleStreamSubmit(e) {
    e.preventDefault();

    const form = e.target;
    const data = {
        id: form.elements['id'].value,
        name: form.elements['name'].value,
        url: form.elements['url'].value,
        resolution: form.elements['resolution'].value,
        profile: form.elements['profile'].value || form.elements['id'].value,
        audio: form.elements['audio'].checked
    };

    try {
        if (state.editingStreamId) {
            await apiCall(`/streams/${state.editingStreamId}`, 'PUT', data);
            showToast('Stream atualizado', 'success');
        } else {
            await apiCall('/streams', 'POST', data);
            showToast('Stream criado', 'success');
        }
        closeStreamModal();
    } catch (error) {
        showToast(`Erro: ${error.message}`, 'error');
    }
}

// Modal de Links
function showLinks(streamId) {
    const stream = state.streams[streamId];
    if (!stream) return;

    const port = window.location.port || '8080';
    const host = state.serverHost;

    document.getElementById('link-hls').value = `http://${host}:${port}/hls/${streamId}/index.m3u8`;
    document.getElementById('link-rtmp').value = `rtmp://${host}:1935/live/${streamId}`;
    document.getElementById('link-vlc').value = `vlc http://${host}:${port}/hls/${streamId}/index.m3u8`;

    elements.modalLinks.classList.add('active');
}

function closeLinksModal() {
    elements.modalLinks.classList.remove('active');
}

// Modal de Logs
async function showLogs(streamId) {
    const stream = state.streams[streamId];
    if (!stream) return;

    elements.logsStreamName.textContent = stream.name;

    try {
        const result = await apiCall(`/logs/${streamId}`);
        elements.logsContent.textContent = result.logs || 'Nenhum log disponível';
    } catch (error) {
        elements.logsContent.textContent = 'Erro ao carregar logs';
    }

    elements.modalLogs.classList.add('active');
}

function closeLogsModal() {
    elements.modalLogs.classList.remove('active');
}

// Utilitários
function copyLink(inputId) {
    const input = document.getElementById(inputId);
    input.select();
    document.execCommand('copy');
    showToast('Link copiado!', 'success');
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.textContent = message;

    elements.toastContainer.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// Expor funções globais para onclick
window.startStream = startStream;
window.stopStream = stopStream;
window.deleteStream = deleteStream;
window.toggleVNC = toggleVNC;
window.showLinks = showLinks;
window.showLogs = showLogs;
window.openStreamModal = openStreamModal;
window.copyLink = copyLink;
