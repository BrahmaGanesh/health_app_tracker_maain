from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required

from utils.gemini_ai import ask_gemini

ai_bp = Blueprint("ai", __name__)


@ai_bp.route("/chat", methods=["POST"])
@jwt_required()
def chat():

    data = request.get_json()

    message = data.get("message", "")

    history = data.get("history", [])

    result = ask_gemini(message, history)

    return jsonify({
        "success": result["success"],
        "message": "Success",
        "data": {
            "reply": result["reply"]
        }
    })