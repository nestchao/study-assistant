import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';

export class CodeChatProvider implements vscode.WebviewViewProvider {
    private _view?: vscode.WebviewView;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _backendClient: any,
        private readonly _projectId: string | null
    ) {}

    public resolveWebviewView(
        webviewView: vscode.WebviewView,
        context: vscode.WebviewViewResolveContext,
        _token: vscode.CancellationToken,
    ) {
        this._view = webviewView;

        webviewView.webview.options = {
            enableScripts: true,
            // 🚀 CRITICAL: Allow access to the media folder
            localResourceRoots: [
                vscode.Uri.joinPath(this._extensionUri, 'media'),
                vscode.Uri.joinPath(this._extensionUri, 'node_modules')
            ]
        };

        webviewView.webview.html = this._getHtmlForWebview(webviewView.webview);

        webviewView.webview.onDidReceiveMessage(async (data) => {
            switch (data.type) {
                case 'askCode': {
                    if (!data.value || !this._projectId) {
                        this._view?.webview.postMessage({
                            type: 'addResponse',
                            value: '⚠️ Project not registered. Please use the Config panel first.'
                        });
                        return;
                    }

                    // 🚀 SPACE-X FEEDBACK: Initial Thinking state
                    this._view?.webview.postMessage({ type: 'addResponse', value: '🤔 Analyzing...' });

                    try {
                        const activeEditor = vscode.window.activeTextEditor;
                        const activeContext = activeEditor ? {
                            filePath: vscode.workspace.asRelativePath(activeEditor.document.uri),
                            content: activeEditor.document.getText(),
                            selection: activeEditor.document.getText(activeEditor.selection)
                        } : { filePath: "None", content: "", selection: "" };

                        // Call C++ Backend
                        const response = await this._backendClient.getCodeSuggestion(
                            this._projectId,
                            data.value,
                            activeContext
                        );

                        // Update the "Thinking" bubble with real data
                        this._view?.webview.postMessage({
                            type: 'updateLastResponse',
                            value: response
                        });
                    } catch (error: any) {
                        this._view?.webview.postMessage({
                            type: 'updateLastResponse',
                            value: `❌ Critical Failure: ${error.message}. Check if C++ backend is frozen.`
                        });
                    }
                    break;
                }

                case 'applyCode': {
                    const rawCode = data.value;
                    const blockId = data.id;
                    
                    // 1. Extract Target using Regex from the [TARGET: path] tag
                    const targetMatch = rawCode.match(/(?:\/\/|#|--)\s*\[TARGET:\s*([^\]\s]+)\]/i);
                    const workspaceFolders = vscode.workspace.workspaceFolders;

                    if (!workspaceFolders) {
                        vscode.window.showErrorMessage("No active workspace found.");
                        return;
                    }

                    try {
                        let targetUri: vscode.Uri;
                        
                        if (targetMatch) {
                            const relativePath = targetMatch[1].trim();
                            targetUri = vscode.Uri.joinPath(workspaceFolders[0].uri, relativePath);
                        } else {
                            // Fallback: Apply to currently active editor if no tag found
                            const activeEditor = vscode.window.activeTextEditor;
                            if (!activeEditor) throw new Error("No target file specified and no active editor.");
                            targetUri = activeEditor.document.uri;
                        }

                        // 2. Clean the code (remove the TARGET tag line)
                        const cleanCode = rawCode.replace(/(?:\/\/|#|--)\s*\[TARGET:.*?\]\s*\n?/, "").trim();

                        // 3. SpaceX Integrity Check: Create file if it doesn't exist
                        const edit = new vscode.WorkspaceEdit();
                        
                        // Create or Overwrite logic
                        const documentExists = await vscode.workspace.fs.stat(targetUri).then(() => true, () => false);
                        
                        if (!documentExists) {
                            edit.createFile(targetUri, { ignoreIfExists: true });
                        }

                        // Select the whole range to replace or append
                        // For this implementation, we overwrite (High Authority Mode)
                        const fullRange = new vscode.Range(
                            new vscode.Position(0, 0),
                            new vscode.Position(10000, 0) // Overly large range to ensure overwrite
                        );

                        edit.replace(targetUri, fullRange, cleanCode);
                        
                        await vscode.workspace.applyEdit(edit);
                        await vscode.workspace.openTextDocument(targetUri).then(doc => doc.save());

                        // 4. Notify UI of success
                        webviewView.webview.postMessage({ type: 'applySuccess', id: blockId });
                        vscode.window.setStatusBarMessage(`$(check) Applied AI changes to ${path.basename(targetUri.fsPath)}`, 3000);

                    } catch (err: any) {
                        vscode.window.showErrorMessage(`Docking failed: ${err.message}`);
                    }
                    break;
                }

                case 'openFile': {
                    // 🚀 PROGRAMMER FIX: Robust file opening
                    const workspaceFolders = vscode.workspace.workspaceFolders;
                    if (workspaceFolders) {
                        const fullPath = path.join(workspaceFolders[0].uri.fsPath, data.value);
                        const uri = vscode.Uri.file(fullPath);
                        try {
                            const doc = await vscode.workspace.openTextDocument(uri);
                            await vscode.window.showTextDocument(doc);
                        } catch (e) {
                            // If path is already absolute or slightly different, try finding it
                            const found = await vscode.workspace.findFiles(`**/${data.value}`, null, 1);
                            if (found.length > 0) {
                                const doc = await vscode.workspace.openTextDocument(found[0]);
                                await vscode.window.showTextDocument(doc);
                            }
                        }
                    }
                    break;
                }
            }
        });

        webviewView.onDidDispose(() => { this._view = undefined; });
    }

    private _getHtmlForWebview(webview: vscode.Webview) {
        // 🚀 RESOLVER: Map absolute paths
        const scriptUri = webview.asWebviewUri(vscode.Uri.joinPath(this._extensionUri, 'media', 'chat.js'));
        const styleUri = webview.asWebviewUri(vscode.Uri.joinPath(this._extensionUri, 'media', 'chat.css'));
        // Use a CDN link that is most likely to pass CSP, but add it to the policy
        const markedUri = "https://cdn.jsdelivr.net/npm/marked/marked.min.js";

        console.log("🚀 [Host] Injecting Script URI:", scriptUri.toString());
        console.log("🚀 [Host] Injecting Style URI:", styleUri.toString());

        return `<!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <!-- 🚀 CSP: Explicitly allow the scripts and styles -->
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${webview.cspSource} https:; script-src ${webview.cspSource} 'unsafe-inline' https://cdn.jsdelivr.net; style-src ${webview.cspSource} 'unsafe-inline';">
            <link href="${styleUri}" rel="stylesheet">
        </head>
        <body>
            <div id="chat-container"></div>
            <div class="input-wrapper">
                <div class="input-container">
                    <textarea id="prompt" rows="1" placeholder="Ask anything..."></textarea>
                    <button id="send-btn">
                        <svg viewBox="0 0 24 24"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
                    </button>
                </div>
            </div>
            <!-- Load dependencies -->
            <script src="${markedUri}"></script>
            <script src="${scriptUri}"></script>
        </body>
        </html>`;
    }
}