print("######## GEMINI FILE LOADED ########")

import os
import traceback
import google.generativeai as genai

# ======================================================
# Configure Gemini
# ======================================================

api_key = os.getenv("GEMINI_API_KEY")

if api_key:
    genai.configure(api_key=api_key)
    print("[OK] GEMINI_API_KEY FOUND")
    print("API Key Prefix:", api_key[:10] + "...")
else:
    print("[WARN] GEMINI_API_KEY NOT FOUND")
    print("[INFO] AI features will be limited until API key is configured")
    print("[INFO] Configure GEMINI_API_KEY in .env to enable AI features")

# Don't raise an error - let the app start without AI
# The AI features will be gracefully disabled

# ======================================================
# Model
# ======================================================

MODEL_NAME = "gemini-flash-latest"

# Initialize model lazily to avoid errors during import
model = None

def get_model():
    """Get or create the model instance."""
    global model
    if model is None:
        try:
            api_key = os.getenv("GEMINI_API_KEY")
            if api_key:
                model = genai.GenerativeModel(MODEL_NAME)
            else:
                model = None
        except Exception as e:
            print(f"[ERROR] Failed to initialize model: {e}")
            model = None
        return model

# ======================================================
# Ask Gemini
# ======================================================

def ask_gemini(message, user=None, history=None):
    """
    Ask Gemini AI a question and get a response.
    Returns a dict with success, reply, and metadata.
    """

    if not message or not message.strip():
        return {
            "success": False,
            "reply": "Please provide a message.",
            "error": "Empty message"
        }

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        return {
            "success": False,
            "reply": "AI features are not configured. Please set GEMINI_API_KEY in your .env file.",
            "error": "API key not configured"
        }

    try:
        genai.configure(api_key=api_key)
        model = genai.GenerativeModel(MODEL_NAME)

        # Build context from user info and history
        context = ""
        if user:
            context = f"User: {user.get('name', 'User')}\n"
            if user.get('health_profile'):
                hp = user.get('health_profile', {})
                if hp.get('current_weight_kg'):
                    context += f"Weight: {hp['current_weight_kg']} kg\n"
                if hp.get('height_cm'):
                    context += f"Height: {hp['height_cm']} cm\n"
                if hp.get('age'):
                    context += f"Age: {hp['age']}\n"
                if hp.get('conditions'):
                    context += f"Conditions: {', '.join(hp['conditions'])}\n"

        # Build history context
        history_context = ""
        if history:
            for msg in history[-5:]:  # Last 5 messages
                role = msg.get('role', 'user')
                content = msg.get('content', '')
                history_context += f"{role}: {content}\n"

        # Build prompt
        prompt = f"""You are HealthTrack AI, a health and wellness assistant.
Provide helpful, accurate, and concise responses about health and wellness topics.
Keep responses concise (2-3 sentences typically).
For medical advice, always recommend consulting a healthcare professional.

{context}
{history_context}

User: {message}

HealthTrack AI:"""

        try:
            genai.configure(api_key=api_key)
            model = genai.GenerativeModel(MODEL_NAME)

            response = model.generate_content(prompt)

            text = getattr(response, 'text', None)

            if text:
                return {
                    "success": True,
                    "reply": text,
                    "error": None
                }
            else:
                return {
                    "success": False,
                    "reply": "I couldn't generate a response. Please try again.",
                    "error": "Empty response from AI"
                }

        except Exception as e:
            traceback.print_exc()
            return {
                "success": False,
                "reply": f"AI service error: {str(e)}",
                "error": str(e)
            }
    except Exception as e:
        traceback.print_exc()
        return {
            "success": False,
            "reply": f"AI service error: {str(e)}",
            "error": str(e)
        }