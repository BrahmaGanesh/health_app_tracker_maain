# routes/api/medicine_api.py — Complete Medicine Module API
import json
from datetime import date, datetime, timedelta
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from models import User, now_ist, today_ist
from models import Medicine, MedicineLog, UserSubscription
from utils.firebase_push import send_push_to_user

medicine_api_bp = Blueprint("medicine_api", __name__)


# ── Plan helpers ───────────────────────────────────────────────────
def _plan(uid):
    sub_list = UserSubscription.get_all(filters={"user_id": uid}, limit=1)
    sub = sub_list[0] if sub_list else None
    return (sub.plan if sub and sub.is_active else "free")


def _med_limit(uid):
    return Medicine.PLAN_LIMITS.get(_plan(uid), 2)


def _is_premium(uid):
    return _plan(uid) in ("premium", "family")


def _is_family_plan(uid):
    return _plan(uid) == "family"


# ════════════════════════════════════════════════════════════════
# DASHBOARD STATS
# ════════════════════════════════════════════════════════════════

@medicine_api_bp.route("/dashboard", methods=["GET"])
@jwt_required()
def medicine_dashboard():
    uid = get_jwt_identity()
    today = today_ist()
    meds = Medicine.get_all(filters={"user_id": uid, "is_active": True})
    plan = _plan(uid)
    limit = _med_limit(uid)

    logs = MedicineLog.get_all(filters={"user_id": uid, "log_date": today_ist()})

    taken = [l for l in logs if l.status in ("taken", "ai_verified")]
    missed = [l for l in logs if l.status == "missed"]
    skipped = [l for l in logs if l.status == "skipped"]
    pct = round(len(taken) / len(logs) * 100, 1) if logs else 0

    return jsonify({"success": True, "data": {
        "logs": [l.to_dict() for l in logs],
        "adherence_pct": pct,
        "taken_count": len(taken),
        "missed_count": len(missed),
        "skipped_count": len(skipped),
        "calendar": [{"date": str(l.log_date), "status": l.status, "emoji": l.STATUS_EMOJI.get(l.status, "🟡")} for l in logs],
    }})


@medicine_api_bp.route("/<int:mid>/history", methods=["GET"])
@jwt_required()
def medicine_history(mid):
    """Alias for /adherence endpoint for backward compatibility."""
    return medicine_adherence(mid)


@medicine_api_bp.route("/<int:mid>/stock", methods=["POST"])
@jwt_required()
def update_stock(mid):
    uid = get_jwt_identity()
    med = Medicine.get_by_id_or_404(mid)
    if med.user_id != get_jwt_identity():
        return jsonify({"success": False, "message": "Forbidden"}), 403

    d = request.get_json() or {}
    med.stock_count = int(d.get("stock_count", med.stock_count))
    med.save()
    return jsonify({"success": True, "message": f"📦 Stock updated to {med.stock_count}", "data": med.to_dict()})


# ════════════════════════════════════════════════════════════════
# SETTINGS
# ════════════════════════════════════════════════════════════════

@medicine_api_bp.route("/settings", methods=["GET", "POST"])
@jwt_required()
def medicine_settings():
    """Global medicine notification + stock settings."""
    from models import UserSettings
    uid = get_jwt_identity()

    if request.method == "GET":
        settings = UserSettings.get_one(filters={"user_id": get_jwt_identity()})
        return jsonify({"success": True, "data": settings.to_dict() if settings else {}})

    data = request.get_json() or {}
    settings = UserSettings.get_one(filters={"user_id": get_jwt_identity()})
    if not settings:
        settings = UserSettings(user_id=get_jwt_identity())

    settings.medicine_reminders_enabled = data.get("medicine_reminders_enabled", True)
    settings.medicine_reminder_time = data.get("medicine_reminder_time", "08:00")
    settings.stock_alerts_enabled = data.get("stock_alerts_enabled", True)
    settings.stock_alert_threshold = data.get("stock_alert_threshold", 5)
    settings.save()
    return jsonify({"success": True, "message": "Settings saved"})