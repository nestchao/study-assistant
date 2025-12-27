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
                    headless=False,  # Keep False to avoid bot detection, but optimized
                    
                    # --- RAM & CPU OPTIMIZATIONS ---
                    viewport={'width': 800, 'height': 600}, # Smaller viewport = less RAM
                    ignore_default_args=["--enable-automation"],
                    args=[
                        "--start-maximized", 
                        "--disable-blink-features=AutomationControlled",
                        "--disable-gpu",              # 1. Disable GPU (huge RAM saver)
                        "--disable-dev-shm-usage",     # 2. Prevent crashes in low memory
                        "--no-sandbox",                # 3. Stability
                        "--js-flags='--max-old-space-size=512'" # 4. Limit JS memory usage
                    ]
                )
                
                page = context.pages[0]
                # Disable background images/animations to save more RAM
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
                    except Exception as e:
                        result_queue.put(f"Bridge Error: {str(e)}")
                    finally:
                        self.cmd_queue.task_done()
        except Exception as e:
            print(f"❌ [Thread] CRITICAL BRIDGE FAILURE: {e}")

    def _internal_send_prompt(self, page, message):
        """Logic executed strictly inside the worker thread."""
        try:
            # 1. Navigating with a longer timeout for heavy loads
            print(f"   [Thread] Navigating to New Chat...")
            page.goto("https://aistudio.google.com/app/prompts/new_chat", wait_until="networkidle", timeout=90000)
            
            prompt_box = page.get_by_placeholder("Start typing a prompt")
            prompt_box.wait_for(state="visible", timeout=30000)
            time.sleep(2) # Extra buffer for scripts to stabilize

            # 2. Inject large prompt via JS (avoids UI hang)
            print(f"   [Thread] Injecting prompt ({len(message)} chars)...")
            # page.evaluate("""
            #     (text) => {
            #         const el = document.querySelector('textarea, [placeholder*="Start typing"]');
            #         if (el) {
            #             el.focus();
            #             el.value = text;
            #             el.dispatchEvent(new Event('input', { bubbles: true }));
            #         }
            #     }
            # """, message)

             # --- THE "NO-FREEZE" INJECTION ---
            # print(f"   [Thread] Injecting Large Data...")
            page.evaluate("""
                (text) => {
                    const el = document.querySelector('textarea, [placeholder*="Start typing"]');
                    if (el) {
                        // Set value directly (instant, doesn't lag the UI)
                        el.value = text;
                        // Tell AI Studio that text has changed so it enables the "Run" button
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                        el.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                }
            """, message)

            time.sleep(1.5)
            page.keyboard.press("Enter")
            print("   [Thread] Waiting for AI response...", end="", flush=True)

            # 3. Enhanced Wait & Scroll Loop
            start_time = time.time()
            last_len = 0
            stable_count = 0

            while True:
                if time.time() - start_time > 180: # Extended for huge responses
                    return "Error: Timeout waiting for response."

                # Get bubbles
                current_chunks = page.locator('ms-text-chunk').all()
                current_count = len(current_chunks)
                
                if current_count > 0:
                    # --- NUCLEAR SCROLL SCRIPT ---
                    # This script targets the last message and forces all scrollable parents to the bottom
                    page.evaluate("""
                        () => {
                            const chunks = document.querySelectorAll('ms-text-chunk');
                            if (chunks.length > 0) {
                                const lastChunk = chunks[chunks.length - 1];
                                
                                // 1. Standard scroll
                                lastChunk.scrollIntoView({ block: 'end', behavior: 'instant' });
                                
                                // 2. Force all scrollable parents to the bottom
                                let parent = lastChunk.parentElement;
                                while (parent) {
                                    if (parent.scrollHeight > parent.clientHeight) {
                                        parent.scrollTop = parent.scrollHeight;
                                    }
                                    parent = parent.parentElement;
                                }
                                
                                // 3. Target the specific AI Studio editor container if it exists
                                const editor = document.querySelector('ms-prompt-editor');
                                if (editor) editor.scrollTop = editor.scrollHeight;
                            }
                        }
                    """)

                # Check if AI is finished
                run_btn = page.locator('ms-run-button button[aria-label="Run"]')
                is_run_visible = run_btn.is_visible()

                # It's busy if the Run button is hidden (Stop button is showing)
                # Or if we don't have the AI response bubble yet (min count 2)
                is_busy = not is_run_visible or current_count < 2

                current_text = current_chunks[-1].inner_text().strip() if current_chunks else ""
                current_len = len(current_text)

                print(".", end="", flush=True)

                # Stability Check
                if not is_busy and current_len > 0:
                    if current_len == last_len:
                        stable_count += 1
                        if stable_count >= 3: # Wait 3 seconds of no change
                            break
                    else:
                        stable_count = 0
                else:
                    stable_count = 0
                
                last_len = current_len
                time.sleep(1)

            print("\n   [Thread] Captured.")

            # 4. Extraction
            final_chunks = page.locator('ms-text-chunk').all()
            raw_answer = final_chunks[-1].inner_text()

# 5. Cleaning Logic
            clean_answer = raw_answer
            
            # A. Remove "Model Thoughts" if present
            if "Expand to view model thoughts" in clean_answer:
                clean_answer = clean_answer.split("Expand to view model thoughts")[-1]

            # B. NEW: Remove the "code Markdown" UI labels and separator lines
            # This handles "code", "Markdown", and "code Markdown" labels
            ui_labels = [r'code\s+Markdown', r'^code$', r'^Markdown$', r'^-{3,}']
            for pattern in ui_labels:
                clean_answer = re.sub(pattern, '', clean_answer, flags=re.MULTILINE | re.IGNORECASE)

            # C. Remove Code Markdown Syntax (Triple Backticks)
            clean_answer = re.sub(r'```[a-zA-Z]*\n?', '', clean_answer)
            clean_answer = clean_answer.replace('`', '')

            # D. Remove UI junk icons
            ui_keywords = ["expand_more", "expand_less", "content_copy", "share", "edit", "thumb_up", "thumb_down", "more_vert", "download"]
            junk_pattern = r'\s*(' + '|'.join(ui_keywords) + r')\s*'
            for _ in range(3):
                clean_answer = re.sub(junk_pattern + r'$', '', clean_answer).strip()
                clean_answer = re.sub(junk_pattern, '\n', clean_answer).strip()
            
            # Final trim and whitespace normalization
            return re.sub(r'\n\s*\n', '\n\n', clean_answer).strip()

        except Exception as e:
            return f"Browser Error: {str(e)}"

    def send_prompt(self, message):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("prompt", message, result_queue))
        try:
            return result_queue.get(timeout=160) # Increased timeout
        except queue.Empty:
            return "Error: Browser bridge timed out."

    def reset(self):
        self.start()
        result_queue = queue.Queue()
        self.cmd_queue.put(("reset", None, result_queue))
        result_queue.get()

browser_bridge = AIStudioBridge()