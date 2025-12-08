import * as vscode from 'vscode';
import { StudyHubProvider } from './providers/StudyHubProvider';
import { PaperSolverProvider } from './providers/PaperSolverProvider';
import { GhostTextProvider } from './providers/CompletionProvider';
import { getBackendClient } from './services/BackendClient';
import { CodeChatProvider } from './providers/CodeChatProvider'; // Assuming you move providers to a /providers folder

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
        vscode.commands.registerCommand('studyAssistant.registerProject', async () => {
            if (!workspaceFolders) {
                vscode.window.showErrorMessage('Please open a workspace folder first');
                return;
            }

            const workspacePath = workspaceFolders[0].uri.fsPath;

            // Ask for extensions to include
            const extensionsInput = await vscode.window.showInputBox({
                prompt: 'File extensions to include (comma-separated)',
                value: 'py,ts,js,cpp,h,java'
            });

            if (!extensionsInput) return;

            const extensions = extensionsInput.split(',').map(e => e.trim());
            const ignoredPaths = ['node_modules', '.git', 'dist', 'build', '__pycache__', '.vscode'];

            await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: 'Registering project with C++ backend...',
                cancellable: false
            }, async () => {
                try {
                    await backendClient.registerCodeProject(
                        currentProjectId!,
                        workspacePath,
                        extensions,
                        ignoredPaths
                    );
                    vscode.window.showInformationMessage('✅ Project registered successfully');
                } catch (error: any) {
                    vscode.window.showErrorMessage(`Failed to register project: ${error.message}`);
                }
            });
        })
    );

    // Sync Project
    context.subscriptions.push(
        vscode.commands.registerCommand('studyAssistant.syncProject', async () => {
            if (!currentProjectId) {
                vscode.window.showErrorMessage('No project registered');
                return;
            }

            await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: 'Syncing project...',
                cancellable: false
            }, async () => {
                try {
                    const result = await backendClient.syncCodeProject(currentProjectId!);
                    vscode.window.showInformationMessage(
                        `✅ Sync complete: ${result.nodes || 0} nodes indexed`
                    );
                } catch (error: any) {
                    vscode.window.showErrorMessage(`Sync failed: ${error.message}`);
                }
            });
        })
    );

    // Create Study Project
    context.subscriptions.push(
        vscode.commands.registerCommand('studyAssistant.createStudyProject', async () => {
            const name = await vscode.window.showInputBox({
                prompt: 'Enter study project name',
                placeHolder: 'e.g., Computer Science 101'
            });

            if (!name) return;

            try {
                const projectId = await backendClient.createStudyProject(name);
                vscode.window.showInformationMessage(`✅ Study project created: ${name}`);
                
                // Refresh Study Hub view
                studyHubProvider.refresh();
            } catch (error: any) {
                vscode.window.showErrorMessage(`Failed: ${error.message}`);
            }
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