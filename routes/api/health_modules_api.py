from datetime import datetime, timedelta

from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity

from models import (
    now_ist,
    today_ist,
    HabitLog,
    User,
    LabTest,
    DoctorVisit,
    Appointment,
    EmergencyCard,
    TrustedContact,
    UserSubscription,
    HealthTimelineEvent,
)

import os
import base64
import json
import re
import google.generativeai as genai

# Try to load API key from environment, but don't fail if not set
api_key = os.getenv("GEMINI_API_KEY")

# Initialize vision model for image analysis (if API key available)
vision_model = None
if api_key:
    try:
        genai.configure(api_key=api_key)
        # Use gemini-1.5-flash for vision (gemini-pro-vision is deprecated)
        vision_model = genai.GenerativeModel('gemini-1.5-flash')
    except Exception:
        vision_model = None

# Continue with the rest of the module even if API key is not set
# The AI features will be disabled if no key is configured

modules_api_bp = Blueprint("modules_api", __name__)


def _parse_date(val):
    if not val:
        return today_ist()
    try:
        return datetime.strptime(str(val)[:10], "%Y-%m-%d").date()
    except Exception:
        return today_ist()


def _json():
    return request.get_json(silent=True) or {}


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
    appt.save()


@modules_api_bp.route("/lab-tests/", methods=["GET", "POST"])
@jwt_required()
def lab_tests():
    uid = get_jwt_identity()

    if request.method == "GET":
        test_category = request.args.get("test_category", "blood_sugar")
        member_id = request.args.get("member_id", type=int)

        filters = {"user_id": uid, "test_category": test_category}
        if member_id:
            filters["member_id"] = member_id

        tests = LabTest.get_all(
            filters=filters,
            order_by="-test_date",
            limit=50
        )
        return jsonify({"success": True, "tests": [t.to_dict() for t in tests]})

    d = request.get_json(silent=True) or {}
    if not d.get("test_category") or d.get("value") is None:
        return jsonify({"success": False, "message": "test_category and value required"}), 400

    test = LabTest(
        user_id=uid,
        test_category=d["test_category"],
        value=float(d["value"]),
        unit=d.get("unit", ""),
        lab_name=d.get("lab_name", "").strip() or None,
        test_date=_parse_date(d.get("test_date")),
        notes=d.get("notes", "").strip() or None,
        member_id=d.get("member_id"),
    )
    test.save()
    return jsonify({"success": True, "test": test.to_dict()}), 201


@modules_api_bp.route("/lab-tests/<int:test_id>", methods=["GET", "DELETE"])
@jwt_required()
def lab_test_detail(test_id):
    uid = get_jwt_identity()
    test = LabTest.get_by_id_or_404(test_id)
    if test.user_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    if request.method == "GET":
        return jsonify({"success": True, "test": test.to_dict()})

    test.delete()
    return jsonify({"success": True, "message": "Lab test deleted"})


@modules_api_bp.route("/doctor-visits/", methods=["GET", "POST"])
@jwt_required()
def doctor_visits():
    uid = get_jwt_identity()

    if request.method == "GET":
        member_id = request.args.get("member_id", type=int)
        filters = {"user_id": uid}
        if member_id:
            filters["member_id"] = member_id

        visits = DoctorVisit.get_all(filters=filters, order_by="-visit_date", limit=50)
        return jsonify({"success": True, "visits": [v.to_dict() for v in visits]})

    d = request.get_json(silent=True) or {}
    if not d.get("doctor_name") or not d.get("visit_date"):
        return jsonify({"success": False, "message": "doctor_name and visit_date required"}), 400

    visit = DoctorVisit(
        user_id=uid,
        doctor_name=d["doctor_name"].strip(),
        specialty=d.get("specialty", "").strip() or None,
        clinic_name=d.get("clinic_name", "").strip() or None,
        visit_date=_parse_date(d.get("visit_date")),
        reason=d.get("reason", "").strip() or None,
        diagnosis=d.get("diagnosis", "").strip() or None,
        treatment=d.get("treatment", "").strip() or None,
        notes=d.get("notes", "").strip() or None,
        next_visit_date=_parse_date(d.get("follow_up_date")),
        member_id=d.get("member_id", type=int),
    )
    visit.save()
    _auto_create_followup(uid, visit)
    return jsonify({"success": True, "visit": visit.to_dict()}), 201


@modules_api_bp.route("/doctor-visits/<int:visit_id>", methods=["GET", "PUT", "DELETE"])
@jwt_required()
def doctor_visit_detail(visit_id):
    uid = get_jwt_identity()
    visit = DoctorVisit.get_by_id_or_404(visit_id)
    if visit.user_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    if request.method == "GET":
        return jsonify({"success": True, "visit": visit.to_dict()})

    if request.method == "DELETE":
        visit.delete()
        return jsonify({"success": True, "message": "Deleted"})

    d = _json()
    if "doctor_name" in d:
        visit.doctor_name = d["doctor_name"].strip()
    if "specialty" in d:
        visit.specialty = d["specialty"].strip() or None
    if "clinic_name" in d:
        visit.clinic_name = d["clinic_name"].strip() or None
    if "visit_date" in d:
        visit.visit_date = _parse_date(d["visit_date"])
    if "reason" in d:
        visit.reason = d["reason"].strip() or None
    if "diagnosis" in d:
        visit.diagnosis = d["diagnosis"].strip() or None
    if "treatment" in d:
        visit.treatment = d["treatment"].strip() or None
    if "notes" in d:
        visit.notes = d["notes"].strip() or None
    if "follow_up_date" in d:
        visit.follow_up_date = _parse_date(d["follow_up_date"])
    if "member_id" in d:
        visit.member_id = d.get("member_id")

    visit.save()
    _auto_create_followup(uid, visit)
    return jsonify({"success": True, "visit": visit.to_dict()})


@modules_api_bp.route("/appointments/", methods=["GET", "POST"])
@jwt_required()
def appointments():
    uid = get_jwt_identity()

    if request.method == "GET":
        member_id = request.args.get("member_id", type=int)
        status = request.args.get("status", "")
        filters = {"user_id": uid}
        if member_id:
            filters["member_id"] = member_id
        if status:
            filters["status"] = status

        appts = Appointment.get_all(filters=filters, order_by="appointment_date", limit=50)
        return jsonify({"success": True, "appointments": [a.to_dict() for a in appts]})

    d = _json()
    if not d.get("doctor_name") or not d.get("appointment_date"):
        return jsonify({"success": False, "message": "doctor_name and appointment_date required"}), 400

    appt = Appointment(
        user_id=uid,
        doctor_name=d["doctor_name"].strip(),
        specialty=d.get("specialty", "").strip() or None,
        clinic_name=d.get("clinic_name", "").strip() or None,
        appointment_date=_parse_date(d["appointment_date"]),
        appointment_time=d.get("appointment_time", "").strip() or None,
        appointment_type=d.get("appointment_type", "in_person"),
        status=d.get("status", "scheduled"),
        reason=d.get("reason", "").strip() or None,
        notes=d.get("notes", "").strip() or None,
        reminder_enabled=d.get("reminder_enabled", True),
        reminder_minutes_before=d.get("reminder_minutes_before", 60),
        member_id=d.get("member_id", type=int),
    )
    appt.save()
    return jsonify({"success": True, "appointment": appt.to_dict()}), 201


@modules_api_bp.route("/appointments/<int:appt_id>", methods=["GET", "PUT", "DELETE"])
@jwt_required()
def appointment_detail(appt_id):
    uid = get_jwt_identity()
    appt = Appointment.get_by_id_or_404(appt_id)
    if appt.user_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    if request.method == "GET":
        return jsonify({"success": True, "appointment": appt.to_dict()})

    if request.method == "DELETE":
        appt.delete()
        return jsonify({"success": True, "message": "Deleted"})

    d = _json()
    if "doctor_name" in d:
        appt.doctor_name = d["doctor_name"].strip()
    if "specialty" in d:
        appt.specialty = d["specialty"].strip() or None
    if "clinic_name" in d:
        appt.clinic_name = d["clinic_name"].strip() or None
    if "appointment_date" in d:
        appt.appointment_date = _parse_date(d["appointment_date"])
    if "appointment_time" in d:
        appt.appointment_time = d["appointment_time"]
    if "appointment_type" in d:
        appt.appointment_type = d["appointment_type"]
    if "status" in d:
        appt.status = d["status"]
    if "reason" in d:
        appt.reason = d["reason"].strip() or None
    if "notes" in d:
        appt.notes = d["notes"].strip() or None
    if "reminder_enabled" in d:
        appt.reminder_enabled = d["reminder_enabled"]
    if "reminder_minutes_before" in d:
        appt.reminder_minutes_before = d["reminder_minutes_before"]
    if "member_id" in d:
        appt.member_id = d.get("member_id")

    appt.save()
    return jsonify({"success": True, "appointment": appt.to_dict()})


@modules_api_bp.route("/emergency-card", methods=["GET", "POST", "PUT"])
@jwt_required()
def emergency_card():
    uid = get_jwt_identity()
    card = EmergencyCard.get_one(filters={"user_id": uid})

    if request.method == "GET":
        if not card:
            return jsonify({"success": True, "card": None})
        return jsonify({"success": True, "card": card.to_dict()})

    d = _json()
    if not card:
        card = EmergencyCard(user_id=uid)
        card.save()

    for field in ["blood_group", "allergies", "chronic_conditions", "medications",
                  "emergency_contact_name", "emergency_contact_phone", "doctor_name",
                  "doctor_phone", "insurance_provider", "insurance_number", "notes"]:
        if field in d:
            setattr(card, field, d[field])

    card.save()
    return jsonify({"success": True, "card": card.to_dict()})


@modules_api_bp.route("/trusted-contacts", methods=["GET", "POST"])
@jwt_required()
def trusted_contacts():
    uid = get_jwt_identity()

    if request.method == "GET":
        contacts = TrustedContact.get_all(filters={"user_id": uid})
        return jsonify({"success": True, "contacts": [c.to_dict() for c in contacts]})

    d = _json()
    if not d.get("name") or not d.get("phone"):
        return jsonify({"success": False, "message": "name and phone required"}), 400

    contact = TrustedContact(
        user_id=uid,
        name=d["name"].strip(),
        relationship=d.get("relationship", "").strip() or None,
        phone=d["phone"].strip(),
        email=d.get("email", "").strip() or None,
        is_primary=d.get("is_primary", False),
        can_view_health_data=d.get("can_view_health_data", False),
        can_receive_alerts=d.get("can_receive_alerts", False),
    )
    contact.save()
    return jsonify({"success": True, "contact": contact.to_dict()}), 201


@modules_api_bp.route("/trusted-contacts/<int:contact_id>", methods=["PUT", "DELETE"])
@jwt_required()
def trusted_contact_detail(contact_id):
    uid = get_jwt_identity()
    contact = TrustedContact.get_by_id_or_404(contact_id)
    if contact.user_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    if request.method == "DELETE":
        contact.delete()
        return jsonify({"success": True, "message": "Deleted"})

    d = _json()
    for field in ["name", "relationship", "phone", "email", "is_primary", "can_view_health_data", "can_receive_alerts"]:
        if field in d:
            setattr(contact, field, d[field])
    contact.save()
    return jsonify({"success": True, "contact": contact.to_dict()})


@modules_api_bp.route("/habits", methods=["GET", "POST"])
@jwt_required()
def habits():
    uid = get_jwt_identity()

    if request.method == "GET":
        habit_type = request.args.get("type", "")
        filters = {"user_id": uid}
        if habit_type:
            filters["habit_type"] = habit_type
        logs = HabitLog.get_all(filters=filters, order_by="-log_date")
        return jsonify({"success": True, "habits": [h.to_dict() for h in logs]})

    d = _json()
    if not d.get("habit_type"):
        return jsonify({"success": False, "message": "habit_type required"}), 400

    log = HabitLog(
        user_id=uid,
        habit_type=d["habit_type"],
        status=d.get("status", "pending"),
        value=d.get("value"),
        notes=d.get("notes"),
        log_date=_parse_date(d.get("log_date")),
        completed_at=datetime.utcnow() if d.get("status") == "completed" else None,
    )
    log.save()
    return jsonify({"success": True, "habit": log.to_dict()}), 201


@modules_api_bp.route("/habits/<int:log_id>", methods=["PUT", "DELETE"])
@jwt_required()
def habit_detail(log_id):
    uid = get_jwt_identity()
    log = HabitLog.get_by_id_or_404(log_id)
    if log.user_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    if request.method == "DELETE":
        log.delete()
        return jsonify({"success": True, "message": "Deleted"})

    d = _json()
    if "status" in d:
        log.status = d["status"]
        if d["status"] == "completed":
            log.completed_at = datetime.utcnow()
    if "value" in d:
        log.value = d["value"]
    if "notes" in d:
        log.notes = d["notes"]
    if "log_date" in d:
        log.log_date = _parse_date(d["log_date"])
    log.save()
    return jsonify({"success": True, "habit": log.to_dict()})


@modules_api_bp.route("/timeline", methods=["GET"])
@jwt_required()
def timeline():
    uid = get_jwt_identity()
    limit = request.args.get("limit", 50, type=int)
    events = HealthTimelineEvent.get_all(filters={"user_id": uid}, order_by="-event_date", limit=limit)
    return jsonify({"success": True, "events": [e.to_dict() for e in events]})