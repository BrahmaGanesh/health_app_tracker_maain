from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from utils.gemini_ai import ask_gemini

ai_bp = Blueprint("ai", __name__)


@ai_bp.route("/chat", methods=["POST"])
@jwt_required()
def chat():
    print("\n========== AI ROUTE CALLED ==========")

    try:
        user = get_current_user()

        print(f"User ID: {user.id}")

        data = request.get_json(silent=True) or {}

        message = data.get("message", "").strip()
        history = data.get("history", [])

        print("Message:", message)
        print("History Count:", len(history))

        if not message:
            return jsonify({
                "success": False,
                "message": "Message required",
                "data": None
            }), 400

        print("Calling ask_gemini()...")

        result = ask_gemini(
            message=message,
            user=user,
            history=history
        )

        print("ask_gemini() returned:")
        print(result)

        return jsonify({
            "success": result.get("success", False),
            "message": "Success" if result.get("success") else "AI Error",
            "data": {
                "reply": result.get("reply", "")
            }
        }), 200 if result.get("success") else 500

    except Exception as e:
        import traceback

        print("\n========== AI ROUTE ERROR ==========")
        traceback.print_exc()
        print("Exception:", repr(e))
        print("====================================\n")

        return jsonify({
            "success": False,
            "message": "Internal Server Error",
            "data": {
                "reply": str(e)
            }
        }), 500