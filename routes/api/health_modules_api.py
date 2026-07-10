# routes/api/health_modules_api.py
# Lab Tests, Doctor Visits, Appointments, Emergency Card,
# Habits, Timeline, AI Assistant, Subscription, Trusted Contacts

from datetime import datetime, timedelta

from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity

from extensions import db
from models import now_ist, today_ist, HabitLog, User
from models_new_modules import (
    LabTest,
    DoctorVisit,
    Appointment,
    EmergencyCard,
    TrustedContact,
    UserSubscription,
    HealthTimelineEvent,
)

modules_api_bp = Blueprint("modules_api", __name__)


# ════════════════════════════════════════════════════════════════
# MODULE 8 — LAB TEST TRACKER
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/lab-tests/", methods=["GET", "POST"])
@jwt_required()
def lab_tests():
    uid = get_jwt_identity()

    if request.method == "GET":
        test_type = request.args.get("test_type", "blood_sugar")
        member_id = request.args.get("member_id", type=int)

        q = LabTest.query.filter_by(user_id=uid, test_type=test_type)
        if member_id:
            q = q.filter_by(member_id=member_id)

        tests = q.order_by(LabTest.test_date.desc()).limit(50).all()
        return jsonify({
            "success": True,
            "data": {
                "tests": [t.to_dict() for t in tests],
                "latest": tests[0].to_dict() if tests else None,
                "test_type": test_type,
            }
        })

    d = request.get_json() or {}
    if not d.get("test_type") or d.get("value") is None:
        return jsonify({"success": False, "message": "test_type and value required"}), 400

    test = LabTest(
        user_id=uid,
        test_type=d["test_type"],
        value=float(d["value"]),
        unit=d.get("unit", ""),
        lab_name=d.get("lab_name", "").strip() or None,
        test_date=_parse_date(d.get("test_date")),
        notes=d.get("notes", "").strip() or None,
        member_id=d.get("member_id"),
    )
    db.session.add(test)

    db.session.add(HealthTimelineEvent(
        user_id=uid,
        event_type="lab",
        event_date=test.test_date,
        title=f"🧪 {test.test_type.replace('_', ' ').title()}: {test.value} {test.unit or ''}".strip(),
        description=f"Lab: {test.lab_name or 'Unknown'} · Status: {getattr(test, 'status', 'Recorded')}",
        icon="🧪",
        member_id=test.member_id,
    ))
    db.session.commit()

    return jsonify({
        "success": True,
        "message": "Lab test saved",
        "data": test.to_dict()
    }), 201


@modules_api_bp.route("/lab-tests/<int:tid>", methods=["DELETE"])
@jwt_required()
def delete_lab_test(tid):
    uid = get_jwt_identity()
    t = LabTest.query.filter_by(id=tid, user_id=uid).first_or_404()
    db.session.delete(t)
    db.session.commit()
    return jsonify({"success": True, "message": "Deleted"})


@modules_api_bp.route("/lab-tests/types", methods=["GET"])
@jwt_required()
def lab_test_types():
    uid = get_jwt_identity()
    rows = db.session.query(LabTest.test_type).filter_by(user_id=uid).distinct().all()
    return jsonify({"success": True, "data": {"types": [r[0] for r in rows]}})


# ════════════════════════════════════════════════════════════════
# MODULE 9 — DOCTOR VISITS
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/doctor-visits/", methods=["GET", "POST"])
@jwt_required()
def doctor_visits():
    uid = get_jwt_identity()

    if request.method == "GET":
        member_id = request.args.get("member_id", type=int)
        q = DoctorVisit.query.filter_by(user_id=uid)
        if member_id:
            q = q.filter_by(member_id=member_id)

        visits = q.order_by(DoctorVisit.visit_date.desc()).limit(50).all()
        return jsonify({"success": True, "data": {"visits": [v.to_dict() for v in visits]}})

    d = request.get_json() or {}
    visit = DoctorVisit(
        user_id=uid,
        visit_date=_parse_date(d.get("visit_date")),
        doctor_name=d.get("doctor_name", "").strip() or None,
        hospital=d.get("hospital", "").strip() or None,
        specialization=d.get("specialization", "").strip() or None,
        diagnosis=d.get("diagnosis", "").strip() or None,
        prescription=d.get("prescription", "").strip() or None,
        follow_up_date=_parse_date(d.get("follow_up_date")) if d.get("follow_up_date") else None,
        cost=d.get("cost"),
        notes=d.get("notes", "").strip() or None,
        member_id=d.get("member_id"),
    )
    db.session.add(visit)

    db.session.add(HealthTimelineEvent(
        user_id=uid,
        event_type="visit",
        event_date=visit.visit_date,
        title=f"👨‍⚕️ Dr. {visit.doctor_name or 'Unknown'} — {visit.hospital or 'Visit'}",
        description=visit.diagnosis or "",
        icon="👨‍⚕️",
        member_id=visit.member_id,
    ))
    db.session.commit()

    if visit.follow_up_date:
        _auto_create_followup(uid, visit)
        db.session.commit()

    return jsonify({
        "success": True,
        "message": "Visit saved",
        "data": visit.to_dict()
    }), 201


@modules_api_bp.route("/doctor-visits/<int:vid>", methods=["DELETE"])
@jwt_required()
def delete_doctor_visit(vid):
    uid = get_jwt_identity()
    v = DoctorVisit.query.filter_by(id=vid, user_id=uid).first_or_404()
    db.session.delete(v)
    db.session.commit()
    return jsonify({"success": True, "message": "Deleted"})


# ════════════════════════════════════════════════════════════════
# MODULE 10 — APPOINTMENTS
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/appointments/", methods=["GET", "POST"])
@jwt_required()
def appointments():
    uid = get_jwt_identity()

    if request.method == "GET":
        member_id = request.args.get("member_id", type=int)
        upcoming_only = request.args.get("upcoming", "false").lower() == "true"

        q = Appointment.query.filter_by(user_id=uid)
        if member_id:
            q = q.filter_by(member_id=member_id)
        if upcoming_only:
            q = q.filter(
                Appointment.appointment_date >= today_ist(),
                Appointment.completed.is_(False)
            )

        appts = q.order_by(Appointment.appointment_date.asc()).limit(100).all()
        return jsonify({
            "success": True,
            "data": {
                "appointments": [a.to_dict() for a in appts],
                "upcoming_count": sum(1 for a in appts if not a.completed),
            }
        })

    d = request.get_json() or {}
    if not d.get("title") or not d.get("appointment_date"):
        return jsonify({"success": False, "message": "title and appointment_date required"}), 400

    appt = Appointment(
        user_id=uid,
        title=d["title"].strip(),
        appointment_type=d.get("appointment_type", "doctor"),
        appointment_date=_parse_date(d["appointment_date"]),
        appointment_time=d.get("appointment_time"),
        location=d.get("location", "").strip() or None,
        notes=d.get("notes", "").strip() or None,
        member_id=d.get("member_id"),
    )
    db.session.add(appt)
    db.session.commit()

    return jsonify({
        "success": True,
        "message": "📅 Appointment saved",
        "data": appt.to_dict()
    }), 201


@modules_api_bp.route("/appointments/<int:aid>", methods=["PUT", "DELETE"])
@jwt_required()
def appointment_detail(aid):
    uid = get_jwt_identity()
    appt = Appointment.query.filter_by(id=aid, user_id=uid).first_or_404()

    if request.method == "DELETE":
        db.session.delete(appt)
        db.session.commit()
        return jsonify({"success": True, "message": "Deleted"})

    d = request.get_json() or {}
    for f in ["title", "appointment_type", "appointment_time", "location", "notes"]:
        if f in d:
            setattr(appt, f, d[f])

    if "appointment_date" in d:
        appt.appointment_date = _parse_date(d["appointment_date"])

    db.session.commit()
    return jsonify({"success": True, "data": appt.to_dict()})


@modules_api_bp.route("/appointments/<int:aid>/complete", methods=["POST"])
@jwt_required()
def complete_appointment(aid):
    uid = get_jwt_identity()
    appt = Appointment.query.filter_by(id=aid, user_id=uid).first_or_404()
    appt.completed = True

    db.session.add(HealthTimelineEvent(
        user_id=uid,
        event_type="visit",
        event_date=today_ist(),
        title=f"✅ Completed: {appt.title}",
        icon="✅",
    ))
    db.session.commit()
    return jsonify({"success": True, "message": "✅ Appointment completed"})


# ════════════════════════════════════════════════════════════════
# MODULE 14 — EMERGENCY CARD
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/emergency-card/", methods=["GET", "POST"])
@jwt_required()
def emergency_card():
    uid = get_jwt_identity()

    user = User.query.get(uid)
    card = EmergencyCard.query.filter_by(user_id=uid).first()

    medicines = []
    try:
        from models import Medicine
        medicines = [
            m.name for m in Medicine.query.filter_by(user_id=uid, is_active=True).limit(10).all()
        ]
    except Exception:
        medicines = []

    conditions = []
    try:
        if user and hasattr(user, "conditions") and user.conditions:
            conditions = [
                c.condition.name if getattr(c, "condition", None) else str(c)
                for c in user.conditions
            ]
    except Exception:
        conditions = []

    if request.method == "GET":
        base_data = (
            card.to_dict(user=user, conditions=conditions, medicines=medicines)
            if card else {
                "blood_group": None,
                "allergies": None,
                "emergency_contacts": None,
                "organ_donor": False,
                "additional_notes": None,
            }
        )

        return jsonify({
            "success": True,
            "data": {
                **base_data,
                "name": getattr(user, "name", None),
                "age": getattr(user, "age", None),
                "conditions": conditions,
                "medicines": medicines,
            }
        })

    d = request.get_json() or {}
    if not card:
        card = EmergencyCard(user_id=uid)
        db.session.add(card)

    card.blood_group = d.get("blood_group", card.blood_group)
    card.allergies = d.get("allergies", card.allergies)
    card.emergency_contacts = d.get("emergency_contacts", card.emergency_contacts)
    card.organ_donor = d.get("organ_donor", card.organ_donor)
    card.additional_notes = d.get("additional_notes", card.additional_notes)

    db.session.commit()
    return jsonify({"success": True, "message": "Emergency card updated"})


# ════════════════════════════════════════════════════════════════
# MODULE 15 — TRUSTED CONTACTS
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/emergency-alerts/contacts", methods=["GET", "POST"])
@jwt_required()
def trusted_contacts():
    uid = get_jwt_identity()

    if request.method == "GET":
        contacts = TrustedContact.query.filter_by(user_id=uid).all()
        return jsonify({"success": True, "data": {"contacts": [c.to_dict() for c in contacts]}})

    d = request.get_json() or {}
    if not d.get("name"):
        return jsonify({"success": False, "message": "Contact name required"}), 400

    c = TrustedContact(
        user_id=uid,
        name=d["name"].strip(),
        phone=d.get("phone"),
        email=d.get("email"),
        relation=d.get("relation"),
        notify_bp_crisis=d.get("notify_bp_crisis", True),
        notify_missed_meds=d.get("notify_missed_meds", False),
    )
    db.session.add(c)
    db.session.commit()

    return jsonify({
        "success": True,
        "message": f"Contact {c.name} added",
        "data": c.to_dict()
    }), 201


@modules_api_bp.route("/emergency-alerts/contacts/<int:cid>", methods=["DELETE"])
@jwt_required()
def delete_trusted_contact(cid):
    uid = get_jwt_identity()
    c = TrustedContact.query.filter_by(id=cid, user_id=uid).first_or_404()
    db.session.delete(c)
    db.session.commit()
    return jsonify({"success": True, "message": "Contact removed"})


# ════════════════════════════════════════════════════════════════
# MODULE 20 — HEALTH TIMELINE
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/timeline/", methods=["GET"])
@jwt_required()
def timeline():
    uid = get_jwt_identity()
    member_id = request.args.get("member_id", type=int)
    category = request.args.get("category")
    page = request.args.get("page", 1, type=int)

    q = HealthTimelineEvent.query.filter_by(user_id=uid)
    if member_id:
        q = q.filter_by(member_id=member_id)
    if category:
        q = q.filter_by(event_type=category)

    events = q.order_by(HealthTimelineEvent.event_date.desc()).paginate(
        page=page, per_page=30, error_out=False
    )

    return jsonify({
        "success": True,
        "data": {
            "events": [e.to_dict() for e in events.items],
            "total": events.total,
            "page": page,
            "pages": events.pages,
        }
    })


# ════════════════════════════════════════════════════════════════
# MODULE 19 — AI WELLNESS ASSISTANT
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/ai-assistant/chat", methods=["POST"])
@jwt_required()
def ai_chat():
    uid = get_jwt_identity()
    d = request.get_json() or {}
    message = d.get("message", "").strip()
    history = d.get("history", [])

    if not message:
        return jsonify({"success": False, "message": "Message required"}), 400

    try:
        import anthropic

        client = anthropic.Anthropic(
            api_key=current_app.config.get("ANTHROPIC_API_KEY", "")
        )

        system = """You are HealthTrack's wellness assistant. You provide helpful, accurate, and compassionate
health and wellness advice. Important rules:
1. Always recommend consulting a doctor for medical diagnoses or treatment decisions
2. Focus on general wellness, lifestyle, nutrition, and healthy habits
3. Keep responses concise (2-4 sentences typically)
4. For emergency symptoms (chest pain, stroke signs, etc.) always say: 'Call emergency services immediately'
5. You know about BP management, diabetes, weight, sleep, and exercise"""

        messages = []
        for h in history[-8:]:
            if h.get("role") in ("user", "assistant"):
                messages.append({
                    "role": h["role"],
                    "content": h.get("content", "")
                })

        messages.append({"role": "user", "content": message})

        resp = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=400,
            system=system,
            messages=messages,
        )
        reply = resp.content[0].text

    except Exception:
        reply = (
            "I'm unable to connect to the AI service right now. "
            "For health questions, please consult your doctor or a qualified healthcare professional."
        )

    return jsonify({"success": True, "data": {"reply": reply, "role": "assistant"}})


# ════════════════════════════════════════════════════════════════
# MODULE 6 — AI CAMERA
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/ai-camera/food", methods=["POST"])
@jwt_required()
def analyze_food():
    d = request.get_json() or {}
    image = d.get("image", "")
    if not image:
        return jsonify({"success": False, "message": "image required"}), 400

    try:
        import anthropic
        import json
        import re

        client = anthropic.Anthropic(
            api_key=current_app.config.get("ANTHROPIC_API_KEY", "")
        )

        resp = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=500,
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": image
                        }
                    },
                    {
                        "type": "text",
                        "text": "Identify the food and estimate: calories, protein, carbs, fats, sodium. Return JSON: {food_name, calories, protein_g, carbs_g, fat_g, sodium_mg, is_healthy_for_bp (true/false), notes}"
                    },
                ]
            }],
        )

        text = resp.content[0].text
        match = re.search(r'\{.*\}', text, re.DOTALL)
        data = json.loads(match.group()) if match else {"food_name": "Unknown", "calories": 0}
    except Exception as e:
        data = {"food_name": "Analysis unavailable", "notes": str(e)}

    return jsonify({"success": True, "data": data})


@modules_api_bp.route("/ai-camera/medicine", methods=["POST"])
@jwt_required()
def analyze_medicine():
    d = request.get_json() or {}
    image = d.get("image", "")
    if not image:
        return jsonify({"success": False, "message": "image required"}), 400

    try:
        import anthropic
        import json
        import re

        client = anthropic.Anthropic(
            api_key=current_app.config.get("ANTHROPIC_API_KEY", "")
        )

        resp = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=400,
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": image
                        }
                    },
                    {
                        "type": "text",
                        "text": "Identify this medicine if visible. Return JSON: {medicine_name, active_ingredient, common_uses, typical_dosage, important_warnings, requires_prescription (true/false)}"
                    },
                ]
            }],
        )

        text = resp.content[0].text
        match = re.search(r'\{.*\}', text, re.DOTALL)
        data = json.loads(match.group()) if match else {"medicine_name": "Unknown"}
    except Exception as e:
        data = {"medicine_name": "Analysis unavailable", "notes": str(e)}

    return jsonify({"success": True, "data": data})


# ════════════════════════════════════════════════════════════════
# SUBSCRIPTION STATUS
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/subscription/status", methods=["GET"])
@jwt_required()
def subscription_status():
    uid = get_jwt_identity()
    sub = UserSubscription.query.filter_by(user_id=uid).first()

    if not sub:
        sub = UserSubscription(user_id=uid, plan="free")
        db.session.add(sub)
        db.session.commit()

    return jsonify({"success": True, "data": sub.to_dict()})


@modules_api_bp.route("/subscription/verify", methods=["POST"])
@jwt_required()
def verify_purchase():
    uid = get_jwt_identity()
    d = request.get_json() or {}
    purchase_token = d.get("purchase_token", "")
    product_id = d.get("product_id", "")

    plan_map = {
        "healthtrack_premium_monthly": "premium",
        "healthtrack_premium_yearly": "premium",
        "healthtrack_family_monthly": "family",
        "healthtrack_family_yearly": "family",
    }
    plan = plan_map.get(product_id, "free")

    sub = UserSubscription.query.filter_by(user_id=uid).first()
    if not sub:
        sub = UserSubscription(user_id=uid)
        db.session.add(sub)

    sub.plan = plan
    sub.purchase_token = purchase_token
    sub.product_id = product_id
    sub.expires_at = now_ist() + timedelta(days=30 if "monthly" in product_id else 365)

    db.session.commit()
    return jsonify({
        "success": True,
        "message": f"🎉 Upgraded to {plan.title()}!",
        "data": sub.to_dict()
    })


@modules_api_bp.route("/subscription/cancel", methods=["POST"])
@jwt_required()
def cancel_subscription():
    uid = get_jwt_identity()
    sub = UserSubscription.query.filter_by(user_id=uid).first()
    if sub:
        sub.auto_renew = False
        db.session.commit()
    return jsonify({"success": True, "message": "Auto-renewal cancelled"})


# ════════════════════════════════════════════════════════════════
# HEALTH SCORE HISTORY
# ════════════════════════════════════════════════════════════════

@modules_api_bp.route("/health-score/", methods=["GET"])
@jwt_required()
def health_score():
    uid = get_jwt_identity()
    from utils.health_score import calculate_health_score
    score = calculate_health_score(uid)
    return jsonify({"success": True, "data": score})


@modules_api_bp.route("/health-score/history", methods=["GET"])
@jwt_required()
def health_score_history():
    uid = get_jwt_identity()
    days = request.args.get("days", 30, type=int)
    from models import DailyHealthScore

    since = today_ist() - timedelta(days=days)
    scores = DailyHealthScore.query.filter(
        DailyHealthScore.user_id == uid,
        DailyHealthScore.date >= since
    ).order_by(DailyHealthScore.date.asc()).all()

    return jsonify({
        "success": True,
        "data": {
            "scores": [
                {"date": str(s.date), "score": s.total_score, "grade": s.grade}
                for s in scores
            ],
        }
    })


# ── Helpers ────────────────────────────────────────────────────────

def _parse_date(val):
    if not val:
        return today_ist()
    try:
        return datetime.strptime(str(val)[:10], "%Y-%m-%d").date()
    except Exception:
        return today_ist()


def _auto_create_followup(user_id, visit):
    if not visit.follow_up_date:
        return

    appt = Appointment(
        user_id=user_id,
        title=f"Follow-up: Dr. {visit.doctor_name or 'Unknown'}",
        appointment_type="doctor",
        appointment_date=visit.follow_up_date,
        location=visit.hospital,
        notes=f"Follow-up for: {visit.diagnosis or 'Previous visit'}",
        member_id=visit.member_id,
    )
    db.session.add(appt)