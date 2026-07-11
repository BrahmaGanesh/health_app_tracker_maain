from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_current_user
import traceback

from utils.gemini_ai import ask_gemini

ai_bp = Blueprint("ai", __name__)


@ai_bp.route("/chat", methods=["POST"])
@jwt_required()
def chat():

    print("\n" + "=" * 80)
    print("AI CHAT ROUTE CALLED")
    print("=" * 80)

    try:

        # ---------------------------------------------------
        # Current User
        # ---------------------------------------------------

        user = get_current_user()

        if user:
            print(f"User ID: {user.id}")
        else:
            print("User object is None")

        # ---------------------------------------------------
        # Request Body
        # ---------------------------------------------------

        data = request.get_json(silent=True) or {}

        print("Incoming JSON:")
        print(data)

        message = str(data.get("message", "")).strip()
        history = data.get("history", [])

        print("Message:", message)
        print("History Count:", len(history))

        if not message:
            return jsonify({
                "success": False,
                "message": "Message required",
                "data": None
            }), 400

        # ---------------------------------------------------
        # Call Gemini
        # ---------------------------------------------------

        print("\nCalling ask_gemini()...\n")

        result = ask_gemini(
            message=message,
            user=user,
            history=history
        )

        print("\nask_gemini() returned:")
        print(result)

        print("=" * 80)

        return jsonify({
            "success": result.get("success", False),
            "message": "Success" if result.get("success") else "AI Error",
            "data": {
                "reply": result.get("reply", "")
            }
        }), 200 if result.get("success") else 500

    except Exception as e:

        print("\n" + "=" * 80)
        print("AI ROUTE EXCEPTION")
        print("=" * 80)

        traceback.print_exc()

        print("Exception Type:", type(e).__name__)
        print("Exception:", str(e))

        print("=" * 80)

        return jsonify({
            "success": False,
            "message": "Internal Server Error",
            "data": {
                "reply": str(e)
            }
        }), 500