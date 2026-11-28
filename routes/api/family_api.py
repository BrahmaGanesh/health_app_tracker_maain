# routes/api/family_api.py — Family Health Management API
# Plan limits: Free=0, Normal=1, Premium=2 (admin can increase per user)
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from models import User, FamilyMember, FamilyHealthMetric, FamilyMedicine, FamilyDocument, now_ist, today_ist, UserSubscription, Appointment
import json

family_api_bp = Blueprint("family_api", __name__)


# ── Plan helpers ───────────────────────────────────────────────────
def _get_plan(user_id):
    sub_list = UserSubscription.get_all(filters={"user_id": user_id}, limit=1)
    sub = sub_list[0] if sub_list else None
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


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None:
        r["data"] = data
    return jsonify(r), code


def err(msg="Error", code=400):
    return jsonify({"success": False, "message": msg}), code


def get_current_user():
    uid = get_jwt_identity()
    return User.get_by_id(uid)


# ════════════════════════════════════════════════════════════════
# FAMILY MEMBERS — list, add, edit, delete
# ════════════════════════════════════════════════════════════════

@family_api_bp.route("/members", methods=["GET"])
@jwt_required()
def get_members():
    uid = get_jwt_identity()
    user = User.get_by_id(uid)
    members = FamilyMember.get_all(
        filters={"owner_id": uid, "is_active": True},
        order_by="name"
    )
    plan = _get_plan(uid)
    limit = _member_limit(user)

    return jsonify({"success": True, "members": [m.to_dict() for m in members], "plan": plan, "limit": limit})


@family_api_bp.route("/members", methods=["POST"])
@jwt_required()
def add_member():
    uid = get_jwt_identity()
    user = User.get_by_id(uid)
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
    current_count = FamilyMember.count(filters={"owner_id": uid, "is_active": True})
    limit = _member_limit(user)

    if current_count >= limit:
        return jsonify({
            "success": False,
            "message": f"🔒 You can add max {limit} family member(s) on your {plan.title()} plan",
            "upgrade_required": plan == "normal",
            "current_count": current_count,
            "limit": limit,
        }), 403

    data = request.get_json() or {}
    name = (data.get("name") or "").strip()
    relationship = data.get("relationship", "")
    dob_str = data.get("date_of_birth", "")
    gender = data.get("gender", "")
    blood_group = data.get("blood_group", "")
    phone = data.get("phone", "")
    email = data.get("email", "")

    if not name or not relationship or not dob_str:
        return jsonify({"success": False, "message": "Name, relationship, and date of birth are required"}), 400

    try:
        dob = datetime.strptime(dob_str, "%Y-%m-%d").date()
    except ValueError:
        return jsonify({"success": False, "message": "Invalid date format"}), 400

    member = FamilyMember(
        owner_id=uid,
        name=name,
        relationship=relationship,
        date_of_birth=dob,
        gender=gender,
        blood_group=blood_group,
        phone=phone,
        email=email,
    )
    member.save()
    return jsonify({"success": True, "member": member.to_dict()}), 201


@family_api_bp.route("/members/<int:member_id>", methods=["GET"])
@jwt_required()
def get_member(member_id):
    uid = get_jwt_identity()
    member = FamilyMember.get_by_id_or_404(member_id)
    if member.owner_id != get_jwt_identity():
        return jsonify({"success": False, "message": "Forbidden"}), 403

    return jsonify({"success": True, "member": member.to_dict()})


@family_api_bp.route("/members/<int:member_id>", methods=["PUT"])
@jwt_required()
def update_member(member_id):
    uid = get_jwt_identity()
    member = FamilyMember.get_by_id_or_404(member_id)
    if member.owner_id != get_jwt_identity():
        return jsonify({"success": False, "message": "Forbidden"}), 403

    data = request.get_json() or {}
    if "name" in data:
        member.name = data["name"].strip()
    if "relationship" in data:
        member.relationship = data["relationship"]
    if "date_of_birth" in data:
        try:
            member.date_of_birth = datetime.strptime(data["date_of_birth"], "%Y-%m-%d").date()
        except ValueError:
            return jsonify({"success": False, "message": "Invalid date format"}), 400
    if "gender" in data:
        member.gender = data["gender"]
    if "blood_group" in data:
        member.blood_group = data["blood_group"]
    if "phone" in data:
        member.phone = data["phone"]
    if "email" in data:
        member.email = data["email"]
    if "is_active" in data:
        member.is_active = data["is_active"]

    member.save()
    return jsonify({"success": True, "member": member.to_dict()})


@family_api_bp.route("/members/<int:member_id>", methods=["DELETE"])
@jwt_required()
def delete_member(member_id):
    uid = get_jwt_identity()
    member = FamilyMember.get_by_id_or_404(member_id)
    if member.owner_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    member.is_active = False
    member.save()
    return jsonify({"success": True, "message": f"{member.name} removed"})


# ═════════════════════════════════════════════════════════════════
# FAMILY HEALTH METRICS
# ════════════════════════════════════════════════════════════════

@family_api_bp.route("/members/<int:member_id>/metrics", methods=["GET"])
@jwt_required()
def get_member_metrics(member_id):
    uid = get_jwt_identity()
    member = FamilyMember.get_by_id_or_404(member_id)
    if member.owner_id != get_jwt_identity():
        return jsonify({"success": False, "message": "Forbidden"}), 403

    metric_type = request.args.get("type", "")
    days = request.args.get("days", 30, type=int) or 30
    since = date.today() - timedelta(days=days)

    filters = {"member_id": member_id}
    if metric_type:
        filters["metric_type"] = metric_type
    filters["recorded_at_gte"] = since

    metrics = FamilyHealthMetric.get_all(filters=filters, order_by="-recorded_at")
    return jsonify({"success": True, "metrics": [m.to_dict() for m in metrics]})


@family_api_bp.route("/members/<int:member_id>/metrics", methods=["POST"])
@jwt_required()
def log_metric(member_id):
    uid = get_jwt_identity()
    member = FamilyMember.get_by_id_or_404(member_id)
    if member.owner_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    data = request.get_json() or {}
    metric_type = data.get("metric_type", "")
    value_1 = data.get("value_1") or None
    value_2 = data.get("value_2") or None
    value_3 = data.get("value_3") or None
    notes = data.get("notes", "")

    if not metric_type:
        return jsonify({"success": False, "message": "Metric type required"}), 400

    try:
        if value_1 is not None:
            value_1 = float(value_1)
    except (TypeError, ValueError):
        return jsonify({"success": False, "message": "Invalid value_1"}), 400

    metric = FamilyHealthMetric(
        member_id=member_id,
        metric_type=metric_type,
        value_1=value_1,
        value_2=value_2,
        value_3=value_3,
        notes=notes,
        recorded_at=datetime.utcnow(),
    )
    metric.save()
    return jsonify({"success": True, "metric": metric.to_dict()}), 201


@family_api_bp.route("/members/<int:member_id>/metrics/<int:metric_id>", methods=["DELETE"])
@jwt_required()
def delete_metric(member_id, metric_id):
    uid = get_jwt_identity()
    member = FamilyMember.get_by_id_or_404(member_id)
    if member.owner_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    metric = FamilyHealthMetric.get_by_id_or_404(metric_id)
    if metric.member_id != member_id:
        return jsonify({"success": False, "message": "Forbidden"}), 403
    metric.delete()
    return jsonify({"success": True, "message": "Deleted"})