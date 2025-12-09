import axios, { AxiosInstance } from 'axios';
import * as fs from 'fs';
import FormData from 'form-data'; // FIXED: Changed from 'import * as' to default import

// Define the ports for your local servers
const CPP_BACKEND_URL = 'http://localhost:5002';
const PYTHON_BACKEND_URL = 'http://localhost:5000';

// Create separate axios instances for each backend
const cppClient = axios.create({ baseURL: CPP_BACKEND_URL });
const pythonClient = axios.create({ baseURL: PYTHON_BACKEND_URL });

export class BackendClient {

    // --- System Health ---
    async checkAllBackends(): Promise<{ cpp: boolean, python: boolean }> {
        // FIXED: Changed type from 'typeof axios' to 'AxiosInstance'
        const check = async (client: AxiosInstance, name: string) => {
            try {
                const response = await client.get('/api/hello', { timeout: 1000 });
                return response.status === 200;
            } catch (error) {
                console.warn(`[BackendClient] ${name} backend is offline.`);
                return false;
            }
        };
        const [cppStatus, pythonStatus] = await Promise.all([
            check(cppClient, 'C++'),
            check(pythonClient, 'Python'),
        ]);
        return { cpp: cppStatus, python: pythonStatus };
    }

    // --- C++ Backend Methods (Code Intelligence) ---
    async registerCodeProject(
        projectId: string, 
        path: string, 
        extensions: string[], 
        ignoredPaths: string[],
        includedPaths: string[] = [] 
    ): Promise<void> {
        await cppClient.post(`/sync/register/${projectId}`, {
            local_path: path,
            extensions,
            ignored_paths: ignoredPaths,
            included_paths: includedPaths,
            sync_mode: 'hybrid' 
        });
    }

    async syncCodeProject(projectId: string): Promise<{ nodes?: number, message: string }> {
        const response = await cppClient.post(`/sync/run/${projectId}`);
        return response.data;
    }

    async getCodeSuggestion(projectId: string, prompt: string): Promise<string> {
        const response = await cppClient.post('/generate-code-suggestion', {
            project_id: projectId,
            prompt,
            use_hyde: true,
        });
        return response.data.suggestion;
    }
    
    async getContextCandidates(projectId: string, prompt: string): Promise<any[]> {
        const response = await cppClient.post('/retrieve-context-candidates', {
            project_id: projectId,
            prompt,
        });
        return response.data.candidates;
    }


    // --- Python Backend Methods (Study Hub & Paper Solver) ---
    async getStudyProjects(): Promise<{ id: string, name: string }[]> {
        const response = await pythonClient.get('/get-projects');
        return response.data;
    }

    async createStudyProject(name: string): Promise<string> {
        const response = await pythonClient.post('/create-project', { name });
        return response.data.id;
    }

    async getProjectSources(projectId: string): Promise<any[]> {
        const response = await pythonClient.get(`/get-sources/${projectId}`);
        return response.data;
    }

    async uploadPDF(projectId: string, filePath: string): Promise<void> {
        const form = new FormData();
        form.append('pdfs', fs.createReadStream(filePath));

        await pythonClient.post(`/upload-source/${projectId}`, form, {
            headers: form.getHeaders(),
        });
    }

    async getNote(projectId: string, sourceId: string): Promise<string> {
        const response = await pythonClient.get(`/get-note/${projectId}/${sourceId}`);
        return response.data.note_html;
    }

    async getPastPapers(projectId: string): Promise<any[]> {
        const response = await pythonClient.get(`/get-papers/${projectId}`);
        return response.data;
    }

    async uploadPastPaper(projectId: string, filePath: string, mode: 'multimodal' | 'text_only'): Promise<void> {
        const form = new FormData();
        form.append('paper', fs.createReadStream(filePath));
        form.append('analysis_mode', mode);

        await pythonClient.post(`/upload-paper/${projectId}`, form, {
            headers: form.getHeaders(),
        });
    }
}

// Singleton instance
let _client: BackendClient | null = null;
export function getBackendClient(): BackendClient {
    if (!_client) {
        _client = new BackendClient();
    }
    return _client;
}