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
                    viewport={'width': 1100, 'height': 800},
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
                page.add_init_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
                
                print("✅ [Thread] Browser Ready.")

                while True:
                    task = self.cmd_queue.get()
                    if task is None: break 
                    
                    cmd_type, data, result_queue = task
                    try:
                        if cmd_type == "prompt":
                            # Normal prompt, allow navigation/reset if needed
                            response = self._internal_send_prompt(page, data, skip_nav=False)
                            result_queue.put(response)
                        
                        elif cmd_type == "upload_extract":
                            # data is tuple: (file_path, prompt)
                            file_path, prompt = data
                            response = self._internal_upload_and_extract(page, file_path, prompt)
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
                        print(f"❌ [Thread] Error processing {cmd_type}: {e}")
                        result_queue.put(f"Bridge Error: {str(e)}")
                    finally:
                        self.cmd_queue.task_done()
        except Exception as e:
            print(f"❌ [Thread] CRITICAL BRIDGE FAILURE: {e}")

    def _internal_upload_and_extract(self, page, file_path, prompt):
        """Uploads a file and asks for extraction."""
        print(f"   [Thread] Starting File Extraction: {file_path}")
        
        # 1. Reset Chat first to ensure clean state
        try:
            # We want to start fresh so we don't attach to an old conversation
            if "aistudio.google.com" not in page.url:
                 page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=60000)
            else:
                 # Check if the "New chat" button is visible and click it, otherwise reload
                 # This is safer than just reloading if the URL is generic
                 page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle")
        except:
            pass

        # 2. Upload Logic
        if not os.path.exists(file_path):
            return "Error: File not found on server."

        try:
            filename = os.path.basename(file_path)
            
            # Open Add Media Menu
            add_btn = page.locator("[data-test-id='add-media-button']")
            add_btn.wait_for(state="visible", timeout=20000)
            add_btn.click()
            time.sleep(0.5)
            
            # Handle File Chooser
            upload_option = page.locator("button.mat-mdc-menu-item").filter(has_text="Upload a file")
            
            with page.expect_file_chooser() as fc_info:
                if upload_option.is_visible():
                    upload_option.click()
                else:
                    # Fallback logic
                    page.keyboard.press("Escape")
                    raise Exception("Upload menu option not found")
            
            fc_info.value.set_files(file_path)

            print(f"   [Thread] File '{filename}' selected. Waiting for attachment...")

            # 3. Wait for file chip to appear
            try:
                page.get_by_text(filename).wait_for(state="visible", timeout=40000)
            except:
                print("   [Thread] Warning: Filename chip not detected within timeout. Proceeding anyway...")

            # 4. Wait for processing bar (Tokenizing)
            time.sleep(1) 
            try:
                if page.locator("mat-progress-bar").is_visible():
                    print("   [Thread] Processing bar detected. Waiting...")
                    page.locator("mat-progress-bar").wait_for(state="hidden", timeout=120000)
            except:
                pass

            print("   [Thread] File attached. Sending prompt...")
            
            # 5. Send Prompt with SKIP NAV enabled so we don't refresh the page
            return self._internal_send_prompt(page, prompt, skip_nav=True)

        except Exception as e:
            page.keyboard.press("Escape")
            return f"Upload/Extract Failed: {str(e)}"

    def _internal_send_prompt(self, page, message, skip_nav=False):
        """Logic executed strictly inside the worker thread."""
        try:
            # Navigation logic depends on whether we are continuing a flow (file upload) or starting new
            if not skip_nav:
                if "aistudio.google.com" not in page.url:
                     page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=60000)

            # Ensure prompt box is ready
            prompt_box = page.get_by_placeholder("Start typing a prompt")
            prompt_box.wait_for(state="visible", timeout=30000)
            time.sleep(0.5)

            # Inject text
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

            time.sleep(1.0)
            
            # Press Enter to send
            # page.keyboard.press("Enter")
            
            # Fallback: Click "Run" button if Enter didn't work (sometimes focus issues)
            # The "Run" button usually has aria-label="Run"
            run_btn = page.locator('ms-run-button button[aria-label="Run"]')
            if run_btn.is_visible():
                 # If run button is still visible 1s after pressing enter, click it
                 time.sleep(1)
                 if run_btn.is_visible():
                     print("   [Thread] 'Enter' didn't trigger run. Clicking Run button...")
                     run_btn.click()

            print("   [Thread] Waiting for AI response...", end="", flush=True)

            start_time = time.time()
            last_len = 0
            stable_count = 0

            while True:
                if time.time() - start_time > 240: # Extended timeout
                    return "Error: Timeout waiting for response."

                # Keep scrolling to trigger lazy load if needed
                page.evaluate("window.scrollTo(0, document.body.scrollHeight)")

                current_chunks = page.locator('ms-text-chunk').all()
                run_btn = page.locator('ms-run-button button[aria-label="Run"]')
                
                # Check busy state
                is_run_visible = run_btn.is_visible()
                stop_btn = page.get_by_label("Stop message")
                is_stopping = stop_btn.is_visible()

                current_text = current_chunks[-1].inner_text().strip() if current_chunks else ""
                current_len = len(current_text)

                print(".", end="", flush=True)

                # Heuristic: If Run button is visible AND stop button is NOT visible AND we have text
                if is_run_visible and not is_stopping and current_len > 0:
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
            if not final_chunks: return "Error: No response chunks found."
            
            raw_answer = final_chunks[-1].inner_text()

            # Cleanup
            clean_answer = raw_answer
            if "Expand to view model thoughts" in clean_answer:
                clean_answer = clean_answer.split("Expand to view model thoughts")[-1]

            ui_keywords = ["expand_more", "expand_less", "content_copy", "share", "edit", "thumb_up", "thumb_down"]
            for junk in ui_keywords:
                clean_answer = clean_answer.replace(junk, "")

            return clean_answer.strip()

        except Exception as e:
            return f"Browser Error: {str(e)}"

    def _internal_get_models(self, page):
        """Scrapes available Gemini models from the UI."""
        print("   [Thread] Fetching models...")
        if "aistudio.google.com" not in page.url:
             page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=60000)

        try:
            page.locator("ms-model-selector button").wait_for(state="visible", timeout=30000)
            model_btn = page.locator("ms-model-selector button")
            if not model_btn.is_visible():
                page.get_by_label("Run settings").click()
                time.sleep(0.5)
            model_btn.click()
            time.sleep(1.0)
            try:
                gemini_filter = page.locator("button.ms-button-filter-chip").filter(has_text="Gemini").first
                if gemini_filter.is_visible(): gemini_filter.click()
                time.sleep(0.5)
            except: pass 

            page.locator(".model-title-text").first.wait_for(timeout=3000)
            elements = page.locator(".model-title-text").all()
            models = list(dict.fromkeys([t.inner_text().strip() for t in elements if t.inner_text().strip()]))
            page.keyboard.press("Escape")
            return models
        except Exception as e:
            page.keyboard.press("Escape")
            return []

    def _internal_set_model(self, page, model_name):
        """Selects a specific model."""
        print(f"   [Thread] Switching to model: {model_name}...")
        if "aistudio.google.com" not in page.url:
             page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=60000)

        try:
            page.locator("ms-model-selector button").wait_for(state="visible", timeout=30000)
            model_btn = page.locator("ms-model-selector button")
            if not model_btn.is_visible():
                page.get_by_label("Run settings").click()
                time.sleep(0.5)
            model_btn.click()
            time.sleep(1.0)
            try:
                gemini_filter = page.locator("button.ms-button-filter-chip").filter(has_text="Gemini").first
                if gemini_filter.is_visible(): gemini_filter.click()
                time.sleep(0.5)
            except: pass

            target = page.locator(".model-title-text").get_by_text(model_name, exact=True).first
            target.click()
            time.sleep(1.0)
            return True
        except Exception as e:
            page.keyboard.press("Escape")
            return f"Error: {e}"

    def send_prompt(self, message):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("prompt", message, result_queue))
        try:
            return result_queue.get(timeout=250)
        except queue.Empty:
            return "Error: Browser bridge timed out."
    
    def extract_text_from_file(self, file_path):
        """Uploads a file and extracts text using the browser."""
        self.start()
        result_queue = queue.Queue()
        prompt = "Extract all text content from the attached file verbatim. Do not summarize. Do not add markdown unless it is in the source. Just output the raw text."
        
        self.cmd_queue.put(("upload_extract", (file_path, prompt), result_queue))
        try:
            return result_queue.get(timeout=300) 
        except queue.Empty:
            return "Error: Browser bridge timed out during extraction."

    def get_available_models(self):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("get_models", None, result_queue))
        try:
            return result_queue.get(timeout=60)
        except queue.Empty:
            return ["Error fetching"]

    def set_model(self, model_name):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("set_model", model_name, result_queue))
        try:
            return result_queue.get(timeout=60)
        except queue.Empty:
            return "Timeout"

    def reset(self):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("reset", None, result_queue))
        result_queue.get()

browser_bridge = AIStudioBridge()