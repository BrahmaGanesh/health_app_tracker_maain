from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from utils.gemini_ai import ask_gemini


ai_bp = Blueprint("ai", __name__)


@ai_bp.route("/chat", methods=["POST"])
@jwt_required()
def chat():
    print("===== AI ROUTE CALLED =====")
    
    user = get_current_user()  # ✅ Get user for personalized context
    data = request.get_json() or {}
    message = data.get("message", "")
    history = data.get("history", [])  # ✅ Extract history from request
    
    if not message:
        return jsonify({
            "success": False,
            "message": "Message required",
            "data": None
        }), 400
    
    print(f"User {user.id} asked: {message}")
    
    # ✅ Pass user context to Gemini
    result = ask_gemini(message, user=user, history=history)
    
    print(f"AI Response: {result}")
    
    status_code = 200 if result["success"] else 500
    
    return jsonify({
        "success": result["success"],
        "message": "Success" if result["success"] else "AI Error",
        "data": {
            "reply": result["reply"]
        }
    }), status_code