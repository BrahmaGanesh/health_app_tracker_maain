# routes/api/family_api.py — Family Health Management API
# Plan limits: Free=0, Normal=1, Premium=2 (admin can increase per user)
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from extensions import db
from models import User, FamilyMember, FamilyHealthMetric, FamilyMedicine, FamilyDocument, now_ist, today_ist , UserSubscription, Appointment
# from models_new_modules import
import json

family_api_bp = Blueprint("family_api", __name__)


# ── Plan helpers ───────────────────────────────────────────────────
def _get_plan(user_id):
    sub = UserSubscription.query.filter_by(user_id=user_id).first()
    if not sub: return "free"
    return sub.plan if sub.is_active else "free"

def _member_limit(user):
    """Returns how many family members this user can add."""
    plan = _get_plan(user.id)
    # Admin-set custom limit overrides plan default
    custom = user.family_member_limit  # default=2 from User model
    if plan == "free":     return 0
    if plan == "premium":  return custom         # default 2, admin can raise
    if plan == "family":   return custom         # default 2, admin can raise
    return 1                                     # "normal" subscription = 1

def _can_add_medicine(user_id):
    return _get_plan(user_id) in ("premium", "family")

def _doc_limit(user_id):
    plan = _get_plan(user_id)
    if plan == "free":    return 0
    if plan in ("normal",): return 1
    return 999  # premium / family = unlimited

def _can_add_appointment(user_id):
    return _get_plan(user_id) in ("premium", "family")


# ════════════════════════════════════════════════════════════════
# FAMILY MEMBERS — list, add, edit, delete
# ════════════════════════════════════════════════════════════════

@family_api_bp.route("/members", methods=["GET"])
@jwt_required()
def get_members():
    uid  = get_jwt_identity()
    user = User.query.get(uid)
    members = FamilyMember.query.filter_by(owner_id=uid, is_active=True).order_by(FamilyMember.name).all()
    plan  = _get_plan(uid)
    limit = _member_limit(user)

    return jsonify({"success": True, "data": {
        "members": [_enrich_member(m, uid) for m in members],
        "total": len(members),
        "limit": limit,
        "plan": plan,
        "can_add_more": len(members) < limit,
        "plan_features": _plan_features(uid),
    }})


@family_api_bp.route("/members", methods=["POST"])
@jwt_required()
def add_member():
    uid  = get_jwt_identity()
    user = User.query.get(uid)
    plan = _get_plan(uid)

    # Free users blocked
    if plan == "free":
        return jsonify({
            "success": False,
            "message": "🔒 Family management requires a subscription",
            "upgrade_required": True,
            "upgrade_message": "Upgrade to Normal plan to add 1 family member, or Premium for 2.",
        }), 403

    # Check limit
    current_count = FamilyMember.query.filter_by(owner_id=uid, is_active=True).count()
    limit         = _member_limit(user)

    if current_count >= limit:
        return jsonify({
            "success": False,
            "message": f"🔒 You can add max {limit} family member(s) on your {plan.title()} plan",
            "upgrade_required": plan == "normal",
            "current_count": current_count,
            "limit": limit,
        }), 403

    d = request.get_json() or {}
    if not d.get("name"):
        return jsonify({"success": False, "message": "Name is required"}), 400

    member = FamilyMember(
        owner_id=uid,
        name=d["name"].strip(),
        relation=d.get("relation", ""),
        gender=d.get("gender", ""),
        blood_group=d.get("blood_group"),
        notes=d.get("notes", "").strip() or None,
        conditions_json=json.dumps(d.get("conditions", [])),
    )

    # Parse DOB
    if d.get("dob"):
        from datetime import date
        try:
            member.date_of_birth = date.fromisoformat(d["dob"])
        except: pass

    if d.get("height_cm"):      member.height_cm = float(d["height_cm"])
    if d.get("weight_kg"):      member.current_weight_kg = float(d["weight_kg"])
    if d.get("emergency_contact"): member.emergency_contact = d["emergency_contact"]

    db.session.add(member)
    db.session.commit()
    return jsonify({"success": True, "message": f"✅ {member.name} added to family", "data": _enrich_member(member, uid)}), 201


@family_api_bp.route("/members/<int:mid>", methods=["GET"])
@jwt_required()
def get_member(mid):
    uid = get_jwt_identity()
    m   = FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()
    return jsonify({"success": True, "data": {
        **_enrich_member(m, uid),
        "plan_features": _plan_features(uid),
    }})


@family_api_bp.route("/members/<int:mid>", methods=["PUT"])
@jwt_required()
def update_member(mid):
    uid = get_jwt_identity()
    m   = FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()
    d   = request.get_json() or {}

    for f in ["name", "relation", "gender", "blood_group", "notes", "emergency_contact"]:
        if f in d: setattr(m, f, d[f])

    if "height_cm"  in d and d["height_cm"]:  m.height_cm         = float(d["height_cm"])
    if "weight_kg"  in d and d["weight_kg"]:  m.current_weight_kg = float(d["weight_kg"])
    if "conditions" in d: m.conditions_json = json.dumps(d["conditions"])
    if "dob"        in d and d["dob"]:
        from datetime import date
        try: m.date_of_birth = date.fromisoformat(d["dob"])
        except: pass

    db.session.commit()
    return jsonify({"success": True, "message": f"✅ {m.name} updated", "data": _enrich_member(m, uid)})


@family_api_bp.route("/members/<int:mid>", methods=["DELETE"])
@jwt_required()
def delete_member(mid):
    """Hard delete — removes member + ALL their data (metrics, medicines, documents, appointments)."""
    uid = get_jwt_identity()
    m   = FamilyMember.query.filter_by(id=mid, owner_id=uid).first_or_404()

    name = m.name
    # Cascade delete via relationships (all, delete-orphan)
    # Also delete appointments
    Appointment.query.filter_by(user_id=uid, member_id=mid).delete()
    db.session.delete(m)
    db.session.commit()
    return jsonify({"success": True, "message": f"🗑️ {name} and all their data permanently deleted"})


# ════════════════════════════════════════════════════════════════
# HEALTH METRICS per member (BP, Sugar, Weight)
# ════════════════════════════════════════════════════════════════

@family_api_bp.route("/members/<int:mid>/metrics", methods=["GET"])
@jwt_required()
def get_member_metrics(mid):
    uid = get_jwt_identity()
    FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()

    metric_type = request.args.get("type", "bp")
    records = FamilyHealthMetric.query.filter_by(
        family_member_id=mid, metric_type=metric_type
    ).order_by(FamilyHealthMetric.recorded_at.desc()).limit(30).all()

    return jsonify({"success": True, "data": {
        "records": [r.to_dict() for r in records],
        "latest": records[0].to_dict() if records else None,
    }})


@family_api_bp.route("/members/<int:mid>/metrics", methods=["POST"])
@jwt_required()
def add_member_metric(mid):
    uid  = get_jwt_identity()
    FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()
    d    = request.get_json() or {}
    mtype= d.get("metric_type", "bp")

    # Plan check — only BP, Sugar, Weight allowed for all paid plans
    allowed = ["bp", "weight", "sugar"]
    if mtype not in allowed:
        return jsonify({"success": False, "message": f"Metric type '{mtype}' not allowed"}), 400

    metric = FamilyHealthMetric(
        family_member_id=mid,
        user_id=uid,
        metric_type=mtype,
        value_1=d.get("value_1"),
        value_2=d.get("value_2"),
        notes=d.get("notes"),
        recorded_at=now_ist(),
    )
    db.session.add(metric)
    db.session.commit()
    return jsonify({"success": True, "message": "✅ Reading saved", "data": metric.to_dict()}), 201


@family_api_bp.route("/members/<int:mid>/metrics/<int:rid>", methods=["DELETE"])
@jwt_required()
def delete_member_metric(mid, rid):
    uid = get_jwt_identity()
    FamilyMember.query.filter_by(id=mid, owner_id=uid).first_or_404()
    r = FamilyHealthMetric.query.filter_by(id=rid, family_member_id=mid).first_or_404()
    db.session.delete(r)
    db.session.commit()
    return jsonify({"success": True, "message": "Deleted"})


# ════════════════════════════════════════════════════════════════
# MEDICINES per member — Premium only
# ════════════════════════════════════════════════════════════════

@family_api_bp.route("/members/<int:mid>/medicines", methods=["GET"])
@jwt_required()
def get_member_medicines(mid):
    uid = get_jwt_identity()
    FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()
    meds = FamilyMedicine.query.filter_by(family_member_id=mid).order_by(FamilyMedicine.name).all()
    return jsonify({"success": True, "data": {"medicines": [m.to_dict() for m in meds]}})


@family_api_bp.route("/members/<int:mid>/medicines", methods=["POST"])
@jwt_required()
def add_member_medicine(mid):
    uid = get_jwt_identity()
    if not _can_add_medicine(uid):
        return jsonify({"success": False, "message": "🔒 Medicine tracking requires Premium plan", "upgrade_required": True}), 403
    FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()
    d = request.get_json() or {}
    if not d.get("name"): return jsonify({"success": False, "message": "Medicine name required"}), 400
    med = FamilyMedicine(
        family_member_id=mid, user_id=uid,
        name=d["name"].strip(), dosage=d.get("dosage", ""),
        timing=d.get("timing", "morning"), frequency=d.get("frequency", "daily"),
    )
    db.session.add(med)
    db.session.commit()
    return jsonify({"success": True, "message": f"💊 {med.name} added", "data": med.to_dict()}), 201


@family_api_bp.route("/members/<int:mid>/medicines/<int:medid>", methods=["DELETE"])
@jwt_required()
def delete_member_medicine(mid, medid):
    uid = get_jwt_identity()
    FamilyMember.query.filter_by(id=mid, owner_id=uid).first_or_404()
    med = FamilyMedicine.query.filter_by(id=medid, family_member_id=mid).first_or_404()
    db.session.delete(med)
    db.session.commit()
    return jsonify({"success": True, "message": f"🗑️ {med.name} removed"})


# ════════════════════════════════════════════════════════════════
# DOCUMENTS per member — Normal=1 max, Premium=unlimited
# ════════════════════════════════════════════════════════════════

@family_api_bp.route("/members/<int:mid>/documents", methods=["GET"])
@jwt_required()
def get_member_documents(mid):
    uid = get_jwt_identity()
    FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()
    docs = FamilyDocument.query.filter_by(family_member_id=mid).order_by(FamilyDocument.uploaded_at.desc()).all()
    limit = _doc_limit(uid)
    return jsonify({"success": True, "data": {
        "documents": [d.to_dict() for d in docs],
        "limit": limit,
        "can_add_more": len(docs) < limit,
    }})


@family_api_bp.route("/members/<int:mid>/documents", methods=["POST"])
@jwt_required()
def add_member_document(mid):
    uid = get_jwt_identity()
    limit = _doc_limit(uid)

    if limit == 0:
        return jsonify({"success": False, "message": "🔒 Document upload requires a paid plan", "upgrade_required": True}), 403

    count = FamilyDocument.query.filter_by(family_member_id=mid).count()
    if count >= limit:
        msg = "Normal plan allows 1 document per member" if limit == 1 else f"Max {limit} documents reached"
        return jsonify({"success": False, "message": f"🔒 {msg}. Upgrade to Premium for unlimited.", "upgrade_required": True}), 403

    FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()
    d = request.get_json() or {}

    import base64, os
    from flask import current_app

    file_data = d.get("file_data", "")
    filename  = d.get("file_name", "document.pdf")
    title     = d.get("title", filename)
    doc_type  = d.get("doc_type", "other")

    # Save file
    folder = os.path.join(current_app.config.get("DOCS_FOLDER", "static/documents"), "family", str(mid))
    os.makedirs(folder, exist_ok=True)
    filepath = os.path.join(folder, filename)
    if file_data:
        with open(filepath, "wb") as f:
            f.write(base64.b64decode(file_data))

    doc = FamilyDocument(
        family_member_id=mid, user_id=uid,
        title=title, doc_type=doc_type, file_path=filepath,
        file_name=filename, uploaded_at=now_ist(),
    )
    db.session.add(doc)
    db.session.commit()
    return jsonify({"success": True, "message": f"📎 {title} uploaded", "data": doc.to_dict()}), 201


@family_api_bp.route("/members/<int:mid>/documents/<int:did>", methods=["DELETE"])
@jwt_required()
def delete_member_document(mid, did):
    uid = get_jwt_identity()
    FamilyMember.query.filter_by(id=mid, owner_id=uid).first_or_404()
    doc = FamilyDocument.query.filter_by(id=did, family_member_id=mid).first_or_404()
    import os
    if doc.file_path and os.path.exists(doc.file_path):
        os.remove(doc.file_path)
    title = doc.title
    db.session.delete(doc)
    db.session.commit()
    return jsonify({"success": True, "message": f"🗑️ {title} deleted"})


# ════════════════════════════════════════════════════════════════
# APPOINTMENTS per member — Premium only + auto-reminder
# ════════════════════════════════════════════════════════════════

@family_api_bp.route("/members/<int:mid>/appointments", methods=["GET"])
@jwt_required()
def get_member_appointments(mid):
    uid = get_jwt_identity()
    FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()
    appts = Appointment.query.filter_by(user_id=uid, member_id=mid).order_by(Appointment.appointment_date.asc()).all()
    return jsonify({"success": True, "data": {"appointments": [a.to_dict() for a in appts]}})


@family_api_bp.route("/members/<int:mid>/appointments", methods=["POST"])
@jwt_required()
def add_member_appointment(mid):
    uid = get_jwt_identity()
    if not _can_add_appointment(uid):
        return jsonify({"success": False, "message": "🔒 Appointments require Premium plan", "upgrade_required": True}), 403
    m = FamilyMember.query.filter_by(id=mid, owner_id=uid, is_active=True).first_or_404()
    d = request.get_json() or {}
    if not d.get("title") or not d.get("appointment_date"):
        return jsonify({"success": False, "message": "Title and date required"}), 400

    from datetime import date
    appt = Appointment(
        user_id=uid, member_id=mid,
        title=d["title"].strip(),
        appointment_type=d.get("appointment_type", "doctor"),
        appointment_date=date.fromisoformat(d["appointment_date"]),
        appointment_time=d.get("appointment_time"),
        location=d.get("location"),
        notes=d.get("notes"),
    )
    db.session.add(appt)
    db.session.commit()

    # Auto-create reminder notification
    _create_appointment_reminder(uid, m.name, appt)

    return jsonify({"success": True, "message": f"📅 Appointment added for {m.name}", "data": appt.to_dict()}), 201


@family_api_bp.route("/members/<int:mid>/appointments/<int:aid>", methods=["DELETE"])
@jwt_required()
def delete_member_appointment(mid, aid):
    uid  = get_jwt_identity()
    appt = Appointment.query.filter_by(id=aid, user_id=uid, member_id=mid).first_or_404()
    db.session.delete(appt)
    db.session.commit()
    return jsonify({"success": True, "message": "Appointment deleted"})


# ════════════════════════════════════════════════════════════════
# ADMIN — set per-user family member limit
# ════════════════════════════════════════════════════════════════

@family_api_bp.route("/admin/set-limit", methods=["POST"])
@jwt_required()
def admin_set_limit():
    """Admin-only: set custom family member limit for a specific user."""
    uid  = get_jwt_identity()
    user = User.query.get(uid)
    if not user or not user.is_admin:
        return jsonify({"success": False, "message": "Admin access required"}), 403

    d         = request.get_json() or {}
    target_id = d.get("user_id")
    new_limit = d.get("limit", 2)

    if not target_id:
        return jsonify({"success": False, "message": "user_id required"}), 400
    if not isinstance(new_limit, int) or new_limit < 0:
        return jsonify({"success": False, "message": "limit must be a positive integer"}), 400

    target = User.query.get(target_id)
    if not target:
        return jsonify({"success": False, "message": "User not found"}), 404

    target.family_member_limit = new_limit
    db.session.commit()
    return jsonify({"success": True, "message": f"✅ {target.name}'s family limit set to {new_limit}"})


# ════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════

def _enrich_member(m: FamilyMember, uid: int) -> dict:
    """Return member dict enriched with latest metrics."""
    d    = m.to_dict()
    plan = _get_plan(uid)

    # Latest readings
    def latest(mtype):
        r = FamilyHealthMetric.query.filter_by(family_member_id=m.id, metric_type=mtype).order_by(FamilyHealthMetric.recorded_at.desc()).first()
        return r.to_dict() if r else None

    d["latest_bp"]     = latest("bp")
    d["latest_sugar"]  = latest("sugar")
    d["latest_weight"] = latest("weight")
    d["medicine_count"]= FamilyMedicine.query.filter_by(family_member_id=m.id).count()
    d["doc_count"]     = FamilyDocument.query.filter_by(family_member_id=m.id).count()

    upcoming = Appointment.query.filter_by(user_id=uid, member_id=m.id, completed=False)\
        .filter(Appointment.appointment_date >= today_ist()).order_by(Appointment.appointment_date).first()
    d["next_appointment"] = upcoming.to_dict() if upcoming else None

    return d


def _plan_features(uid: int) -> dict:
    plan = _get_plan(uid)
    return {
        "plan": plan,
        "can_add_member":     plan != "free",
        "can_track_bp":       plan != "free",
        "can_track_sugar":    plan != "free",
        "can_track_weight":   plan != "free",
        "can_add_medicine":   _can_add_medicine(uid),
        "doc_limit":          _doc_limit(uid),
        "can_add_appointment":_can_add_appointment(uid),
    }


def _create_appointment_reminder(user_id: int, member_name: str, appt: Appointment):
    """Create a notification reminder 1 day before appointment."""
    try:
        from models import Reminder
        reminder = Reminder(
            user_id=user_id,
            title=f"📅 {member_name}: {appt.title}",
            message=f"Appointment tomorrow at {appt.appointment_time or 'scheduled time'}. Location: {appt.location or 'Check details'}",
            category="appointment",
            remind_time="09:00",
            repeat_interval_mins=0,
            sound_name="health_alert",
            is_active=True, is_daily=False, max_repeats=1,
        )
        db.session.add(reminder)
        db.session.commit()
    except Exception:
        pass  # Don't fail the appointment creation if reminder fails