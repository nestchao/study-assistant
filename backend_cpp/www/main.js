const UI = {
    logList: document.getElementById('log-list'),
    kpiLatency: document.getElementById('kpi-latency'),
    kpiTps: document.getElementById('kpi-tps'),
    
    // Inspector Fields
    inspId: document.getElementById('insp-id'),
    inspType: document.getElementById('insp-type'),
    inspTime: document.getElementById('insp-time'),
    inspLatency: document.getElementById('insp-latency'),
    inspTokens: document.getElementById('insp-tokens'),
    inspFullPrompt: document.getElementById('insp-full-prompt'),
    inspResponse: document.getElementById('insp-response'),
    inspUserInput: document.getElementById('insp-user-input'),
    inspVector: document.getElementById('insp-vector')
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
async function pollTelemetry() {
    try {
        const res = await fetch('/api/admin/telemetry');
        const data = await res.json();
        
        // Update KPIs
        UI.kpiLatency.innerText = data.metrics.llm_latency.toFixed(0) + 'ms';
        UI.kpiTps.innerText = data.metrics.tps.toFixed(1);

        renderLogs(data.logs);
    } catch(e) { console.error(e); }
}

let lastLogCount = 0;

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

function renderLogs(logs) {
    if (logs.length === lastLogCount) return;
    lastLogCount = logs.length;

    UI.logList.innerHTML = logs.slice().reverse().map((log, index) => {
        const time = new Date(log.timestamp * 1000).toLocaleTimeString();
        const typeClass = log.type === 'GHOST' ? 'type-GHOST' : 'type-AGENT';
        
        return `
            <div class="log-item" onclick='inspect(${JSON.stringify(log).replace(/'/g, "&apos;")})'>
                <div class="log-top">
                    <span class="type-tag ${typeClass}">${log.type || 'AGENT'}</span>
                    <span style="color:#666">${time}</span>
                </div>
                <div style="font-size:12px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis">
                    ${log.user_query}
                </div>
            </div>
        `;
    }).join('');
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

window.inspect = (log) => {
    // Header
    UI.inspId.innerText = log.project_id || "UNKNOWN";
    UI.inspType.className = `badge type-${log.type || 'AGENT'}`;
    UI.inspType.innerText = log.type || 'AGENT';
    
    UI.inspTime.innerText = new Date(log.timestamp * 1000).toLocaleTimeString();
    UI.inspLatency.innerText = log.duration_ms.toFixed(0) + "ms";
    UI.inspTokens.innerText = `${log.total_tokens} (In: ${log.prompt_tokens} / Out: ${log.completion_tokens})`;

    // Content
    UI.inspUserInput.innerText = log.user_query;
    UI.inspFullPrompt.innerText = log.full_prompt || "(No context captured)";
    UI.inspResponse.innerText = log.ai_response;

    // Vector Visualization
    if (log.vector_snapshot && log.vector_snapshot.length > 0) {
        UI.inspVector.innerHTML = log.vector_snapshot.map(val => {
            // Map float -0.5 to 0.5 to a color intensity
            const intensity = Math.min(255, Math.max(0, Math.floor((val + 0.1) * 1000)));
            const color = `rgb(0, ${intensity}, ${255 - intensity})`;
            return `<div class="vec-cell" style="background:${color}" title="${val.toFixed(4)}"></div>`;
        }).join('');
        UI.inspVector.innerHTML += `<div class="vec-val" style="margin-left:10px">${log.vector_snapshot.length} dims shown</div>`;
    } else {
        UI.inspVector.innerHTML = '<span style="color:#555">No vector data available</span>';
    }
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
setInterval(pollTelemetry, 1000);
pollTelemetry();