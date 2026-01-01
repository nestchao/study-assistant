const UI = {
    pages: document.querySelectorAll('.page'),
    navItems: document.querySelectorAll('.nav-links li'),
    traceList: document.getElementById('trace-list'),
    logList: document.getElementById('log-list'),
    syncTime: document.getElementById('sync-time'),
};

// --- NAVIGATION ---
UI.navItems.forEach(item => {
    item.addEventListener('click', () => {
        const pageId = item.getAttribute('data-page');
        
        UI.navItems.forEach(i => i.classList.remove('active'));
        item.classList.add('active');

        UI.pages.forEach(page => {
            page.classList.toggle('active', page.id === pageId);
        });
    });
});

// --- DATA POLLING ---
async function pollSystemData() {
    try {
        const res = await fetch('/api/admin/telemetry');
        const data = await res.json();
        
        updateOverview(data.metrics);
        renderArchives(data.logs);
        UI.syncTime.innerText = new Date().toLocaleTimeString();
    } catch (e) { console.error("Poll Error", e); }
}

async function pollTraceData() {
    try {
        const res = await fetch('/api/admin/agent_trace');
        const data = await res.json();
        renderTrace(data);
    } catch (e) { console.error("Trace Error", e); }
}

// --- RENDERING ---
function updateOverview(metrics) {
    // Update Gauges
    const updateGauge = (id, val, max) => {
        const circle = document.getElementById(id + '-gauge');
        const text = document.getElementById(id + '-text');
        const percent = Math.min((val / max) * 100, 100);
        const offset = 283 - (283 * percent / 100);
        circle.style.strokeDashoffset = offset;
        text.innerText = val.toFixed(1) + (id === 'cpu' ? '%' : 'MB');
    };

    updateGauge('cpu', metrics.cpu, 100);
    updateGauge('ram', metrics.ram_mb, 1024); // Assume 1GB max for gauge scale

    document.getElementById('vec-val').innerText = metrics.vector_latency.toFixed(1) + 'ms';
    document.getElementById('tps-val').innerText = metrics.tps.toFixed(1) + ' T/s';
}

function renderTrace(traces) {
    UI.traceList.innerHTML = traces.slice().reverse().map(t => {
        // Make details meaningful
        let detail = t.detail;
        if (t.state === "TOOL_CALL") detail = `🔧 Invoking Tool: <strong>${t.detail}</strong>`;
        if (t.state === "REFLECTION") detail = `🧠 AI Analysis: ${t.detail.substring(0, 80)}...`;

        const dockingPoint = t.session_id.includes("D:/") ? t.session_id : "Default";
        return `
            <tr>
                <td>${new Date().toLocaleTimeString()}</td>
                <td><span class="dock-tag">${dockingPoint}</span></td>
                <td>${detail}</td>
                <td style="color: ${t.duration > 1000 ? 'var(--red)' : 'var(--accent)'}">${t.duration.toFixed(0)}ms</td>
                <td style="font-family: monospace; font-size: 10px;">${t.session_id.substring(0, 8)}</td>
            </tr>
        `;
    }).join('');
    document.getElementById('trace-count').innerText = `${traces.length} Events Detected`;
}

function renderArchives(logs) {
    if (!logs || logs.length === 0) {
        UI.logList.innerHTML = '<div class="placeholder">No missions archived yet.</div>';
        return;
    }

    // Sort by timestamp newest first
    const sortedLogs = logs.sort((a, b) => b.timestamp - a.timestamp);

    UI.logList.innerHTML = sortedLogs.map(log => `
        <div class="log-item" onclick='inspectLog(${JSON.stringify(log).replace(/'/g, "&apos;")})'>
            <div class="log-meta">
                <span>${new Date(log.timestamp * 1000).toLocaleTimeString()}</span>
                <span class="token-badge">${log.total_tokens || 0} Tkn</span>
            </div>
            <div class="log-query">${escapeHtml(log.user_query.substring(0, 40))}...</div>
        </div>
    `).join('');
}

window.inspectLog = (log) => {
    const content = document.getElementById('inspector-content');
    const placeholder = document.getElementById('inspector-default');
    
    // 🛡️ Safety Guard: Prevent division by zero
    const durationSec = log.duration_ms / 1000 || 1;
    const fuelEfficiency = (log.total_tokens / durationSec).toFixed(0);
    
    placeholder.classList.add('hidden');
    content.classList.remove('hidden');

    content.innerHTML = `
        <div class="inspector-header">
            <h2 style="margin:0">Mission Telemetry</h2>
            <div class="token-stats">
                <span class="stat-pill">Input (Prompt): ${log.prompt_tokens}</span>
                <span class="stat-pill">Output (Reply): ${log.completion_tokens}</span>
                <span class="stat-pill total">Total Fuel: ${log.total_tokens} Tkn</span>
            </div>
            <div class="burn-rate-label">
                <i class="fas fa-fire"></i> Burn Rate: ${fuelEfficiency} tokens/sec
            </div>
        </div>

        <div class="mission-report">
            <h3>${log.ai_response ? '✅ Mission Resolved' : '🔍 Retrieval Query'}</h3>
            
            <div class="terminal-box">
                <span class="line-header">> USER_INTENT:</span>
                <p class="raw-text">${escapeHtml(log.user_query)}</p>
                
                <span class="line-header">> AI_SOLUTION:</span>
                <div class="raw-text code-block">${escapeHtml(log.ai_response) || 'Processing...'}</div>
            </div>
        </div>

        <div class="meta-footer">
            <strong>Engine Latency:</strong> ${log.duration_ms.toFixed(0)}ms | 
            <strong>Target Project:</strong> ${log.project_id}
        </div>
    `;
};

function escapeHtml(text) {
    if (!text) return "";
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}


// Stress Test
window.triggerStressTest = async () => {
    const res = await fetch('/api/admin/stress_test', { method: 'POST' });
    alert("Stress sequence initiated.");
}

// Intervals
setInterval(pollSystemData, 1000);
setInterval(pollTraceData, 1000);
pollSystemData();