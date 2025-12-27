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

                    const workspaceFolders = vscode.workspace.workspaceFolders;
                    if (!workspaceFolders) return;

                    try {
                        const headerMatch = rawCode.match(/(?:\/\/|#|--)\s*\[TARGET:\s*([^:\]\s]+):?([^:\]\s]+)?:?([\s\S]*?)\]/i);
                        if (!headerMatch) throw new Error("Metadata Header Missing");

                        const relativePathRaw = headerMatch[1].trim();
                        let relativePath = relativePathRaw;

                        const targetUriInitial = vscode.Uri.joinPath(workspaceFolders[0].uri, relativePath);

                        try {
                            // Check if the file the AI suggested actually exists
                            await vscode.workspace.fs.stat(targetUriInitial);
                        } catch (e) {
                            // If it doesn't exist, and the AI hallucinated (e.g., 'data.json' or 'file'), 
                            // fallback to the active editor
                            const activeEditor = vscode.window.activeTextEditor;
                            if (activeEditor) {
                                const activePath = vscode.workspace.asRelativePath(activeEditor.document.uri);
                                console.warn(`⚠️ [SpaceX] Target Mismatch: AI suggested '${relativePath}', but it doesn't exist. Re-routing to Active Editor: '${activePath}'`);
                                relativePath = activePath;
                            } else {
                                throw new Error(`The file '${relativePath}' does not exist and no active editor is open.`);
                            }
                        }

                        // 🚀 HALLUCINATION GUARD: Auto-correct 'file' to active editor path
                        if (relativePath.toLowerCase() === 'file') {
                            const activeEditor = vscode.window.activeTextEditor;
                            if (activeEditor) {
                                relativePath = vscode.workspace.asRelativePath(activeEditor.document.uri);
                                console.warn(`⚠️ [SpaceX] Hallucination Detected: AI sent 'file' instead of '${relativePath}'. Auto-correcting.`);
                            } else {
                                throw new Error("AI used 'file' placeholder but no active editor is open.");
                            }
                        }

                        const action = (headerMatch[2] || "INSERT").toUpperCase();
                        const searchKey = headerMatch[3] ? headerMatch[3].trim() : "";  

                        // 🚀 PLACEHOLDER GUARD
                        if (action === "ACTION" || searchKey === "ANCHOR") {
                            throw new Error("AI hallucinated the template placeholders. Please tell the AI: 'Use REPLACE:ALL for this change'.");
                        }
                        
                        // Use the first workspace folder as root (Standard behavior)
                        const targetUri = vscode.Uri.joinPath(workspaceFolders[0].uri, relativePath);
                        
                        // Ensure we strip the tag accurately
                        const headerEndIndex = rawCode.indexOf(']');
                        const cleanCode = rawCode.substring(headerEndIndex + 1).trim();

                        const document = await vscode.workspace.openTextDocument(targetUri);
                        const fullText = document.getText();
                        const edit = new vscode.WorkspaceEdit();

                        // Helper for Full Document Range (Safer than lineAt)
                        const getFullDocumentRange = (doc: vscode.TextDocument) => {
                            const firstLine = doc.lineAt(0);
                            const lastLine = doc.lineAt(doc.lineCount - 1);
                            return new vscode.Range(firstLine.range.start, lastLine.rangeIncludingLineBreak.end);
                        };

                        if (cleanCode.length === 0 && action !== "DELETE") {
                            throw new Error("AI provided the instruction tag but forgot to include the actual code below it. Please ask the AI to 'Try again with the full code block'.");
                        }

                        // 🚀 SEARCH KEY VALIDATION
                        if (action === "INSERT" || action === "REPLACE") {
                            if (searchKey === cleanCode || searchKey === relativePath) {
                                throw new Error("AI is confusing the Anchor with the Content. Advise the AI: 'Use REPLACE:ALL instead'.");
                            }
                        }

                        // 🚀 SURGICAL ENGINE 2.1
                        if (action === "REPLACE" && searchKey) {
                            let rangeToReplace: vscode.Range;

                            // 🚀 SURGICAL UPGRADE: Case-insensitive 'starts with' check for ALL
                            // This handles "ALL", "ALL:file", "ALL:test04.json", etc.
                            const isFullReplace = searchKey.toUpperCase() === "ALL" || 
                                                searchKey.toUpperCase().startsWith("ALL:");

                            if (isFullReplace) {
                                console.log("📂 [SpaceX] Full file replacement initiated via fuzzy ALL match:", searchKey);
                                rangeToReplace = getFullDocumentRange(document);
                            } else {
                                // Standard surgical logic with newline normalization
                                const normalizedSearch = searchKey.replace(/\r\n/g, '\n');
                                const normalizedFullText = fullText.replace(/\r\n/g, '\n');

                                let index = normalizedFullText.indexOf(normalizedSearch);
                                
                                // ... (rest of your existing structural match/error handling) ...
                                
                                if (index === -1) {
                                    throw new Error(`Anchor text not found in ${relativePath}. Ensure the 'search_string' matches a unique block in your file.`);
                                }
                                
                                rangeToReplace = new vscode.Range(
                                    document.positionAt(index),
                                    document.positionAt(index + searchKey.length)
                                );
                            }
                            
                            edit.replace(targetUri, rangeToReplace, cleanCode);
                        }
                        else if (action === "INSERT" && searchKey) {
                            // Newline normalization for robust matching
                            const cleanSearchKey = searchKey.replace(/\r/g, "");
                            const cleanFullText = fullText.replace(/\r/g, "");
                            const index = cleanFullText.indexOf(cleanSearchKey);
                            
                            if (index === -1) {
                                throw new Error(`Anchor not found: "${searchKey}"`);
                            }

                            const startPos = document.positionAt(fullText.indexOf(searchKey));
                            const line = document.lineAt(startPos.line);
                            const lineEnd = line.range.end;

                            // 🚀 SURGICAL REFINEMENT: Ensure code is on a new line
                            edit.insert(targetUri, lineEnd, `\n${cleanCode}`);
                        }
                        else if (action === "APPEND") {
                            const lastLine = document.lineAt(document.lineCount - 1);
                            edit.insert(targetUri, lastLine.range.end, `\n\n${cleanCode}`);
                        }
                        else if (action === "OVERWRITE") {
                            edit.replace(targetUri, getFullDocumentRange(document), cleanCode);
                        }
                        else {
                            throw new Error(`Action '${action}' is not supported or requires a valid search key.`);
                        }

                        const success = await vscode.workspace.applyEdit(edit);
                        if (success) {
                            await document.save();
                            // Show the document if it's not visible
                            await vscode.window.showTextDocument(document, { preview: false, preserveFocus: true });
                            
                            this._view?.webview.postMessage({ type: 'applySuccess', id: blockId });
                            vscode.window.setStatusBarMessage(`$(check) AI applied changes to ${relativePath}`, 3000);
                        }

                    } catch (err: any) {
                        vscode.window.showErrorMessage(`Edit Failed: ${err.message}`);
                        console.error("ApplyCode Error:", err);
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