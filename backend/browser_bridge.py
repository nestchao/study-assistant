# backend/browser_bridge.py
import os
import time
import threading
import queue
import re
from playwright.sync_api import sync_playwright

class AIStudioBridge:
    def __init__(self):
        self.cmd_queue = queue.Queue()
        self.worker_thread = None
        self.lock = threading.Lock()
        self.bot_profile_path = os.path.join(os.getcwd(), "chrome_stealth_profile")

    def start(self):
        with self.lock:
            if self.worker_thread and self.worker_thread.is_alive():
                return
            print("🚀 Starting Dedicated Chrome Bridge Thread...")
            self.worker_thread = threading.Thread(target=self._browser_loop, daemon=True)
            self.worker_thread.start()

    def _browser_loop(self):
        try:
            with sync_playwright() as p:
                print("   [Thread] Launching Optimized Chrome...")
                
                context = p.chromium.launch_persistent_context(
                    user_data_dir=self.bot_profile_path,
                    executable_path=r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                    channel="chrome",
                    headless=False,
                    
                    # --- RAM & CPU OPTIMIZATIONS ---
                    viewport={'width': 1000, 'height': 600},
                    ignore_default_args=["--enable-automation"],
                    args=[
                        "--start-maximized", 
                        "--disable-blink-features=AutomationControlled",
                        "--disable-gpu",
                        "--disable-dev-shm-usage",
                        "--no-sandbox",
                        "--js-flags='--max-old-space-size=512'"
                    ]
                )
                
                page = context.pages[0]
                page.route("**/*.{png,jpg,jpeg,gif,webp}", lambda route: route.abort()) 
                
                print("✅ [Thread] Browser Ready.")

                while True:
                    task = self.cmd_queue.get()
                    if task is None: break 
                    
                    cmd_type, data, result_queue = task
                    try:
                        if cmd_type == "prompt":
                            response = self._internal_send_prompt(page, data)
                            result_queue.put(response)
                        elif cmd_type == "reset":
                            page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle")
                            result_queue.put(True)
                        elif cmd_type == "get_models":
                            models = self._internal_get_models(page)
                            result_queue.put(models)
                        elif cmd_type == "set_model":
                            success = self._internal_set_model(page, data)
                            result_queue.put(success)
                    except Exception as e:
                        result_queue.put(f"Bridge Error: {str(e)}")
                    finally:
                        self.cmd_queue.task_done()
        except Exception as e:
            print(f"❌ [Thread] CRITICAL BRIDGE FAILURE: {e}")

    def _internal_send_prompt(self, page, message):
        """Logic executed strictly inside the worker thread."""
        try:
            print(f"   [Thread] Navigating to New Chat...")
            page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=90000)
            
            prompt_box = page.get_by_placeholder("Start typing a prompt")
            prompt_box.wait_for(state="visible", timeout=30000)
            time.sleep(2)

            print(f"   [Thread] Injecting prompt ({len(message)} chars)...")
            page.evaluate("""
                (text) => {
                    const el = document.querySelector('textarea, [placeholder*="Start typing"]');
                    if (el) {
                        el.value = text;
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                        el.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                }
            """, message)

            time.sleep(1.5)
            page.keyboard.press("Enter")
            print("   [Thread] Waiting for AI response...", end="", flush=True)

            start_time = time.time()
            last_len = 0
            stable_count = 0

            while True:
                if time.time() - start_time > 180:
                    return "Error: Timeout waiting for response."

                current_chunks = page.locator('ms-text-chunk').all()
                current_count = len(current_chunks)
                
                if current_count > 0:
                    page.evaluate("""
                        () => {
                            const chunks = document.querySelectorAll('ms-text-chunk');
                            if (chunks.length > 0) {
                                const lastChunk = chunks[chunks.length - 1];
                                lastChunk.scrollIntoView({ block: 'end', behavior: 'instant' });
                                let parent = lastChunk.parentElement;
                                while (parent) {
                                    if (parent.scrollHeight > parent.clientHeight) {
                                        parent.scrollTop = parent.scrollHeight;
                                    }
                                    parent = parent.parentElement;
                                }
                                const editor = document.querySelector('ms-prompt-editor');
                                if (editor) editor.scrollTop = editor.scrollHeight;
                            }
                        }
                    """)

                run_btn = page.locator('ms-run-button button[aria-label="Run"]')
                is_run_visible = run_btn.is_visible()
                is_busy = not is_run_visible or current_count < 2

                current_text = current_chunks[-1].inner_text().strip() if current_chunks else ""
                current_len = len(current_text)

                print(".", end="", flush=True)

                if not is_busy and current_len > 0:
                    if current_len == last_len:
                        stable_count += 1
                        if stable_count >= 3:
                            break
                    else:
                        stable_count = 0
                else:
                    stable_count = 0
                
                last_len = current_len
                time.sleep(1)

            print("\n   [Thread] Captured.")

            final_chunks = page.locator('ms-text-chunk').all()
            raw_answer = final_chunks[-1].inner_text()

            clean_answer = raw_answer
            if "Expand to view model thoughts" in clean_answer:
                clean_answer = clean_answer.split("Expand to view model thoughts")[-1]

            ui_labels = [r'code\s+Markdown', r'^code$', r'^Markdown$', r'^-{3,}']
            for pattern in ui_labels:
                clean_answer = re.sub(pattern, '', clean_answer, flags=re.MULTILINE | re.IGNORECASE)

            clean_answer = re.sub(r'```[a-zA-Z]*\n?', '', clean_answer)
            clean_answer = clean_answer.replace('`', '')

            ui_keywords = ["expand_more", "expand_less", "content_copy", "share", "edit", "thumb_up", "thumb_down", "more_vert", "download"]
            junk_pattern = r'\s*(' + '|'.join(ui_keywords) + r')\s*'
            for _ in range(3):
                clean_answer = re.sub(junk_pattern + r'$', '', clean_answer).strip()
                clean_answer = re.sub(junk_pattern, '\n', clean_answer).strip()
            
            return re.sub(r'\n\s*\n', '\n\n', clean_answer).strip()

        except Exception as e:
            return f"Browser Error: {str(e)}"

    def _internal_get_models(self, page):
        """Scrapes available Gemini models from the UI."""
        print("   [Thread] Fetching models...")
        
        # --- FIX: Ensure Navigation ---
        if "aistudio.google.com" not in page.url:
             print("   [Thread] Page is blank or external. Navigating to AI Studio...")
             try:
                page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=60000)
             except Exception as e:
                print(f"   [Thread] Navigation failed: {e}")
                raise e

        try:
            # Wait for UI load
            page.locator("ms-model-selector button").wait_for(state="visible", timeout=30000)

            # 1. Open Menu
            model_btn = page.locator("ms-model-selector button")
            if not model_btn.is_visible():
                page.get_by_label("Run settings").click()
                time.sleep(0.5)
            
            model_btn.click()
            time.sleep(1.0)

            # 2. Click "Gemini" Filter
            try:
                gemini_filter = page.locator("button.ms-button-filter-chip").filter(has_text="Gemini").first
                if gemini_filter.is_visible():
                    gemini_filter.click()
                    time.sleep(0.5)
            except:
                pass 

            # 3. Scrape
            page.locator(".model-title-text").first.wait_for(timeout=3000)
            elements = page.locator(".model-title-text").all()
            models = list(dict.fromkeys([t.inner_text().strip() for t in elements if t.inner_text().strip()]))
            
            page.keyboard.press("Escape")
            return models
        except Exception as e:
            page.keyboard.press("Escape")
            raise e

    def _internal_set_model(self, page, model_name):
        """Selects a specific model."""
        print(f"   [Thread] Switching to model: {model_name}...")
        
        # --- FIX: Ensure Navigation ---
        if "aistudio.google.com" not in page.url:
             print("   [Thread] Page is blank or external. Navigating to AI Studio...")
             page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=60000)

        try:
            page.locator("ms-model-selector button").wait_for(state="visible", timeout=30000)

            # 1. Open Menu
            model_btn = page.locator("ms-model-selector button")
            if not model_btn.is_visible():
                page.get_by_label("Run settings").click()
                time.sleep(0.5)
            
            model_btn.click()
            time.sleep(1.0)

            # 2. Click "Gemini" Filter
            try:
                gemini_filter = page.locator("button.ms-button-filter-chip").filter(has_text="Gemini").first
                if gemini_filter.is_visible():
                    gemini_filter.click()
                    time.sleep(0.5)
            except: pass

            # 3. Click the model
            target = page.locator(".model-title-text").get_by_text(model_name, exact=True).first
            target.click()
            
            time.sleep(1.0)
            return True
        except Exception as e:
            page.keyboard.press("Escape")
            raise e

    def send_prompt(self, message):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("prompt", message, result_queue))
        try:
            return result_queue.get(timeout=160)
        except queue.Empty:
            return "Error: Browser bridge timed out."

    def get_available_models(self):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("get_models", None, result_queue))
        try:
            return result_queue.get(timeout=60) # Increased timeout for initial nav
        except queue.Empty:
            return "Bridge Error: Timeout fetching models."

    def set_model(self, model_name):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("set_model", model_name, result_queue))
        try:
            return result_queue.get(timeout=60)
        except queue.Empty:
            return "Bridge Error: Timeout setting model."

    def reset(self):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("reset", None, result_queue))
        result_queue.get()

browser_bridge = AIStudioBridge()