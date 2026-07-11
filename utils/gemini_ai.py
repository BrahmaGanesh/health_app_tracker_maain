print("######## GEMINI FILE LOADED ########")

import os
import traceback
import google.generativeai as genai

# ======================================================
# Configure Gemini
# ======================================================

api_key = os.getenv("GEMINI_API_KEY")

print("=" * 60)
print("Checking Gemini configuration...")

if api_key:
    print("✅ GEMINI_API_KEY FOUND")
    print("API Key Prefix:", api_key[:10] + "...")
else:
    print("❌ GEMINI_API_KEY NOT FOUND")
    raise RuntimeError("GEMINI_API_KEY environment variable is not set.")

genai.configure(api_key=api_key)

print("✅ Gemini configured successfully")
print("=" * 60)

# ======================================================
# Model
# ======================================================

MODEL_NAME = "gemini-flash-latest"

print(f"Loading Gemini model: {MODEL_NAME}")

model = genai.GenerativeModel(MODEL_NAME)

print("✅ Gemini model loaded")
print("=" * 60)


# ======================================================
# Ask Gemini
# ======================================================

def ask_gemini(message, user=None, history=None):

    print("\n")
    print("=" * 80)
    print("ask_gemini() CALLED")
    print("=" * 80)

    try:

        print("Incoming message:")
        print(message)

        print("-" * 80)

        # ------------------------------------------------
        # User Context
        # ------------------------------------------------

        user_context = ""

        if user:

            print("User ID:", getattr(user, "id", None))

            hp = getattr(user, "health_profile", None)

            if hp:

                print("Health profile found.")

                user_context = f"""
User Health Profile:
Weight: {hp.current_weight_kg} kg
Height: {hp.height_cm} cm
BMI: {user.bmi}
"""

            else:

                print("No health profile.")

        else:

            print("No user object received.")

        # ------------------------------------------------
        # History
        # ------------------------------------------------

        history_context = ""

        if history:

            print("History messages:", len(history))

            history_context = "\n".join(

                [
                    f"{'User' if h.get('role')=='user' else 'Assistant'}: {h.get('content','')}"
                    for h in history[-5:]
                ]

            )

        else:

            print("No history received.")

        # ------------------------------------------------
        # Prompt
        # ------------------------------------------------

        prompt = f"""
You are HealthTrack AI.

You answer ONLY health, nutrition, fitness and wellness questions.

Reply in short (2-4 sentences).

If the user asks unrelated questions politely refuse.

{user_context}

Conversation History:

{history_context}

User:
{message}

HealthTrack AI:
"""

        print("-" * 80)
        print("Calling Gemini...")
        print("-" * 80)

        response = model.generate_content(prompt)

        print("Gemini call SUCCESS")

        print("-" * 80)
        print("RAW RESPONSE")
        print(response)
        print("-" * 80)

        text = getattr(response, "text", None)

        if not text:

            print("❌ response.text is empty")

            print("Candidates:", getattr(response, "candidates", None))

            return {
                "success": False,
                "reply": "Gemini returned an empty response."
            }

        print("Response Length:", len(text))
        print(text)

        print("=" * 80)

        return {
            "success": True,
            "reply": text
        }

    except Exception as e:

        print("=" * 80)
        print("GEMINI EXCEPTION")
        print("=" * 80)

        traceback.print_exc()

        print("-" * 80)
        print("Exception Type:", type(e).__name__)
        print("Exception:", str(e))
        print("-" * 80)

        return {
            "success": False,
            "reply": str(e)
        }