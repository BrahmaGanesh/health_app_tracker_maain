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


def ask_gemini(message, user=None, history=None):
    try:
        # Build personalized context
        user_context = ""
        if user and user.health_profile:
            user_context = f"""
User Health Profile:
- Weight: {user.health_profile.current_weight_kg} kg
- Height: {user.health_profile.height_cm} cm
- BMI: {user.bmi}
"""
        
        # Build conversation history
        history_context = ""
        if history and len(history) > 0:
            history_context = "\n".join([
                f"{'User' if h.get('role')=='user' else 'Assistant'}: {h.get('content', '')}"
                for h in history[-5:]  # Last 5 messages
            ])
        
        prompt = f"""
You are HealthTrack AI, a health assistant for an Indian user.

Answer ONLY health, nutrition, fitness, and wellness questions.
Keep responses concise (2-4 sentences).
Use metric units (kg, cm, mg/dL).
If asked about non-health topics, politely decline.

{user_context}

Conversation History:
{history_context}

User: {message}

HealthTrack AI:
"""
        
        # ✅ Use correct SDK call
        response = model.generate_content(prompt)
        
        print("Gemini Response:", response.text[:200])
        
        return {
            "success": True,
            "reply": response.text
        }
        
    except Exception as e:
        print("Gemini Error:", str(e))
        return {
            "success": False,
            "reply": f"AI service unavailable: {str(e)}"
        }