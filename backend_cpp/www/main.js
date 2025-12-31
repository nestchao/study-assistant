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

        return `
            <tr>
                <td>${new Date().toLocaleTimeString()}</td>
                <td><span class="phase-pill">${t.state}</span></td>
                <td>${detail}</td>
                <td style="color: ${t.duration > 1000 ? 'var(--red)' : 'var(--accent)'}">${t.duration.toFixed(0)}ms</td>
                <td style="font-family: monospace; font-size: 10px;">${t.session_id.substring(0, 8)}</td>
            </tr>
        `;
    }).join('');
    document.getElementById('trace-count').innerText = `${traces.length} Events Detected`;
}

function renderArchives(logs) {
    if (UI.logList.children.length === logs.length) return;
    
    UI.logList.innerHTML = logs.map(log => `
        <div class="log-item" onclick='inspectLog(${JSON.stringify(log).replace(/'/g, "&apos;")})'>
            <div style="font-size: 10px; color: var(--accent); margin-bottom: 5px;">
                ${new Date(log.timestamp * 1000).toLocaleString()}
            </div>
            <div style="font-weight: bold; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                ${log.user_query}
            </div>
        </div>
    `).join('');
}

window.inspectLog = (log) => {
    const content = document.getElementById('inspector-content');
    const placeholder = document.getElementById('inspector-default');
    
    placeholder.classList.add('hidden');
    content.classList.remove('hidden');

    content.innerHTML = `
        <h2 style="margin-top:0">${log.ai_response ? '✅ Mission Resolved' : '🔍 Retrieval Query'}</h2>
        <div style="background: #000; padding: 15px; border-radius: 8px; font-family: monospace; font-size: 12px; max-height: 400px; overflow-y: auto;">
            <span style="color: var(--green)">> USER_INTENT:</span> ${log.user_query}<br><br>
            <span style="color: var(--accent)">> AI_SOLUTION:</span><br>
            ${log.ai_response || 'Pending...'}
        </div>
        <div style="margin-top: 15px; font-size: 12px;">
            <strong>Latency:</strong> ${log.duration_ms.toFixed(0)}ms | 
            <strong>Project:</strong> ${log.project_id}
        </div>
    `;
};

// Stress Test
window.triggerStressTest = async () => {
    const res = await fetch('/api/admin/stress_test', { method: 'POST' });
    alert("Stress sequence initiated.");
}

// Intervals
setInterval(pollSystemData, 1000);
setInterval(pollTraceData, 1000);
pollSystemData();