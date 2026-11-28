# routes/api/lab_api.py — Complete Lab Tests API (Premium/Family)
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from datetime import date, datetime, timedelta
from models import User, now_ist, today_ist
from models import LabTest, UserSubscription, HealthTimelineEvent

lab_api_bp = Blueprint("lab_api", __name__)


# ── Plan guard ─────────────────────────────────────────────────────
def _plan(uid):
    sub_list = UserSubscription.get_all(filters={"user_id": uid}, limit=1)
    sub = sub_list[0] if sub_list else None
    return sub.plan if sub and sub.is_active else "free"


def _require_premium(uid):
    if _plan(uid) not in ("premium", "family"):
        return jsonify({"success": False, "message": "🔒 Lab test tracking requires Premium plan", "upgrade_required": True}), 403
    return None


# ── Category metadata ──────────────────────────────────────────────
CATEGORIES = {
    "blood_sugar":  ("🩸", "Blood Sugar",   ["Fasting Blood Glucose", "Post-meal Glucose", "Random Blood Glucose"]),
    "hba1c":        ("📊", "HbA1c",         ["HbA1c (Glycated Hemoglobin)"]),
    "cholesterol":  ("🫀", "Cholesterol",    ["Total Cholesterol", "HDL", "LDL", "Triglycerides"]),
    "kidney":       ("🫘", "Kidney",         ["Creatinine", "BUN", "eGFR", "Uric Acid"]),
    "liver":        ("🫁", "Liver",          ["ALT (SGPT)", "AST (SGOT)", "Bilirubin", "ALP"]),
    "thyroid":      ("🦋", "Thyroid",        ["TSH", "T3", "T4"]),
    "cbc":          ("🔬", "CBC",            ["Hemoglobin", "WBC", "RBC", "Platelets", "Hematocrit"]),
    "vitamin":      ("☀️", "Vitamins",       ["Vitamin D", "Vitamin B12", "Iron", "Ferritin"]),
    "cbc":          ("🔬", "CBC",            ["Hemoglobin", "WBC", "RBC", "Platelets", "Hematocrit"]),
    "vitamin":      ("☀️", "Vitamins",       ["Vitamin D", "Vitamin B12", "Iron", "Ferritin"]),
    "other":        ("🧪", "Other Tests",    []),
}

UNITS = {
    "blood_sugar": "mg/dL", "hba1c": "%", "cholesterol": "mg/dL",
    "creatinine": "mg/dL", "alt": "U/L", "ast": "U/L", "tsh": "mIU/L",
    "vitamin_d": "ng/mL", "vitamin_b12": "pg/mL", "hemoglobin": "g/dL",
    "wbc": "K/µL", "rbc": "M/µL", "platelets": "K/µL",
}


# ═════════════════════════════════════════════════════════════════
# DASHBOARD
# ═════════════════════════════════════════════════════════════════

lab_api_bp = Blueprint("lab_api", __name__)


def _require_premium(uid):
    if _plan(uid) not in ("premium", "family"):
        return jsonify({"success": False, "message": "🔒 Lab test tracking requires Premium plan", "upgrade_required": True}), 403
    return None


def _plan(uid):
    sub_list = UserSubscription.get_all(filters={"user_id": uid}, limit=1)
    sub = sub_list[0] if sub_list else None
    return sub.plan if sub and sub.is_active else "free"


# ── Category metadata ──────────────────────────────────────────────
CATEGORIES = {
    "blood_sugar":  ("🩸", "Blood Sugar",   ["Fasting Blood Glucose", "Post-meal Glucose", "Random Blood Glucose"]),
    "hba1c":        ("📊", "HbA1c",         ["HbA1c (Glycated Hemoglobin)"]),
    "cholesterol":  ("🫀", "Cholesterol",    ["Total Cholesterol", "HDL", "LDL", "Triglycerides"]),
    "kidney":       ("🫘", "Kidney",         ["Creatinine", "BUN", "eGFR", "Uric Acid"]),
    "liver":        ("🫁", "Liver",          ["ALT (SGPT)", "AST (SGOT)", "Bilirubin", "ALP"]),
    "thyroid":      ("🦋", "Thyroid",        ["TSH", "T3", "T4"]),
    "cbc":          ("🔬", "CBC",            ["Hemoglobin", "WBC", "RBC", "Platelets", "Hematocrit"]),
    "vitamin":      ("☀️", "Vitamins",       ["Vitamin D", "Vitamin B12", "Iron", "Ferritin"]),
    "other":        ("🧪", "Other Tests",    []),
}

UNITS = {
    "blood_sugar": "mg/dL", "hba1c": "%", "cholesterol": "mg/dL",
    "creatinine": "mg/dL", "alt": "U/L", "ast": "U/L", "tsh": "mIU/L",
    "vitamin_d": "ng/mL", "vitamin_b12": "pg/mL", "hemoglobin": "g/dL",
    "wbc": "K/µL", "rbc": "M/µL", "platelets": "K/µL",
}


# ═════════════════════════════════════════════════════════════════
# DASHBOARD
# ═════════════════════════════════════════════════════════════════

lab_api_bp = Blueprint("lab_api", __name__)


@lab_api_bp.route("/dashboard", methods=["GET"])
@jwt_required()
def dashboard():
    uid = get_jwt_identity()
    err = _require_premium(uid)
    if err: return err

    member_id = request.args.get("member_id", type=int)

    filters = {"user_id": uid}
    if member_id:
        filters["member_id"] = member_id

    all_tests = LabTest.get_all(filters=filters, order_by="-test_date", limit=50)

    latest_per_type = {}
    for t in all_tests:
        if t.test_category not in latest_per_type:
            latest_per_type[t.test_category] = t

    abnormal_count = sum(1 for t in latest_per_type.values() if t.is_abnormal)
    last_updated = max((t.test_date for t in all_tests), default=None)

    # Upcoming recommended (tests not done in 90+ days)
    upcoming = []
    for cat, (icon, label, _) in CATEGORIES.items():
        if cat not in latest_per_type:
            upcoming.append({"category": cat, "icon": icon, "label": label, "last_done": None})
        elif (today_ist() - latest_per_type[cat].test_date).days >= 90:
            upcoming.append({"category": cat, "icon": icon, "label": label, "last_done": str(latest_per_type[cat].test_date)})

    return jsonify({"success": True, "data": {
        "total_tests": len(all_tests),
        "categories_tracked": len(latest_per_type),
        "abnormal_count": abnormal_count,
        "last_updated": str(last_updated) if last_updated else None,
        "latest_per_category": {k: v.to_dict() for k, v in latest_per_type.items()},
        "upcoming_recommended": upcoming[:5],
        "categories": {k: {"icon": v[0], "label": v[1]} for k, v in CATEGORIES.items()},
    }})


# ═════════════════════════════════════════════════════════════════
# LAB TEST CRUD
# ═════════════════════════════════════════════════════════════════

@lab_api_bp.route("/tests", methods=["GET", "POST"])
@jwt_required()
def lab_tests():
    uid = get_jwt_identity()
    err = _require_premium(uid)
    if err: return err

    if request.method == "GET":
        test_category = request.args.get("test_category", "blood_sugar")
        member_id = request.args.get("member_id", type=int)

        filters = {"user_id": uid, "test_category": test_category}
        if member_id:
            filters["member_id"] = member_id

        tests = LabTest.get_all(filters=filters, order_by="-test_date", limit=50)
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


@lab_api_bp.route("/tests/<int:test_id>", methods=["GET", "DELETE"])
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


# ── Category metadata ──────────────────────────────────────────────
CATEGORIES = {
    "blood_sugar":  ("🩸", "Blood Sugar",   ["Fasting Blood Glucose", "Post-meal Glucose", "Random Blood Glucose"]),
    "hba1c":        ("📊", "HbA1c",         ["HbA1c (Glycated Hemoglobin)"]),
    "cholesterol":  ("🫀", "Cholesterol",    ["Total Cholesterol", "HDL", "LDL", "Triglycerides"]),
    "kidney":       ("🫘", "Kidney",         ["Creatinine", "BUN", "eGFR", "Uric Acid"]),
    "liver":        ("🫁", "Liver",          ["ALT (SGPT)", "AST (SGOT)", "Bilirubin", "ALP"]),
    "thyroid":      ("🦋", "Thyroid",        ["TSH", "T3", "T4"]),
    "cbc":          ("🔬", "CBC",            ["Hemoglobin", "WBC", "RBC", "Platelets", "Hematocrit"]),
    "vitamin":      ("☀️", "Vitamins",       ["Vitamin D", "Vitamin B12", "Iron", "Ferritin"]),
    "other":        ("🧪", "Other Tests",    []),
}

UNITS = {
    "blood_sugar": "mg/dL", "hba1c": "%", "cholesterol": "mg/dL",
    "creatinine": "mg/dL", "alt": "U/L", "ast": "U/L", "tsh": "mIU/L",
    "vitamin_d": "ng/mL", "vitamin_b12": "pg/mL", "hemoglobin": "g/dL",
    "wbc": "K/µL", "rbc": "M/µL", "platelets": "K/µL",
}


def _plan(uid):
    sub_list = UserSubscription.get_all(filters={"user_id": uid}, limit=1)
    sub = sub_list[0] if sub_list else None
    return sub.plan if sub and sub.is_active else "free"


def _require_premium(uid):
    if _plan(uid) not in ("premium", "family"):
        return jsonify({"success": False, "message": "🔒 Lab test tracking requires Premium plan", "upgrade_required": True}), 403
    return None


def _parse_date(val):
    if not val:
        return today_ist()
    try:
        return datetime.strptime(str(val)[:10], "%Y-%m-%d").date()
    except Exception:
        return today_ist()


lab_api_bp = Blueprint("lab_api", __name__)