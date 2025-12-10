import * as vscode from 'vscode';
import { BackendClient } from '../services/BackendClient';

export class CodeChatProvider implements vscode.WebviewViewProvider {
    _view?: vscode.WebviewView;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _backendClient: BackendClient,
        private readonly _projectId: string | null
    ) {}

    public resolveWebviewView(webviewView: vscode.WebviewView) {
        this._view = webviewView;
        
        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [this._extensionUri]
        };

        webviewView.webview.html = this._getHtmlForWebview(webviewView.webview);

        webviewView.webview.onDidReceiveMessage(async (data) => {
            switch (data.type) {
                case 'askCode': {
                    if (!data.value || !this._projectId) {
                        webviewView.webview.postMessage({
                            type: 'addResponse',
                            value: this._projectId 
                                ? 'Please enter a question' 
                                : 'Please register your project first (Cmd+Shift+P → "Register Project")'
                        });
                        return;
                    }

                    // Show thinking message
                    webviewView.webview.postMessage({
                        type: 'addResponse',
                        value: '🤔 Analyzing your codebase...'
                    });

                    try {
                        // Get suggestion from C++ backend
                        const response = await this._backendClient.getCodeSuggestion(
                            this._projectId,
                            data.value
                        );

                        webviewView.webview.postMessage({
                            type: 'updateLastResponse',
                            value: response
                        });
                    } catch (error: any) {
                        webviewView.webview.postMessage({
                            type: 'updateLastResponse',
                            value: `❌ Error: ${error.message}`
                        });
                    }
                    break;
                }

                case 'selectContext': {
                    // Get context candidates for user to select
                    if (!this._projectId) return;

                    try {
                        const candidates = await this._backendClient.getContextCandidates(
                            this._projectId,
                            data.value
                        );

                        webviewView.webview.postMessage({
                            type: 'showCandidates',
                            candidates: candidates
                        });
                    } catch (error: any) {
                        webviewView.webview.postMessage({
                            type: 'addResponse',
                            value: `Error getting candidates: ${error.message}`
                        });
                    }
                    break;
                }

                case 'insertCode': {
                    // Insert code at cursor position
                    const editor = vscode.window.activeTextEditor;
                    if (editor && data.value) {
                        editor.edit(editBuilder => {
                            editBuilder.insert(editor.selection.active, data.value);
                        });
                    }
                    break;
                }
            }
        });
    }

    private _getHtmlForWebview(webview: vscode.Webview) {
        return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Code Assistant</title>
    <style>
        body { font-family: var(--vscode-font-family); background: var(--vscode-editor-background); color: var(--vscode-editor-foreground); padding: 16px; height: 100vh; display: flex; flex-direction: column; }
        .chat-container { flex: 1; overflow-y: auto; margin-bottom: 16px; display: flex; flex-direction: column; gap: 12px; }
        .message { padding: 12px; border-radius: 8px; max-width: 90%; word-wrap: break-word; }
        .user { background: var(--vscode-button-background); color: var(--vscode-button-foreground); align-self: flex-end; }
        .bot { background: var(--vscode-editor-inactiveSelectionBackground); align-self: flex-start; }
        .input-area { display: flex; gap: 8px; }
        textarea { flex: 1; background: var(--vscode-input-background); color: var(--vscode-input-foreground); border: 1px solid var(--vscode-input-border); border-radius: 4px; padding: 8px; resize: vertical; min-height: 40px; font-family: inherit; }
        button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; border-radius: 4px; padding: 0 16px; cursor: pointer; }
        button:hover { background: var(--vscode-button-hoverBackground); }
    </style>
</head>
<body>
    <div class="chat-container" id="chat"></div>

    <div class="input-area">
        <textarea id="prompt" placeholder="Ask about your code..."></textarea>
        <button id="sendBtn">Send</button>
    </div>

    <script>
        const vscode = acquireVsCodeApi();
        const chatContainer = document.getElementById('chat');
        const promptInput = document.getElementById('prompt');
        const sendBtn = document.getElementById('sendBtn');

        function addMessage(text, sender = 'bot') {
            const div = document.createElement('div');
            div.className = 'message ' + sender;
            div.innerHTML = text.replace(/\\n/g, '<br>'); // Simple line break handling
            chatContainer.appendChild(div);
            chatContainer.scrollTop = chatContainer.scrollHeight;
        }

        function sendMessage() {
            const text = promptInput.value.trim();
            if (!text) return;

            addMessage(text, 'user');
            promptInput.value = ''; // Clear input

            vscode.postMessage({
                type: 'askCode',
                value: text
            });
        }

        // Event Listeners
        sendBtn.addEventListener('click', sendMessage);
        
        promptInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                sendMessage();
            }
        });

        // Handle messages from Extension
        window.addEventListener('message', event => {
            const message = event.data;
            if (message.type === 'addResponse' || message.type === 'updateLastResponse') {
                addMessage(message.value);
            }
        });
    </script>
</body>
</html>`;
    }
}