# ============================================================
# routes/api/family_api.py — Family Profiles API (APK)
# ============================================================

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from datetime import datetime, date
import json

from extensions import db
from models import FamilyMember, FamilyHealthMetric, FamilyMedicine, FamilyDocument

family_api_bp = Blueprint("family_api", __name__)


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None: r["data"] = data
    return jsonify(r), code


def err(msg="Error", code=400):
    return jsonify({"success": False, "message": msg}), code


# ── LIST FAMILY MEMBERS ───────────────────────────────────────
@family_api_bp.route("/members", methods=["GET"])
@jwt_required()
def get_members():
    user    = get_current_user()
    members = FamilyMember.query.filter_by(owner_id=user.id, is_active=True).all()

    result = []
    for m in members:
        d = m.to_dict()
        # Latest BP
        latest_bp = FamilyHealthMetric.query.filter_by(
            member_id=m.id, metric_type="bp"
        ).order_by(FamilyHealthMetric.recorded_at.desc()).first()
        # Latest weight
        latest_wt = FamilyHealthMetric.query.filter_by(
            member_id=m.id, metric_type="weight"
        ).order_by(FamilyHealthMetric.recorded_at.desc()).first()
        d["latest_bp"]     = latest_bp.to_dict() if latest_bp else None
        d["latest_weight"] = latest_wt.to_dict() if latest_wt else None
        d["medicine_count"]= FamilyMedicine.query.filter_by(member_id=m.id, active=True).count()
        result.append(d)

    return ok({"members": result, "count": len(result)})


# ── GET SINGLE MEMBER ─────────────────────────────────────────
@family_api_bp.route("/members/<int:member_id>", methods=["GET"])
@jwt_required()
def get_member(member_id):
    user   = get_current_user()
    member = FamilyMember.query.filter_by(id=member_id, owner_id=user.id).first_or_404()

    d = member.to_dict()

    # Recent metrics
    metrics = FamilyHealthMetric.query.filter_by(member_id=member.id).order_by(
        FamilyHealthMetric.recorded_at.desc()
    ).limit(20).all()
    d["recent_metrics"] = [m.to_dict() for m in metrics]

    # Medicines
    meds = FamilyMedicine.query.filter_by(member_id=member.id, active=True).all()
    d["medicines"] = [
        {"id": m.id, "name": m.name, "dosage": m.dosage, "timing": m.timing, "frequency": m.frequency}
        for m in meds
    ]

    return ok(d)


# ── ADD FAMILY MEMBER ─────────────────────────────────────────
@family_api_bp.route("/members", methods=["POST"])
@jwt_required()
def add_member():
    user = get_current_user()
    data = request.get_json() or {}

    name = data.get("name", "").strip()
    if not name: return err("Name is required", 422)

    dob = None
    dob_str = data.get("date_of_birth", "")
    if dob_str:
        try: dob = datetime.strptime(dob_str, "%Y-%m-%d").date()
        except ValueError: pass

    member = FamilyMember(
        owner_id            = user.id,
        name                = name,
        relation            = data.get("relation", ""),
        gender              = data.get("gender", ""),
        date_of_birth       = dob,
        height_cm           = data.get("height_cm"),
        current_weight_kg   = data.get("current_weight_kg"),
        blood_group         = data.get("blood_group", ""),
        emergency_contact   = data.get("emergency_contact", ""),
        target_weight_kg    = data.get("target_weight_kg"),
        target_bp_systolic  = data.get("target_bp_systolic", 130),
        target_bp_diastolic = data.get("target_bp_diastolic", 80),
        target_water_litres = data.get("target_water_litres", 2.5),
        target_steps        = data.get("target_steps", 8000),
        conditions_json     = json.dumps(data.get("conditions", [])),
        notes               = data.get("notes", ""),
    )
    db.session.add(member)
    db.session.commit()
    return ok(member.to_dict(), f"{name} added to family", 201)


# ── UPDATE FAMILY MEMBER ──────────────────────────────────────
@family_api_bp.route("/members/<int:member_id>", methods=["PUT"])
@jwt_required()
def update_member(member_id):
    user   = get_current_user()
    member = FamilyMember.query.filter_by(id=member_id, owner_id=user.id).first_or_404()
    data   = request.get_json() or {}

    fields = ["name","relation","gender","blood_group","emergency_contact",
              "height_cm","current_weight_kg","target_weight_kg",
              "target_bp_systolic","target_bp_diastolic",
              "target_water_litres","target_steps","notes"]

    for f in fields:
        if f in data: setattr(member, f, data[f])

    if "conditions" in data:
        member.conditions_json = json.dumps(data["conditions"])
    if "date_of_birth" in data and data["date_of_birth"]:
        try: member.date_of_birth = datetime.strptime(data["date_of_birth"], "%Y-%m-%d").date()
        except ValueError: pass

    db.session.commit()
    return ok(member.to_dict(), "Member updated")


# ── DELETE FAMILY MEMBER ──────────────────────────────────────
@family_api_bp.route("/members/<int:member_id>", methods=["DELETE"])
@jwt_required()
def delete_member(member_id):
    user   = get_current_user()
    member = FamilyMember.query.filter_by(id=member_id, owner_id=user.id).first_or_404()
    member.is_active = False
    db.session.commit()
    return ok(message=f"{member.name} removed from family")


# ── LOG METRIC FOR FAMILY MEMBER ──────────────────────────────
@family_api_bp.route("/members/<int:member_id>/metrics", methods=["POST"])
@jwt_required()
def log_metric(member_id):
    user   = get_current_user()
    member = FamilyMember.query.filter_by(id=member_id, owner_id=user.id).first_or_404()
    data   = request.get_json() or {}

    metric_type = data.get("metric_type", "")
    if not metric_type: return err("metric_type required", 422)

    metric = FamilyHealthMetric(
        member_id   = member.id,
        metric_type = metric_type,
        value_1     = data.get("value_1"),
        value_2     = data.get("value_2"),
        value_3     = data.get("value_3"),
        unit        = data.get("unit"),
        notes       = data.get("notes", ""),
        recorded_at = datetime.utcnow(),
    )
    db.session.add(metric)

    # Update weight in profile
    if metric_type == "weight" and data.get("value_1"):
        member.current_weight_kg = float(data["value_1"])

    db.session.commit()
    return ok(metric.to_dict(), "Metric logged", 201)


# ── GET METRICS FOR FAMILY MEMBER ────────────────────────────
@family_api_bp.route("/members/<int:member_id>/metrics", methods=["GET"])
@jwt_required()
def get_metrics(member_id):
    user    = get_current_user()
    member  = FamilyMember.query.filter_by(id=member_id, owner_id=user.id).first_or_404()
    metric_type = request.args.get("type")
    limit   = int(request.args.get("limit", 30))

    q = FamilyHealthMetric.query.filter_by(member_id=member.id)
    if metric_type: q = q.filter_by(metric_type=metric_type)
    metrics = q.order_by(FamilyHealthMetric.recorded_at.desc()).limit(limit).all()

    return ok({"metrics": [m.to_dict() for m in metrics], "member": member.to_dict()})


# ── ADD MEDICINE FOR FAMILY MEMBER ───────────────────────────
@family_api_bp.route("/members/<int:member_id>/medicines", methods=["POST"])
@jwt_required()
def add_medicine(member_id):
    user   = get_current_user()
    member = FamilyMember.query.filter_by(id=member_id, owner_id=user.id).first_or_404()
    data   = request.get_json() or {}

    name = data.get("name", "").strip()
    if not name: return err("Medicine name required", 422)

    med = FamilyMedicine(
        member_id = member.id, name=name,
        dosage    = data.get("dosage", ""),
        timing    = data.get("timing", "08:00"),
        frequency = data.get("frequency", "daily"),
        active    = True,
    )
    db.session.add(med)
    db.session.commit()
    return ok({"id": med.id, "name": med.name, "dosage": med.dosage}, "Medicine added", 201)


# ── FAMILY DASHBOARD SUMMARY ──────────────────────────────────
@family_api_bp.route("/dashboard", methods=["GET"])
@jwt_required()
def family_dashboard():
    """Quick health overview for all family members."""
    user    = get_current_user()
    members = FamilyMember.query.filter_by(owner_id=user.id, is_active=True).all()

    summary = []
    for m in members:
        latest_bp = FamilyHealthMetric.query.filter_by(
            member_id=m.id, metric_type="bp"
        ).order_by(FamilyHealthMetric.recorded_at.desc()).first()

        latest_wt = FamilyHealthMetric.query.filter_by(
            member_id=m.id, metric_type="weight"
        ).order_by(FamilyHealthMetric.recorded_at.desc()).first()

        bp_status = "No Reading"
        if latest_bp and latest_bp.value_1:
            s, d = latest_bp.value_1, latest_bp.value_2 or 0
            if s < 120 and d < 80:   bp_status = "Normal ✅"
            elif s < 130 and d < 80: bp_status = "Elevated ⚠️"
            elif s < 180 or d < 120: bp_status = "High 🔴"
            else:                    bp_status = "Crisis 🚨"

        summary.append({
            "member":     m.to_dict(),
            "bp":         latest_bp.to_dict() if latest_bp else None,
            "bp_status":  bp_status,
            "weight":     latest_wt.to_dict() if latest_wt else None,
            "alerts":     _check_member_alerts(m),
        })

    return ok({"family_summary": summary, "member_count": len(members)})


def _check_member_alerts(member):
    alerts = []
    latest_bp = FamilyHealthMetric.query.filter_by(
        member_id=member.id, metric_type="bp"
    ).order_by(FamilyHealthMetric.recorded_at.desc()).first()

    if latest_bp and latest_bp.value_1:
        s = latest_bp.value_1
        if s >= 180: alerts.append({"type": "emergency", "msg": f"{member.name}: BP {int(s)} — Crisis! Needs immediate attention."})
        elif s >= 140: alerts.append({"type": "warning", "msg": f"{member.name}: BP {int(s)} — Elevated. Monitor closely."})

    return alerts