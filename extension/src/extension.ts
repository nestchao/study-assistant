import * as vscode from 'vscode';
import { StudyHubProvider } from './providers/StudyHubProvider';
import { PaperSolverProvider } from './providers/PaperSolverProvider';
import { GhostTextProvider } from './providers/CompletionProvider';
import { getBackendClient } from './services/BackendClient';
import { CodeChatProvider } from './providers/CodeChatProvider'; // Assuming you move providers to a /providers folder
import { CodeConfigProvider } from './providers/CodeConfigProvider'; 

let currentProjectId: string | null = null;

export async function activate(context: vscode.ExtensionContext) {
    console.log('Study Assistant Extension Activating...');

    const backendClient = getBackendClient();

    // Check backend status
    const status = await backendClient.checkAllBackends();  
    
    if (!status.cpp && !status.python) {
        vscode.window.showWarningMessage(
            '⚠️ Study Assistant: Backends not running. Please start the C++ and Python backends.',
            'Start Backends'
        ).then(selection => {
            if (selection === 'Start Backends') {
                vscode.env.openExternal(vscode.Uri.parse('https://github.com/your-repo/setup'));
            }
        });
    } else {
        const statusMessage = `Study Assistant Active: C++ ${status.cpp ? '✅' : '❌'} | Python ${status.python ? '✅' : '❌'}`;
        vscode.window.showInformationMessage(statusMessage);
    }

    // Get workspace folder
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (workspaceFolders) {
        const workspacePath = workspaceFolders[0].uri.fsPath;
        // Generate project ID from workspace path
        currentProjectId = Buffer.from(workspacePath).toString('base64').replace(/[^a-zA-Z0-9]/g, '_');
    }

    // ==================== Register Providers ====================

     // 1. Code Config Provider 
    const codeConfigProvider = new CodeConfigProvider(context.extensionUri);
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider('study-assistant-config', codeConfigProvider)
    );
    
    // 1. Code Chat Provider (C++ Backend)
    const codeChatProvider = new CodeChatProvider(context.extensionUri, backendClient, currentProjectId);
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider('study-assistant-chat', codeChatProvider)
    );

    // 2. Study Hub Provider (Python Backend)
    const studyHubProvider = new StudyHubProvider(context.extensionUri, backendClient);
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider('study-assistant-hub', studyHubProvider)
    );

    // 3. Paper Solver Provider (Python Backend)
    const paperSolverProvider = new PaperSolverProvider(context.extensionUri, backendClient);
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider('study-assistant-papers', paperSolverProvider)
    );

    // 4. Ghost Text Completion Provider
    const config = vscode.workspace.getConfiguration('studyAssistant');
    if (config.get('enableAutoCompletion')) {
        const completionProvider = vscode.languages.registerInlineCompletionItemProvider(
            { pattern: '**' },
            new GhostTextProvider(backendClient, currentProjectId)
        );
        context.subscriptions.push(completionProvider);
    }

    // ==================== Register Commands ====================

    // Register Code Project
    context.subscriptions.push(
        vscode.commands.registerCommand('studyAssistant.registerProject', async (options?: { silent: boolean }) => {
            if (!workspaceFolders) {
                vscode.window.showErrorMessage("No workspace open");
                return;
            }
            const workspacePath = workspaceFolders[0].uri.fsPath;
            const workspaceUri = workspaceFolders[0].uri;

            // --- Read from Settings ---
            const config = vscode.workspace.getConfiguration('studyAssistant', workspaceUri);
            
            // Debug: Print to "Extension Host" console
            console.log('Raw Config:', {
                ext: config.get('allowedExtensions'),
                ign: config.get('ignoredPaths'),
                inc: config.get('includedPaths')
            });

            const extensionsStr = config.get<string>('allowedExtensions', 'ts');
            const ignoredStr = config.get<string>('ignoredPaths', 'node_modules');
            const includedStr = config.get<string>('includedPaths', '');

            // 2. Robust Parsing & Normalization
            const parseList = (str: string) => 
                (str || '').split(/[,\n]+/) // Handle null/undefined safely
                .map(e => e.trim().replace(/\\/g, '/')) 
                .filter(e => e.length > 0);

            const extensions = parseList(extensionsStr);
            const ignoredPaths = parseList(ignoredStr);
            const includedPaths = parseList(includedStr);
            
            // Manually force defaults if empty (Fallback)
            if (ignoredPaths.length === 0) {
                ignoredPaths.push('node_modules', '.git', 'dist', 'build');
            }

            console.log('Sending Registration Config:', { extensions, ignoredPaths, includedPaths });

            // --- MISSING PART RESTORED BELOW ---
            const showNotification = !options?.silent;

            const task = async () => {
                try {
                    await backendClient.registerCodeProject(
                        currentProjectId!, 
                        workspacePath,
                        extensions,
                        ignoredPaths,
                        includedPaths
                    );
                    
                    // Auto-trigger sync after registration
                    await backendClient.syncCodeProject(currentProjectId!, workspacePath);

                    if (showNotification) {
                        vscode.window.showInformationMessage(`✅ Project Configured & Synced!`);
                    }
                } catch (error: any) {
                    vscode.window.showErrorMessage(`Failed: ${error.message}`);
                }
            };

            if (showNotification) {
                await vscode.window.withProgress({
                    location: vscode.ProgressLocation.Notification,
                    title: 'Registering & Syncing...',
                    cancellable: false
                }, task);
            } else {
                await task();
            }
        })
    );
    
    // Sync Project
    context.subscriptions.push(
        vscode.commands.registerCommand('studyAssistant.syncProject', async () => {
            if (!currentProjectId || !workspaceFolders) return;
            const workspacePath = workspaceFolders[0].uri.fsPath;

            await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: 'Syncing...',
                cancellable: false
            }, async () => {
                try {
                    const result = await backendClient.syncCodeProject(currentProjectId!, workspacePath);
                    const count = result.nodes || (result.files ? result.files.length : 0); 
                    vscode.window.showInformationMessage(`✅ Sync complete. Indexed ${count} items.`);
                } catch (error: any) {
                    vscode.window.showErrorMessage(`Sync failed: ${error.message}`);
                }
            });
        })
    );

    // Create Study Project
    context.subscriptions.push(
        vscode.commands.registerCommand('studyAssistant.createStudyProject', async () => {
            const name = await vscode.window.showInputBox({ prompt: 'Enter study project name' });
            if (!name) return;
            try {
                await backendClient.createStudyProject(name);
                studyHubProvider.refresh(); // Refresh the list
            } catch (e: any) { vscode.window.showErrorMessage(e.message); }
        })
    );

    // Upload PDF
    context.subscriptions.push(
        vscode.commands.registerCommand('studyAssistant.uploadPDF', async () => {
            const projects = await backendClient.getStudyProjects();
            
            if (projects.length === 0) {
                vscode.window.showWarningMessage('Create a study project first');
                return;
            }

            const selectedProject = await vscode.window.showQuickPick(
                projects.map(p => ({ label: p.name, id: p.id })),
                { placeHolder: 'Select study project' }
            );

            if (!selectedProject) return;

            const fileUri = await vscode.window.showOpenDialog({
                canSelectFiles: true,
                canSelectMany: false,
                filters: { 'PDF Files': ['pdf'] }
            });

            if (!fileUri || fileUri.length === 0) return;

            await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: 'Uploading and processing PDF...',
                cancellable: false
            }, async () => {
                try {
                    await backendClient.uploadPDF(selectedProject.id, fileUri[0].fsPath);
                    vscode.window.showInformationMessage('✅ PDF uploaded and notes generated');
                    studyHubProvider.refresh();
                } catch (error: any) {
                    vscode.window.showErrorMessage(`Upload failed: ${error.message}`);
                }
            });
        })
    );

    // Solve Past Paper
    context.subscriptions.push(
        vscode.commands.registerCommand('studyAssistant.solvePaper', async () => {
            const projects = await backendClient.getStudyProjects();
            
            if (projects.length === 0) {
                vscode.window.showWarningMessage('Create a study project first');
                return;
            }

            const selectedProject = await vscode.window.showQuickPick(
                projects.map(p => ({ label: p.name, id: p.id })),
                { placeHolder: 'Select study project' }
            );

            if (!selectedProject) return;

            const fileUri = await vscode.window.showOpenDialog({
                canSelectFiles: true,
                canSelectMany: false,
                filters: { 'Papers': ['pdf', 'png', 'jpg', 'jpeg'] }
            });

            if (!fileUri || fileUri.length === 0) return;

            const analysisMode = await vscode.window.showQuickPick(
                [
                    { label: 'Multimodal (Recommended)', value: 'multimodal' },
                    { label: 'Text Only', value: 'text_only' }
                ],
                { placeHolder: 'Select analysis mode' }
            );

            if (!analysisMode) return;

            await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: 'Analyzing past paper...',
                cancellable: false
            }, async () => {
                try {
                    await backendClient.uploadPastPaper(
                        selectedProject.id,
                        fileUri[0].fsPath,
                        analysisMode.value as any
                    );
                    vscode.window.showInformationMessage('✅ Paper analyzed successfully');
                    paperSolverProvider.refresh();
                } catch (error: any) {
                    vscode.window.showErrorMessage(`Analysis failed: ${error.message}`);
                }
            });
        })
    );

    // Show Mindmap
    context.subscriptions.push(
        vscode.commands.registerCommand('studyAssistant.showMindmap', async () => {
            // Create webview panel for mindmap
            const panel = vscode.window.createWebviewPanel(
                'mindmap',
                'Project Mindmap',
                vscode.ViewColumn.One,
                { enableScripts: true }
            );

            // You would generate the mindmap visualization here
            panel.webview.html = `
                <!DOCTYPE html>
                <html>
                <head>
                    <title>Project Mindmap</title>
                </head>
                <body>
                    <h1>Project Structure Visualization</h1>
                    <p>Mindmap feature coming soon...</p>
                </body>
                </html>
            `;
        })
    );

    // Check Backend Status
    context.subscriptions.push(
        vscode.commands.registerCommand('studyAssistant.checkBackendStatus', async () => {
            const status = await backendClient.checkAllBackends();
            
            const message = `
Backend Status:
• C++ Backend (Code Intelligence): ${status.cpp ? '✅ Running' : '❌ Offline'}
• Python Backend (Study Features): ${status.python ? '✅ Running' : '❌ Offline'}
            `.trim();

            vscode.window.showInformationMessage(message, 'Refresh').then(selection => {
                if (selection === 'Refresh') {
                    vscode.commands.executeCommand('studyAssistant.checkBackendStatus');
                }
            });
        })
    );

    console.log('Study Assistant Extension Activated!');
}

export function deactivate() {
    console.log('Study Assistant Extension Deactivated');
}