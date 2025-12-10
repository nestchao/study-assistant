import * as vscode from 'vscode';
import { BackendClient } from '../services/BackendClient';
import { GoogleGenerativeAI } from "@google/generative-ai";

export class GhostTextProvider implements vscode.InlineCompletionItemProvider {
    
    // --- THIS CONSTRUCTOR WAS MISSING ---
    constructor(
        private readonly _backendClient: BackendClient,
        private readonly _projectId: string | null
    ) {}

    async provideInlineCompletionItems(
        document: vscode.TextDocument,
        position: vscode.Position,
        context: vscode.InlineCompletionContext,
        token: vscode.CancellationToken
    ): Promise<vscode.InlineCompletionItem[]> {

        // 1. Get API Key
        const config = vscode.workspace.getConfiguration('studyAssistant'); // Ensure this matches package.json ID
        const apiKey = config.get('apiKey') as string;
        
        if (!apiKey) return [];

        // 2. Init Gemini
        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash-lite" });

        // 3. Get Context
        const codeBefore = document.getText(new vscode.Range(new vscode.Position(0, 0), position));
        const codeAfter = document.getText(new vscode.Range(position, new vscode.Position(document.lineCount, 0)));

        // 4. Prompt
        const prompt = `
        You are an autocomplete coding assistant. 
        PREDICT only the code that follows the cursor. DO NOT wrap in markdown.
        
        [CODE BEFORE CURSOR]
        ${codeBefore.slice(-1000)} 
        
        [CODE AFTER CURSOR]
        ${codeAfter.slice(0, 500)}
        
        [YOUR PREDICTION]
        `;

        try {
            const result = await model.generateContent(prompt);
            const prediction = result.response.text();
            
            // 5. Return result
            return [new vscode.InlineCompletionItem(prediction, new vscode.Range(position, position))];
        } catch (e) {
            return [];
        }
    }
}