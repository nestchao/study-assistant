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
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: var(--vscode-font-family);
            background: var(--vscode-editor-background);
            color: var(--vscode-editor-foreground);
            padding: 16px;
            height: 100vh;
            display: flex;
            flex-direction: column;
        }

        .header {
            margin-bottom: 16px;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--vscode-panel-border);
        }

        .header h2 {
            font-size: 16px;
            font-weight: 600;
            color: var(--vscode-foreground);
        }

        .chat-container {
            flex: 1;
            overflow-y: auto;
            margin-bottom: 16px;
            display: flex;
            flex-direction: column;
            gap: 12px;
        }

        .message {
            padding: 12px;
            border-radius: 8px;
            max-width: 90%;
            word-wrap: break-word;
            line-height: 1.5;
        }

        .message.user {
            background: var(--vscode-button-background);
            color: var(--vscode-button-foreground);
            align-self: flex-end;
            margin-left: auto;
        }

        .message.bot {
            background: var(--vscode-editor-inactiveSelectionBackground);
            align-self: flex-start;
        }

        .message pre {
            background: var(--vscode-textCodeBlock-background);
            padding: 8px;
            border-radius: 4px;
            overflow-x: auto;
            margin: 8px 0;
        }

        .message code {
            font-family: var(--vscode-editor-font-family);
            font-size: 13px;
        }

        .input-area {
            display: flex;
            gap: 8px;
        }

        textarea {
            flex: 1;
            background: var(--vscode-input-background);
            color: var(--vscode-input-foreground);
            border: 1px solid var(--vscode-input-border);
            border-radius: 4px;
            padding: 8px;
            resize: vertical;
            min-height: 60px;
            font-family: var(--vscode-font-family);
            font-size: 13px;
        }

        textarea:focus {
            outline: 1px solid var(--vscode-focusBorder);
        }

        button {
            background: var(--vscode-button-background);
            color: var(--vscode-button-foreground);
            border: none;
            border-radius: 4px;
            padding: 8px 16px;
            cursor: pointer;
            font-size: 13px;
            transition: background 0.2s;
        }

        button:hover {
            background: var(--vscode-button-hoverBackground);
        }

        button:active {
            transform: scale(0.98);
        }

        .candidates {
            margin: 12px 0;
            padding: 12px;
            background: var(--vscode-editor-inactiveSelectionBackground);
            border-radius: 6px;
        }

        .candidate-item {
            padding: 8px;
            margin: 4px 0;
            background: var(--vscode-textCodeBlock-background);
            border-radius: 4px;
            cursor: pointer;
            font-size: 12px;
        }

        .candidate-item:hover {
            background: var(--vscode-list-hoverBackground);
        }

        .typing-indicator {
            color: var(--vscode-descriptionForeground);
            font-style: italic;
        }
    </style>
</head>
<body>
    <div class="header">
        <h2>💬 Code Assistant</h2>
    </div>

    <div class="chat-container" id="chat"></div>

    <div class="input-area">
        <textarea 
            id="prompt" 
            placeholder="Ask about your codebase..."
            onkeydown="if(event.key==='Enter' && !event.shiftKey){event.preventDefault();askQuestion();}">
        </textarea>
        <button onclick="askQuestion()">Send</button>
    </div>

    <script>
        const vscode = acquireVsCodeApi();
        const chatContainer = document.getElementById('chat');
        const promptInput = document.getElementById('prompt');

        function addMessage(text, sender = 'bot') {
            const div = document.createElement('div');
            div.className = \`message \${sender}\`;
            
            // Simple markdown-like formatting
            div.innerHTML = formatMessage(text);
            
            chatContainer.appendChild(div);
            chatContainer.scrollTop = chatContainer.scrollHeight;
        }

        function updateLastMessage(text) {
            const messages = chatContainer.querySelectorAll('.message.bot');
            if (messages.length > 0) {
                const lastMessage = messages[messages.length - 1];
                lastMessage.innerHTML = formatMessage(text);
            }
        }

        function formatMessage(text) {
            // Convert markdown code blocks
            text = text.replace(/\`\`\`(\w+)?\\n([\\s\\S]*?)\`\`\`/g, '<pre><code>$2</code></pre>');
            
            // Convert inline code
            text = text.replace(/\`([^\`]+)\`/g, '<code>$1</code>');
            
            // Convert bold
            text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
            
            // Convert line breaks
            text = text.replace(/\\n/g, '<br>');
            
            return text;
        }

        function askQuestion() {
            const text = promptInput.value.trim();
            if (!text) return;

            addMessage(text, 'user');
            promptInput.value = '';

            vscode.postMessage({
                type: 'askCode',
                value: text
            });
        }

        window.addEventListener('message', event => {
            const message = event.data;

            switch (message.type) {
                case 'addResponse':
                    addMessage(message.value);
                    break;
                case 'updateLastResponse':
                    updateLastMessage(message.value);
                    break;
                case 'showCandidates':
                    showCandidates(message.candidates);
                    break;
            }
        });

        function showCandidates(candidates) {
            const div = document.createElement('div');
            div.className = 'candidates';
            div.innerHTML = '<strong>Select relevant files:</strong>';
            
            candidates.forEach(c => {
                const item = document.createElement('div');
                item.className = 'candidate-item';
                item.textContent = \`📄 \${c.file_path} - \${c.name}\`;
                item.onclick = () => selectCandidate(c);
                div.appendChild(item);
            });
            
            chatContainer.appendChild(div);
        }

        function selectCandidate(candidate) {
            addMessage(\`Selected: \${candidate.name}\`, 'user');
            // Send back to extension for processing
        }
    </script>
</body>
</html>`;
    }
}