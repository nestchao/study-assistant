import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import { GoogleGenerativeAI } from "@google/generative-ai";

export class LocalBackend {
    private projectRoot: string;
    private storageDir: string;
    private genAI: GoogleGenerativeAI;
    private embeddingModel: any;
    private chatModel: any;

    constructor(projectRoot: string, apiKey: string) {
        this.projectRoot = projectRoot;
        this.storageDir = path.join(projectRoot, '.codeminds');
        
        // Initialize Gemini
        this.genAI = new GoogleGenerativeAI(apiKey);
        this.embeddingModel = this.genAI.getGenerativeModel({ model: "text-embedding-004" });
        this.chatModel = this.genAI.getGenerativeModel({ model: "gemini-2.5-flash-lite" });

        if (!fs.existsSync(this.storageDir)) {
            fs.mkdirSync(this.storageDir);
        }
    }

    // --- 1. INDEXING ---
    async indexProject() {
        const ignore = ['node_modules', '.git', 'dist', 'out', '.codeminds', '.vscode', 'package-lock.json'];
        const files: string[] = [];
        
        const scan = (dir: string) => {
            const list = fs.readdirSync(dir);
            list.forEach(file => {
                if (ignore.includes(file)) return;
                const fullPath = path.join(dir, file);
                try {
                    const stat = fs.statSync(fullPath);
                    if (stat && stat.isDirectory()) scan(fullPath);
                    else {
                        if (['.ts', '.js', '.py', '.txt', '.md', '.json', '.html', '.css', '.java', '.cpp'].includes(path.extname(file))) {
                            files.push(fullPath);
                        }
                    }
                } catch (e) { /* ignore access errors */ }
            });
        };
        scan(this.projectRoot);

        let fullContext = "";
        const vectors: any[] = [];
        
        // Limit to 50 files for demo speed, remove slice for full project
        for (const file of files.slice(0, 50)) {
            const content = fs.readFileSync(file, 'utf-8');
            const relPath = path.relative(this.projectRoot, file);
            
            // Skip large files (>20KB) to save API tokens
            if (content.length > 20000) continue;

            fullContext += `\n--- FILE: ${relPath} ---\n${content}\n`;
            
            if (content.trim().length > 0) {
                 try {
                    const embedding = await this.getEmbedding(content);
                    vectors.push({ path: relPath, vector: embedding, content: content });
                 } catch (e) { console.log(`Skipped ${relPath} due to embedding error`); }
            }
        }

        fs.writeFileSync(path.join(this.storageDir, 'full_context.txt'), fullContext);
        fs.writeFileSync(path.join(this.storageDir, 'vectors.json'), JSON.stringify(vectors));
        fs.writeFileSync(path.join(this.storageDir, 'tree.json'), JSON.stringify(files.map(f => path.relative(this.projectRoot, f))));
        
        return vectors.length;
    }

    // --- 2. RETRIEVAL ---
    async retrieveContext(query: string) {
        const vecPath = path.join(this.storageDir, 'vectors.json');
        if (!fs.existsSync(vecPath)) return "";
        
        const vectors = JSON.parse(fs.readFileSync(vecPath, 'utf-8'));
        const queryEmb = await this.getEmbedding(query);

        const scored = vectors.map((doc: any) => {
            return { ...doc, score: this.cosineSimilarity(queryEmb, doc.vector) };
        });

        scored.sort((a: any, b: any) => b.score - a.score);
        // Take top 3 relevant files
        return scored.slice(0, 3).map((d: any) => `--- FILE: ${d.path} ---\n${d.content}`).join('\n\n');
    }

    // --- 3. CHAT ---
    async chat(query: string, context: string) {
        const prompt = `
        You are a senior developer assistant. Answer the user question based ONLY on the provided code context.
        If the answer is not in the context, say you don't know.
        
        USER QUESTION: ${query}

        CODE CONTEXT:
        ${context}
        `;
        
        try {
            const result = await this.chatModel.generateContent(prompt);
            return result.response.text();
        } catch (e: any) {
            return `Error generating response: ${e.message}`;
        }
    }

    // --- Helpers ---
    async getEmbedding(text: string) {
        const result = await this.embeddingModel.embedContent(text);
        return result.embedding.values;
    }

    cosineSimilarity(vecA: number[], vecB: number[]) {
        const dotProduct = vecA.reduce((acc, val, i) => acc + val * vecB[i], 0);
        const magA = Math.sqrt(vecA.reduce((acc, val) => acc + val * val, 0));
        const magB = Math.sqrt(vecB.reduce((acc, val) => acc + val * val, 0));
        return dotProduct / (magA * magB);
    }
}