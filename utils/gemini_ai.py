import os
import google.generativeai as genai

api_key = os.getenv("ANTHROPIC_API_KEY")

genai.configure(api_key=api_key)

print("=" * 50)
print("GEMINI KEY FOUND:", api_key is not None)
print("KEY LENGTH:", len(api_key) if api_key else 0)
print("=" * 50)

model = genai.GenerativeModel("gemini-2.5-flash")


def ask_gemini(message, history=None):
    try:

        prompt = """
You are HealthTrack AI.

Rules:

- Answer only health, nutrition, exercise and wellness questions.

- Never diagnose diseases.

- Never prescribe medicine.

- Always recommend seeing a doctor for emergencies.

User:

""" + message

        response = model.generate_content(prompt)

        return {
            "success": True,
            "reply": response.text
        }

    except Exception as e:
        import traceback
        traceback.print_exc()

        return {
            "success": False,
            "reply": str(e)
        }