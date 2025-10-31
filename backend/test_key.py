import os
import google.generativeai as genai
from dotenv import load_dotenv

print("--- Starting API Key Test ---")

# 1. Load the .env file
load_dotenv()
print("Attempted to load variables from .env file.")

# 2. Get the API key from the environment
api_key = os.getenv("GEMINI_API_KEY")

# 3. Check if the key was loaded
if api_key:
    # Print a portion of the key to confirm it's loaded, but not the whole thing for security
    print(f"✅ Key Loaded Successfully! Starts with: '{api_key[:4]}...'") 
else:
    print("❌ CRITICAL FAILURE: os.getenv('GEMINI_API_KEY') returned None.")
    print("   Check your .env file's name, location, and content.")
    exit() # Stop the script if key is not found

# 4. Try to configure the genai library
try:
    genai.configure(api_key=api_key)
    print("✅ genai.configure() was successful.")
except Exception as e:
    print(f"❌ FAILED during genai.configure(): {e}")
    exit()

# 5. Make a simple, lightweight API call to verify authentication
try:
    print("Attempting to list models to verify the key is valid...")
    for m in genai.list_models():
        # We only need to check if one of the models has this property to know it worked
        if 'generateContent' in m.supported_generation_methods:
            print(f"Found a model: {m.name}")
            break
    print("✅ API Key is VALID and authenticated successfully!")
    print("--- Test Complete ---")
except Exception as e:
    print(f"❌ FAILED to authenticate with Google API: {e}")
    print("   This likely means your API key is incorrect, disabled, or has restrictions.")
    print("--- Test Complete ---")