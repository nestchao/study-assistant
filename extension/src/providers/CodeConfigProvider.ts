import * as vscode from 'vscode';

export class CodeConfigProvider implements vscode.WebviewViewProvider {
    _view?: vscode.WebviewView;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _backendClient: any
    ) {}

    private async syncFilterManifest(projectId: string) {
        const config = vscode.workspace.getConfiguration('studyAssistant');
        
        const payload = {
            project_id: projectId,
            allowed_extensions: config.get<string>('allowedExtensions')?.split(',').map(s => s.trim()) || [],
            ignored_paths: config.get<string>('ignoredPaths')?.split(',').map(s => s.trim()) || [],
            included_paths: config.get<string>('includedPaths')?.split(',').map(s => s.trim()) || []
        };

        try {
            await this._backendClient.post('/sync/update_manifest', payload);
            vscode.window.showInformationMessage("🛰️ AI Flight Manifest Synchronized.");
        } catch (e) {
            console.error("Manifest sync failed", e);
        }
    }

    public resolveWebviewView(webviewView: vscode.WebviewView) {
        this._view = webviewView;
        webviewView.webview.options = { enableScripts: true };
        this.updateView();

        webviewView.webview.onDidReceiveMessage(async (data) => {
            switch (data.type) {
                case 'saveAndSync': {
                    try {
                        // 1. Commit to VS Code Settings
                        await this.saveSettings(data.extensions, data.ignored, data.included);
                        
                        // 2. Trigger Project Registration (Atomic)
                        await vscode.commands.executeCommand('studyAssistant.registerProject', { silent: true });
                        
                        // 3. Update the UI
                        vscode.window.showInformationMessage("✅ Configuration committed to Engine.");
                    } catch (e: any) {
                        vscode.window.showErrorMessage(`Config Sync Failed: ${e.message}`);
                    }
                    break;
                }
                case 'syncOnly': {
                    vscode.commands.executeCommand('studyAssistant.syncProject');
                    break;
                }
            }
        });
    }

    private updateView() {
        if (this._view) {
            const config = vscode.workspace.getConfiguration('studyAssistant');
            const ext = config.get('allowedExtensions', 'py,ts,js,cpp,h,java');
            const ign = config.get('ignoredPaths', 'node_modules, .git, build, dist');
            const inc = config.get('includedPaths', '');
            
            this._view.webview.html = this._getHtmlForWebview(ext, ign, inc);
        }
    }

    private async saveSettings(ext: string, ign: string, inc: string) {
        const config = vscode.workspace.getConfiguration('studyAssistant');
        
        // Determine target: Workspace if folder open, otherwise Global
        const target = vscode.workspace.workspaceFolders 
            ? vscode.ConfigurationTarget.Workspace 
            : vscode.ConfigurationTarget.Global;

        try {
            await config.update('allowedExtensions', ext, target);
            await config.update('ignoredPaths', ign, target);
            await config.update('includedPaths', inc, target);
            vscode.window.showInformationMessage('Configuration saved!');
        } catch (error) {
            console.error("Failed to save settings:", error);
            throw error;
        }
    }

    private _getHtmlForWebview(ext: string, ign: string, inc: string) {
        // Escape special chars to prevent HTML breaking
        const escapeHtml = (unsafe: string) => {
            return unsafe
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&#039;");
        };

        const safeExt = escapeHtml(ext);
        const safeIgn = escapeHtml(ign);
        const safeInc = escapeHtml(inc);

        return `<!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <style>
                body { font-family: var(--vscode-font-family); padding: 15px; color: var(--vscode-foreground); }
                .card { 
                    background: var(--vscode-editor-inactiveSelectionBackground); 
                    border: 1px solid var(--vscode-widget-border);
                    padding: 12px; margin-bottom: 15px; border-radius: 6px; 
                }
                label { display: block; margin-bottom: 4px; font-weight: bold; font-size: 11px; text-transform: uppercase; color: var(--vscode-descriptionForeground); }
                input, textarea { 
                    width: 100%; box-sizing: border-box; padding: 8px; margin-bottom: 12px;
                    background: var(--vscode-input-background); 
                    color: var(--vscode-input-foreground); 
                    border: 1px solid var(--vscode-input-border);
                    border-radius: 4px;
                    font-family: monospace;
                    font-size: 12px;
                }
                button { 
                    width: 100%; padding: 10px; margin-bottom: 10px;
                    background: var(--vscode-button-background); 
                    color: var(--vscode-button-foreground); 
                    border: none; cursor: pointer; border-radius: 4px;
                    font-weight: 600;
                }
                button:hover { background: var(--vscode-button-hoverBackground); }
                .secondary-btn {
                    background: var(--vscode-button-secondaryBackground);
                    color: var(--vscode-button-secondaryForeground);
                }
                .secondary-btn:hover { background: var(--vscode-button-secondaryHoverBackground); }
            </style>
        </head>
        <body>
            <h3 style="margin-top:0">⚙️ Sync Config</h3>
            
            <div class="card">
                <label>File Extensions</label>
                <input type="text" id="extensions" value="${safeExt}" />
                
                <label>Ignored Folders</label>
                <textarea id="ignored" rows="3">${safeIgn}</textarea>
                
                <label>Force Include (Exceptions)</label>
                <textarea id="included" rows="2" placeholder="e.g. node_modules/my-lib">${safeInc}</textarea>
            </div>

            <button onclick="saveAndSync()">💾 Save & Register</button>
            <button class="secondary-btn" onclick="syncOnly()">🔄 Sync Only</button>

            <script>
                const vscode = acquireVsCodeApi();
                
                function saveAndSync() { 
                    vscode.postMessage({ 
                        type: 'saveAndSync',
                        extensions: document.getElementById('extensions').value,
                        ignored: document.getElementById('ignored').value,
                        included: document.getElementById('included').value
                    }); 
                }

                function syncOnly() {
                    vscode.postMessage({ type: 'syncOnly' });
                }
            </script>
        </body>
        </html>`;
    }
}