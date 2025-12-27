// extension/src/providers/CompletionProvider.ts

import * as vscode from 'vscode';
import { BackendClient } from '../services/BackendClient';

export class GhostTextProvider implements vscode.InlineCompletionItemProvider {
    
    // 🚀 ARCHITECTURE FIX: Change 'string | null' to '() => string | null'
    constructor(
        private readonly _backendClient: BackendClient,
        private readonly _getProjectId: () => string | null 
    ) {}

    async provideInlineCompletionItems(
        document: vscode.TextDocument,
        position: vscode.Position,
        context: vscode.InlineCompletionContext,
        token: vscode.CancellationToken
    ): Promise<vscode.InlineCompletionItem[]> {

        // 📡 TELEMETRY
        console.log(`📡 [GhostText] VS Code requested completion at Line ${position.line}`);

        await new Promise(resolve => setTimeout(resolve, 200));
        if (token.isCancellationRequested) return [];

        // 🚀 DYNAMIC FETCH: Call the function to get the LATEST ID
        const projectId = this._getProjectId(); 

        if (!projectId) {
            console.log("❌ [GhostText] Aborted: No Project ID yet.");
            return [];
        }

        const prefix = document.getText(new vscode.Range(new vscode.Position(Math.max(0, position.line - 10), 0), position));

        try {
            const result = await this._backendClient.getAutocomplete(prefix, "");
            
            // 📡 DEBUG: Check exactly what the engine returned
            console.log(`🔍 [GhostText] Raw Engine Payload: [${result}]`);

            if (!result || result.trim() === "") return [];

            // 🚀 SURGICAL ALIGNMENT: 
            // We tell VS Code the text starts EXACTLY at the cursor.
            const item = new vscode.InlineCompletionItem(result);
            item.range = new vscode.Range(position, position); 
            
            return [item];
        } catch (e) {
            return [];
        }
    }
}