print("######## GEMINI FILE LOADED ########")

import os
import traceback
import google.generativeai as genai

# ======================================================
# Configure Gemini
# ======================================================

api_key = os.getenv("GEMINI_API_KEY")

if not api_key:
    raise RuntimeError("GEMINI_API_KEY environment variable is not set.")

genai.configure(api_key=api_key)

print("=" * 50)
print("Gemini API key loaded successfully.")
print("=" * 50)

model = genai.GenerativeModel("gemini-flash-latest")


# ======================================================
# Ask Gemini
# ======================================================

def ask_gemini(message, user=None, history=None):
    print(">>>>>>>> ask_gemini() CALLED <<<<<<<<")
    try:

        print("\n========== GEMINI REQUEST ==========")
        print("User Message:", message)

        # ---------------------------------------------
        # User Context
        # ---------------------------------------------
        user_context = ""

        if user and getattr(user, "health_profile", None):
            user_context = f"""
User Health Profile:
- Weight: {user.health_profile.current_weight_kg} kg
- Height: {user.health_profile.height_cm} cm
- BMI: {user.bmi}
"""

        # ---------------------------------------------
        # Conversation History
        # ---------------------------------------------
        history_context = ""

        if history:
            history_context = "\n".join(
                [
                    f"{'User' if h.get('role') == 'user' else 'Assistant'}: {h.get('content','')}"
                    for h in history[-5:]
                ]
            )

        # ---------------------------------------------
        # Prompt
        # ---------------------------------------------
        prompt = f"""
You are HealthTrack AI.

You answer ONLY health, fitness, nutrition and wellness questions.

Keep replies between 2 and 4 sentences.

If someone asks unrelated questions, politely refuse.

{user_context}

Conversation History:
{history_context}

User:
{message}

HealthTrack AI:
"""

        print("Calling Gemini API...")

        # ---------------------------------------------
        # Gemini Call
        # ---------------------------------------------
        response = model.generate_content(prompt)

        print("Gemini call completed.")

        print("Response object:", response)

        print("Response text:")
        print(response.text)

        print("=====================================\n")

        return {
            "success": True,
            "reply": response.text
        }

    except Exception as e:

        print("\n========== GEMINI ERROR ==========")
        traceback.print_exc()
        print("Exception Type:", type(e).__name__)
        print("Exception:", str(e))
        print("==================================\n")

        return {
            "success": False,
            "reply": str(e)
        }