import os
import google.generativeai as genai

genai.configure(
    api_key=os.getenv("ANTHROPIC_API_KEY")
)

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
        return {
            "success": False,
            "reply": str(e)
        }