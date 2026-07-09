print("######## GEMINI FILE LOADED ########")
import os
import google.generativeai as genai

api_key = os.getenv("ANTHROPIC_API_KEY")

print("Gemini Key Loaded:", bool(api_key))

genai.configure(api_key=api_key)
print("=" * 50)
print("GEMINI KEY:", os.getenv("ANTHROPIC_API_KEY"))
print("=" * 50)

model = genai.GenerativeModel("gemini-1.5-flash")


def ask_gemini(message, history=None):
    try:
        prompt = f"""
You are HealthTrack AI.

Answer only health, nutrition, fitness and wellness questions.

User:
{message}
"""

        response = model.generate_content(prompt)

        print("Gemini Response:", response.text)

        return {
            "success": True,
            "reply": response.text
        }

    except Exception as e:
        print("Gemini Error:", str(e))

        return {
            "success": False,
            "reply": str(e)
        }