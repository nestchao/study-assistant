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
                    viewport={'width': 1100, 'height': 800}, # Slightly taller for upload dialogs
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
                # Disable webdriver property to prevent detection
                page.add_init_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
                
                # Navigate initially
                try:
                    page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=60000)
                except:
                    pass

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
                        # --- NEW COMMAND ---
                        elif cmd_type == "upload_extract":
                            text = self._internal_upload_and_extract(page, data)
                            result_queue.put(text)
                    except Exception as e:
                        result_queue.put(f"Bridge Error: {str(e)}")
                    finally:
                        self.cmd_queue.task_done()
        except Exception as e:
            print(f"❌ [Thread] CRITICAL BRIDGE FAILURE: {e}")

    def _internal_upload_and_extract(self, page, file_path):
        """Handles uploading a file and asking for extraction."""
        print(f"   [Thread] Uploading file for extraction: {os.path.basename(file_path)}")
        
        # 1. Reset chat to ensure clean context
        page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=60000)
        
        # 2. Upload Logic
        if not os.path.exists(file_path):
            return "Error: File path does not exist."

        try:
            # Open menu
            page.locator("[data-test-id='add-media-button']").click()
            
            # Click "Upload a file" and handle file chooser
            # Note: The selector might be specifically for the "Upload a file" menu item
            upload_option = page.locator("button.mat-mdc-menu-item").filter(has_text="Upload a file").first
            
            with page.expect_file_chooser() as fc_info:
                upload_option.click()
            
            fc_info.value.set_files(file_path)

            # Wait for file chip to appear (validation)
            filename = os.path.basename(file_path)
            print("   [Thread] Waiting for file chip...")
            # We look for the text of filename inside the attachment area
            page.get_by_text(filename).wait_for(state="visible", timeout=20000)

            # Wait for processing progress bar (if it appears)
            try:
                if page.locator("mat-progress-bar").is_visible(timeout=3000):
                    print("   [Thread] Waiting for Gemini processing...")
                    page.locator("mat-progress-bar").wait_for(state="hidden", timeout=120000)
            except:
                pass # Progress bar might not appear for small files or instant processing

            print("   [Thread] Upload complete. Sending extraction prompt...")
            
            # 3. Send Prompt
            extraction_prompt = "Extract all text from this document verbatim. Preserve original formatting where possible. Do not summarize or add conversational filler. Just output the raw text."
            return self._internal_send_prompt(page, extraction_prompt)

        except Exception as e:
            print(f"   [Thread] Upload Failed: {e}")
            page.keyboard.press("Escape") # Close menu if open
            raise e

    def _internal_send_prompt(self, page, message):
        """Logic executed strictly inside the worker thread."""
        try:
            # Ensure we are on a valid page (if not already there)
            if "aistudio.google.com" not in page.url:
                 page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle")

            prompt_box = page.get_by_placeholder("Start typing a prompt")
            prompt_box.wait_for(state="visible", timeout=30000)
            time.sleep(1)

            # Inject text (safer than typing for long prompts)
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

            try:
                prompt_box.focus()
            except:
                pass
            
            page.keyboard.press("Enter")

            time.sleep(1.0)
            run_btn = page.locator('ms-run-button button[aria-label="Run"]')
            if run_btn.is_visible():
                print("   [Thread] 'Enter' ignored. Clicking Run button manually...", end=" ")
                try:
                    run_btn.click()
                except Exception as click_err:
                    print(f"(Click failed: {click_err})", end=" ")

            print("   [Thread] Waiting for AI response...", end="", flush=True)

            start_time = time.time()
            last_len = 0
            stable_count = 0

            while True:
                if time.time() - start_time > 240: # Extended timeout for long PDF extractions
                    return "Error: Timeout waiting for response."

                # Scroll to bottom to ensure generation continues
                page.evaluate("window.scrollTo(0, document.body.scrollHeight)")

                run_btn = page.locator('ms-run-button button[aria-label="Run"]')
                is_run_visible = run_btn.is_visible()
                
                chunks = page.locator('ms-text-chunk').all()
                current_count = len(chunks)
                
                # Check if text is growing
                current_text = chunks[-1].inner_text().strip() if chunks else ""
                current_len = len(current_text)

                print(".", end="", flush=True)

                if not is_busy(page, run_btn) and current_len > 0:
                    if current_len == last_len:
                        stable_count += 1
                        if stable_count >= 4: # Wait a bit longer for stability
                            break
                    else:
                        stable_count = 0
                else:
                    stable_count = 0
                
                last_len = current_len
                time.sleep(1)

            print("\n   [Thread] Captured.")

            final_chunks = page.locator('ms-text-chunk').all()
            if not final_chunks: return ""
            
            raw_answer = final_chunks[-1].inner_text()
            
            # Clean up UI artifacts
            if "Expand to view model thoughts" in raw_answer:
                raw_answer = raw_answer.split("Expand to view model thoughts")[-1]

            return clean_response(raw_answer)

        except Exception as e:
            return f"Browser Error: {str(e)}"

    def _internal_get_models(self, page):
        # ... (Same as your original code) ...
        try:
            page.locator("ms-model-selector button").wait_for(state="visible", timeout=10000)
            model_btn = page.locator("ms-model-selector button")
            if not model_btn.is_visible():
                page.get_by_label("Run settings").click()
                time.sleep(0.5)
            model_btn.click()
            time.sleep(1.0)
            try:
                gemini_filter = page.locator("button.ms-button-filter-chip").filter(has_text="Gemini").first
                if gemini_filter.is_visible():
                    gemini_filter.click()
                    time.sleep(0.5)
            except: pass 
            page.locator(".model-title-text").first.wait_for(timeout=3000)
            elements = page.locator(".model-title-text").all()
            models = list(dict.fromkeys([t.inner_text().strip() for t in elements if t.inner_text().strip()]))
            page.keyboard.press("Escape")
            return models
        except:
            page.keyboard.press("Escape")
            return []

    def _internal_set_model(self, page, model_name):
        # ... (Same as your original code) ...
        try:
            page.locator("ms-model-selector button").wait_for(state="visible", timeout=10000)
            model_btn = page.locator("ms-model-selector button")
            if not model_btn.is_visible():
                page.get_by_label("Run settings").click()
                time.sleep(0.5)
            model_btn.click()
            time.sleep(1.0)
            try:
                gemini_filter = page.locator("button.ms-button-filter-chip").filter(has_text="Gemini").first
                if gemini_filter.is_visible():
                    gemini_filter.click()
                    time.sleep(0.5)
            except: pass
            target = page.locator(".model-title-text").get_by_text(model_name, exact=True).first
            target.click()
            time.sleep(1.0)
            return True
        except Exception as e:
            page.keyboard.press("Escape")
            raise e

    # --- Public API ---

    def send_prompt(self, message):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("prompt", message, result_queue))
        try:
            return result_queue.get(timeout=300) # Long timeout
        except queue.Empty:
            return "Error: Browser bridge timed out."

    def upload_and_extract(self, file_path):
        """Uploads a file and returns the extracted text."""
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("upload_extract", file_path, result_queue))
        try:
            # Very long timeout for upload + processing + generation
            return result_queue.get(timeout=600) 
        except queue.Empty:
            return "Error: Browser bridge timed out during extraction."

    def get_available_models(self):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("get_models", None, result_queue))
        try: return result_queue.get(timeout=60)
        except: return []

    def set_model(self, model_name):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("set_model", model_name, result_queue))
        try: return result_queue.get(timeout=60)
        except: return False

# Helpers
def is_busy(page, run_btn):
    return not run_btn.is_visible()

def clean_response(text):
    text = re.sub(r'```[a-zA-Z]*\n?', '', text)
    text = text.replace('`', '')
    ui_keywords = ["expand_more", "expand_less", "content_copy", "share", "edit", "thumb_up", "thumb_down"]
    junk_pattern = r'\s*(' + '|'.join(ui_keywords) + r')\s*'
    text = re.sub(junk_pattern, '\n', text).strip()
    return re.sub(r'\n\s*\n', '\n\n', text).strip()

browser_bridge = AIStudioBridge()