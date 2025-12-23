import * as vscode from "vscode";
import { LocalBackend } from "../localBackend";

export class SidebarProvider implements vscode.WebviewViewProvider {
  _view?: vscode.WebviewView;

  constructor(
    private readonly _extensionUri: vscode.Uri,
    private readonly _backend: LocalBackend 
  ) {}

  public resolveWebviewView(webviewView: vscode.WebviewView) {
    this._view = webviewView;
    webviewView.webview.options = { enableScripts: true, localResourceRoots: [this._extensionUri] };
    webviewView.webview.html = this._getHtmlForWebview(webviewView.webview);

    webviewView.webview.onDidReceiveMessage(async (data) => {
      switch (data.type) {
        case "askAI": {
          if (!data.value) return;
          
          // 1. Show user "Thinking"
          webviewView.webview.postMessage({ type: "addResponse", value: "Thinking... (Searching files)" });

          try {
            // 2. Retrieve Context (RAG)
            const context = await this._backend.retrieveContext(data.value);
            
            // 3. Ask Gemini
            const response = await this._backend.chat(data.value, context);

            // 4. Send answer back to UI
            webviewView.webview.postMessage({ type: "addResponse", value: response });
          } catch (e: any) {
            webviewView.webview.postMessage({ type: "addResponse", value: `Error: ${e.message}` });
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
        <style>
          body { font-family: var(--vscode-font-family); padding: 10px; color: var(--vscode-foreground); }
          textarea { width: 100%; box-sizing: border-box; resize: vertical; min-height: 60px; background: var(--vscode-input-background); color: var(--vscode-input-foreground); border: 1px solid var(--vscode-input-border); margin-bottom: 10px; }
          button { width: 100%; padding: 8px; background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; cursor: pointer; }
          button:hover { background: var(--vscode-button-hoverBackground); }
          .chat { margin-top: 20px; display: flex; flex-direction: column; gap: 10px; }
          .message { padding: 8px; border-radius: 4px; font-size: 13px; line-height: 1.4; white-space: pre-wrap; }
          .user { align-self: flex-end; background: var(--vscode-editor-inactiveSelectionBackground); }
          .bot { align-self: flex-start; background: var(--vscode-textBlockQuote-background); }
        </style>
      </head>
      <body>
        <h3>CodeMinds Local</h3>
        <textarea id="prompt" placeholder="Ask about your code..."></textarea>
        <button id="askBtn">Ask Gemini</button>
        <div class="chat" id="chatbox"></div>

        <script>
          const vscode = acquireVsCodeApi();
          const chatbox = document.getElementById('chatbox');
          
          document.getElementById('askBtn').addEventListener('click', () => {
            const text = document.getElementById('prompt').value;
            if(text) {
                const div = document.createElement('div');
                div.className = 'message user';
                div.innerText = text;
                chatbox.appendChild(div);
                
                vscode.postMessage({ type: 'askAI', value: text });
                document.getElementById('prompt').value = '';
            }
          });

          window.addEventListener('message', event => {
            const message = event.data;
            if (message.type === 'addResponse') {
                // If the previous message was "Thinking...", remove it
                const last = chatbox.lastElementChild;
                if (last && last.innerText.includes("Thinking...")) {
                    chatbox.removeChild(last);
                }

                const div = document.createElement('div');
                div.className = 'message bot';
                div.innerText = message.value; 
                chatbox.appendChild(div);
            }
          });
        </script>
      </body>
      </html>`;
  }
}