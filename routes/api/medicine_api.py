# routes/api/medicine_api.py — Module 4: Medicine Management API
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from datetime import datetime, date
from extensions import db
from models import now_ist, today_ist
from models_new_modules import Medicine, MedicineLog, TrustedContact
from utils.firebase_push import send_push_to_user

medicine_api_bp = Blueprint("medicine_api", __name__)


# ── GET + POST /medicines/ ────────────────────────────────────────
@medicine_api_bp.route("/", methods=["GET", "POST"])
@jwt_required()
def medicines():
    uid = get_jwt_identity()

    if request.method == "GET":
        member_id = request.args.get("member_id", type=int)
        q = Medicine.query.filter_by(user_id=uid, is_active=True)
        if member_id:
            q = q.filter_by(member_id=member_id)
        meds = q.order_by(Medicine.timing, Medicine.name).all()
        return jsonify({"success": True, "data": {
            "medicines": [m.to_dict() for m in meds],
            "total": len(meds),
            "taken_today": sum(1 for m in meds if m._is_taken_today()),
        }})

    # POST — add medicine
    d = request.get_json() or {}
    if not d.get("name"):
        return jsonify({"success": False, "message": "Medicine name required"}), 400

    med = Medicine(
        user_id=uid,
        name=d["name"].strip(),
        generic_name=d.get("generic_name", "").strip() or None,
        dosage=d.get("dosage", "").strip() or None,
        unit=d.get("unit", "tablet"),
        timing=d.get("timing", "morning"),
        frequency=d.get("frequency", "daily"),
        with_food=d.get("with_food", "doesn't_matter"),
        condition_name=d.get("condition_name", "").strip() or None,
        prescribed_by=d.get("prescribed_by", "").strip() or None,
        stock_count=int(d.get("stock_count", 0)),
        low_stock_alert=int(d.get("low_stock_alert", 5)),
        member_id=d.get("member_id"),
    )
    db.session.add(med)
    db.session.commit()

    # Auto-create a reminder for this medicine
    _create_medicine_reminder(uid, med)

    return jsonify({"success": True, "message": f"💊 {med.name} added", "data": med.to_dict()}), 201


# ── PUT / DELETE /medicines/<id> ──────────────────────────────────
@medicine_api_bp.route("/<int:med_id>", methods=["PUT", "DELETE"])
@jwt_required()
def medicine_detail(med_id):
    uid = get_jwt_identity()
    med = Medicine.query.filter_by(id=med_id, user_id=uid).first_or_404()

    if request.method == "DELETE":
        med.is_active = False
        db.session.commit()
        return jsonify({"success": True, "message": f"💊 {med.name} removed"})

    d = request.get_json() or {}
    for field in ["name", "dosage", "unit", "timing", "frequency", "with_food", "condition_name", "stock_count", "low_stock_alert"]:
        if field in d:
            setattr(med, field, d[field])
    db.session.commit()
    return jsonify({"success": True, "message": "Updated", "data": med.to_dict()})


# ── POST /medicines/<id>/log ──────────────────────────────────────
@medicine_api_bp.route("/<int:med_id>/log", methods=["POST"])
@jwt_required()
def log_medicine(med_id):
    uid = get_jwt_identity()
    med = Medicine.query.filter_by(id=med_id, user_id=uid).first_or_404()
    d   = request.get_json() or {}
    taken = bool(d.get("taken", True))
    today = today_ist()

    log = MedicineLog.query.filter_by(medicine_id=med_id, log_date=today).first()
    if log:
        log.taken = taken
        log.logged_at = now_ist()
    else:
        log = MedicineLog(medicine_id=med_id, log_date=today, taken=taken, logged_at=now_ist())
        db.session.add(log)

    # Decrease stock when taken
    if taken and med.stock_count > 0:
        med.stock_count = max(0, med.stock_count - 1)
        # Low stock alert
        if med.stock_count <= med.low_stock_alert:
            send_push_to_user(uid, f"💊 Low stock: {med.name}",
                              f"Only {med.stock_count} tablets left. Please refill soon.",
                              data={"type": "medicine", "sound": "medicine"})

    db.session.commit()
    return jsonify({"success": True, "message": f"{'✅ Taken' if taken else '⏭ Skipped'}: {med.name}"})


# ── GET /medicines/<id>/adherence ─────────────────────────────────
@medicine_api_bp.route("/<int:med_id>/adherence", methods=["GET"])
@jwt_required()
def medicine_adherence(med_id):
    uid  = get_jwt_identity()
    med  = Medicine.query.filter_by(id=med_id, user_id=uid).first_or_404()
    days = request.args.get("days", 30, type=int)

    from datetime import timedelta
    since = today_ist() - timedelta(days=days)
    logs  = MedicineLog.query.filter(
        MedicineLog.medicine_id == med_id,
        MedicineLog.log_date >= since
    ).all()

    taken  = sum(1 for l in logs if l.taken)
    missed = len(logs) - taken
    pct    = round((taken / len(logs)) * 100, 1) if logs else 0

    return jsonify({"success": True, "data": {
        "medicine": med.name, "days": days,
        "total_logs": len(logs), "taken": taken, "missed": missed,
        "adherence_pct": pct,
        "calendar": [{"date": str(l.log_date), "taken": l.taken} for l in logs],
    }})


# ── POST /medicines/<id>/stock ────────────────────────────────────
@medicine_api_bp.route("/<int:med_id>/stock", methods=["POST"])
@jwt_required()
def update_stock(med_id):
    uid = get_jwt_identity()
    med = Medicine.query.filter_by(id=med_id, user_id=uid).first_or_404()
    d   = request.get_json() or {}
    med.stock_count = int(d.get("stock_count", med.stock_count))
    db.session.commit()
    return jsonify({"success": True, "message": f"📦 Stock updated to {med.stock_count}", "data": {"stock_count": med.stock_count}})


def _create_medicine_reminder(user_id, med):
    """Auto-create a reminder when a medicine is added."""
    from models import Reminder
    timing_map = {"morning": "08:00", "afternoon": "13:00", "evening": "18:00", "night": "21:30"}
    remind_time = timing_map.get(med.timing, "08:00")
    existing = Reminder.query.filter_by(user_id=user_id, title=f"Take {med.name}").first()
    if not existing:
        reminder = Reminder(
            user_id=user_id,
            title=f"Take {med.name}",
            message=f"Time to take your {med.dosage or ''} {med.name}",
            category="medicine",
            remind_time=remind_time,
            repeat_interval_mins=5,
            sound_name="medicine",
            sound_enabled=True,
            is_active=True,
            is_daily=True,
            max_repeats=3,
        )
        db.session.add(reminder)
        db.session.commit()