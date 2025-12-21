import * as vscode from 'vscode';
import { BackendClient } from '../services/BackendClient';

export class StudyHubProvider implements vscode.WebviewViewProvider {
    _view?: vscode.WebviewView;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _backendClient: BackendClient
    ) {}

    // --- FIX: This method is required by extension.ts ---
    public refresh() {
        if (this._view) {
            this._view.webview.postMessage({ type: 'refresh' });
        }
    }

    public resolveWebviewView(webviewView: vscode.WebviewView) {
        this._view = webviewView;
        webviewView.webview.options = { enableScripts: true };
        webviewView.webview.html = this._getHtmlForWebview();

        webviewView.webview.onDidReceiveMessage(async (data) => {
            switch (data.type) {
                case 'getProjects': {
                    try {
                        const projects = await this._backendClient.getStudyProjects();
                        webviewView.webview.postMessage({ type: 'setProjects', value: projects });
                    } catch (e: any) {
                        // console.error(e); 
                        // Fail silently or show generic error to avoid spam
                    }
                    break;
                }
                case 'createProject': {
                    vscode.commands.executeCommand('studyAssistant.createStudyProject');
                    break;
                }
                case 'uploadPDF': {
                    vscode.commands.executeCommand('studyAssistant.uploadPDF');
                    break;
                }
            }
        });
    }

    private _getHtmlForWebview() {
        return `<!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <style>
                body { font-family: var(--vscode-font-family); padding: 10px; color: var(--vscode-foreground); }
                .project-card { 
                    background: var(--vscode-editor-inactiveSelectionBackground); 
                    padding: 10px; margin-bottom: 8px; border-radius: 4px; cursor: pointer;
                }
                .project-card:hover { background: var(--vscode-list-hoverBackground); }
                button { 
                    width: 100%; padding: 8px; margin-bottom: 10px;
                    background: var(--vscode-button-background); 
                    color: var(--vscode-button-foreground); 
                    border: none; cursor: pointer; border-radius: 4px;
                }
                button:hover { background: var(--vscode-button-hoverBackground); }
            </style>
        </head>
        <body>
            <h3>📚 Study Hub</h3>
            <div style="display:flex; gap:5px">
                <button onclick="createProject()">+ New</button>
                <button onclick="uploadPDF()">⬆️ PDF</button>
            </div>
            
            <div id="projects-list" style="margin-top:10px">Loading...</div>

            <script>
                const vscode = acquireVsCodeApi();
                
                function createProject() { vscode.postMessage({ type: 'createProject' }); }
                function uploadPDF() { vscode.postMessage({ type: 'uploadPDF' }); }

                window.addEventListener('message', event => {
                    const message = event.data;
                    if (message.type === 'setProjects') {
                        const list = document.getElementById('projects-list');
                        list.innerHTML = '';
                        if(message.value.length === 0) {
                            list.innerHTML = '<p style="font-size:12px; opacity:0.7">No projects found.</p>';
                            return;
                        }
                        message.value.forEach(p => {
                            const div = document.createElement('div');
                            div.className = 'project-card';
                            div.innerText = '📁 ' + p.name;
                            list.appendChild(div);
                        });
                    }
                    if (message.type === 'refresh') {
                        vscode.postMessage({ type: 'getProjects' });
                    }
                });

                // Initial load
                vscode.postMessage({ type: 'getProjects' });
            </script>
        </body>
        </html>`;
    }
}