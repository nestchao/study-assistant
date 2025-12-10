// --- FILE: study-assistance/src/providers/PaperSolverProvider.ts ---
import * as vscode from 'vscode';
import { BackendClient } from '../services/BackendClient';

export class PaperSolverProvider implements vscode.WebviewViewProvider {
    _view?: vscode.WebviewView;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _backendClient: BackendClient
    ) {}

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
                case 'solvePaper':
                    vscode.commands.executeCommand('studyAssistant.solvePaper');
                    break;
            }
        });
    }

    private _getHtmlForWebview() {
        return `<!DOCTYPE html>
        <html lang="en">
        <head>
            <style>
                body { font-family: var(--vscode-font-family); padding: 10px; color: var(--vscode-foreground); }
                button { 
                    width: 100%; padding: 10px;
                    background: var(--vscode-button-background); 
                    color: var(--vscode-button-foreground); 
                    border: none; cursor: pointer; border-radius: 4px;
                }
                .info { color: var(--vscode-descriptionForeground); font-size: 12px; margin-top: 10px;}
            </style>
        </head>
        <body>
            <h3>📝 Paper Solver</h3>
            <p>Upload exam papers to get AI-generated solutions based on your study materials.</p>
            
            <button onclick="solve()">➕ Solve New Paper</button>
            
            <div class="info">
                Supported formats: PDF, PNG, JPG
            </div>

            <script>
                const vscode = acquireVsCodeApi();
                function solve() { vscode.postMessage({ type: 'solvePaper' }); }
            </script>
        </body>
        </html>`;
    }
}