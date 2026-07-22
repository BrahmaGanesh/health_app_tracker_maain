# routes/api/lab_api.py — Complete Lab Tests API (Premium/Family)
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from datetime import date, datetime, timedelta
from extensions import db
from models import User, now_ist, today_ist
from models import LabTest, UserSubscription, HealthTimelineEvent

lab_api_bp = Blueprint("lab_api", __name__)


# ── Plan guard ─────────────────────────────────────────────────────
def _plan(uid):
    sub = UserSubscription.query.filter_by(user_id=uid).first()
    return sub.plan if sub and sub.is_active else "free"

def _require_premium(uid):
    if _plan(uid) not in ("premium","family"):
        return jsonify({"success":False,"message":"🔒 Lab test tracking requires Premium plan","upgrade_required":True}), 403
    return None


# ── Category metadata ──────────────────────────────────────────────
CATEGORIES = {
    "blood_sugar":  ("🩸", "Blood Sugar",   ["Fasting Blood Glucose","Post-meal Glucose","Random Blood Glucose"]),
    "hba1c":        ("📊", "HbA1c",         ["HbA1c (Glycated Hemoglobin)"]),
    "cholesterol":  ("🫀", "Cholesterol",    ["Total Cholesterol","HDL","LDL","Triglycerides"]),
    "kidney":       ("🫘", "Kidney",         ["Creatinine","BUN","eGFR","Uric Acid"]),
    "liver":        ("🫁", "Liver",          ["ALT (SGPT)","AST (SGOT)","Bilirubin","ALP"]),
    "thyroid":      ("🦋", "Thyroid",        ["TSH","T3","T4"]),
    "cbc":          ("🔬", "CBC",            ["Hemoglobin","WBC","RBC","Platelets","Hematocrit"]),
    "vitamin":      ("☀️", "Vitamins",       ["Vitamin D","Vitamin B12","Iron","Ferritin"]),
    "other":        ("🧪", "Other Tests",    []),
}

UNITS = {
    "blood_sugar":"mg/dL","hba1c":"%","cholesterol":"mg/dL",
    "creatinine":"mg/dL","alt":"U/L","ast":"U/L","tsh":"mIU/L",
    "vitamin_d":"ng/mL","vitamin_b12":"pg/mL","hemoglobin":"g/dL",
    "wbc":"K/µL","rbc":"M/µL","platelets":"K/µL",
}


# ════════════════════════════════════════════════════════════════
# DASHBOARD
# ════════════════════════════════════════════════════════════════

@lab_api_bp.route("/dashboard", methods=["GET"])
@jwt_required()
def dashboard():
    uid   = get_jwt_identity()
    err   = _require_premium(uid)
    if err: return err

    member_id = request.args.get("member_id", type=int)
    q = LabTest.query.filter_by(user_id=uid)
    if member_id: q = q.filter_by(member_id=member_id)
    all_tests = q.order_by(LabTest.test_date.desc()).all()

    latest_per_type = {}
    for t in all_tests:
        if t.test_category not in latest_per_type:
            latest_per_type[t.test_category] = t

    abnormal_count = sum(1 for t in latest_per_type.values() if t.is_abnormal)
    last_updated   = max((t.test_date for t in all_tests), default=None)

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


# ════════════════════════════════════════════════════════════════
# LIST + FILTER
# ════════════════════════════════════════════════════════════════

@lab_api_bp.route("/", methods=["GET"])
@jwt_required()
def list_tests():
    uid   = get_jwt_identity()
    err   = _require_premium(uid)
    if err: return err

    category  = request.args.get("category")
    member_id = request.args.get("member_id", type=int)
    search    = request.args.get("search", "").strip()
    sort      = request.args.get("sort", "newest")   # newest / oldest

    q = LabTest.query.filter_by(user_id=uid)
    if category:  q = q.filter_by(test_category=category)
    if member_id: q = q.filter_by(member_id=member_id)
    if search:    q = q.filter(LabTest.test_name.ilike(f"%{search}%"))
    q = q.order_by(LabTest.test_date.desc() if sort == "newest" else LabTest.test_date.asc())
    tests = q.limit(100).all()

    # Trend: compare latest vs previous
    enriched = []
    for t in tests:
        prev = LabTest.query.filter(
            LabTest.user_id == uid,
            LabTest.test_name == t.test_name,
            LabTest.test_date < t.test_date,
        ).order_by(LabTest.test_date.desc()).first()

        trend = "→"
        if prev:
            diff = t.value - prev.value
            trend = "↑" if diff > 0.5 else "↓" if diff < -0.5 else "→"

        d = t.to_dict(include_linked_doc=True)
        d["trend"]        = trend
        d["prev_value"]   = prev.value if prev else None
        d["prev_date"]    = str(prev.test_date) if prev else None
        d["change"]       = round(t.value - prev.value, 2) if prev else None
        enriched.append(d)

    return jsonify({"success": True, "data": {
        "tests": enriched,
        "total": len(enriched),
        "abnormal_count": sum(1 for t in tests if t.is_abnormal),
    }})


# ════════════════════════════════════════════════════════════════
# GRAPH DATA — for fl_chart
# ════════════════════════════════════════════════════════════════

@lab_api_bp.route("/graph", methods=["GET"])
@jwt_required()
def graph_data():
    uid       = get_jwt_identity()
    err       = _require_premium(uid)
    if err: return err

    category  = request.args.get("category", "blood_sugar")
    test_name = request.args.get("test_name")
    member_id = request.args.get("member_id", type=int)
    period    = request.args.get("period", "6m")   # 3m / 6m / 1y / all

    cutoff_map = {"3m": 90, "6m": 180, "1y": 365}
    since_days = cutoff_map.get(period, 180)
    since      = today_ist() - timedelta(days=since_days) if period != "all" else date(2010, 1, 1)

    q = LabTest.query.filter(LabTest.user_id == uid, LabTest.test_date >= since)
    if category:  q = q.filter_by(test_category=category)
    if test_name: q = q.filter_by(test_name=test_name)
    if member_id: q = q.filter_by(member_id=member_id)
    tests = q.order_by(LabTest.test_date.asc()).all()

    if not tests:
        return jsonify({"success": True, "data": {"points": [], "stats": {}}})

    values = [t.value for t in tests]
    stats  = {
        "min": min(values), "max": max(values), "avg": round(sum(values)/len(values), 2),
        "latest": values[-1], "latest_status": tests[-1].status,
        "latest_color": tests[-1].status_color,
        "points_count": len(tests),
    }

    # Reference lines
    cat_info = CATEGORIES.get(category, ("🧪","","[]"))
    ref_ranges = LabTest.DEFAULT_RANGES.get(test_name.lower().replace(" ","_") if test_name else category, [])
    ref_lines  = [{"label": r[0], "low": r[1], "high": r[2]} for r in ref_ranges if r[2] < 9000]

    return jsonify({"success": True, "data": {
        "points": [{"date": str(t.test_date), "value": t.value, "status": t.status, "color": t.status_color} for t in tests],
        "stats": stats,
        "ref_lines": ref_lines,
        "unit": tests[0].unit if tests else "",
        "test_name": test_name or category,
    }})


# ════════════════════════════════════════════════════════════════
# ADD LAB TEST
# ════════════════════════════════════════════════════════════════

@lab_api_bp.route("/", methods=["POST"])
@jwt_required()
def add_test():
    uid = get_jwt_identity()
    err = _require_premium(uid)
    if err: return err

    d = request.get_json() or {}
    required = ["test_category", "test_name", "value"]
    for f in required:
        if not d.get(f):
            return jsonify({"success": False, "message": f"{f} is required"}), 400

    def _date(v):
        if not v: return today_ist()
        try: return date.fromisoformat(str(v)[:10])
        except: return today_ist()

    test = LabTest(
        user_id=uid,
        test_category=d["test_category"],
        test_name=d["test_name"].strip(),
        value=float(d["value"]),
        unit=d.get("unit") or UNITS.get(d["test_category"], ""),
        ref_range_low=float(d["ref_range_low"]) if d.get("ref_range_low") is not None else None,
        ref_range_high=float(d["ref_range_high"]) if d.get("ref_range_high") is not None else None,
        ref_range_label=d.get("ref_range_label", "").strip() or None,
        test_date=_date(d.get("test_date")),
        lab_name=d.get("lab_name","").strip() or None,
        doctor_name=d.get("doctor_name","").strip() or None,
        notes=d.get("notes","").strip() or None,
        document_id=d.get("document_id"),
        repeat_reminder_months=d.get("repeat_reminder_months"),
        member_id=d.get("member_id"),
    )
    db.session.add(test)

    # Timeline event
    db.session.add(HealthTimelineEvent(
        user_id=uid, event_type="lab", event_date=test.test_date,
        title=f"🧪 {test.test_name}: {test.value} {test.unit or ''}",
        description=f"{test.lab_name or 'Lab'} · Status: {test.status}",
        icon="🧪", member_id=test.member_id,
    ))

    # Schedule repeat reminder
    if test.repeat_reminder_months:
        _create_repeat_reminder(uid, test)

    db.session.commit()
    return jsonify({"success": True, "message": f"🧪 {test.test_name} saved", "data": test.to_dict(include_linked_doc=True)}), 201


# ════════════════════════════════════════════════════════════════
# UPDATE / DELETE
# ════════════════════════════════════════════════════════════════

@lab_api_bp.route("/<int:tid>", methods=["PUT"])
@jwt_required()
def update_test(tid):
    uid  = get_jwt_identity()
    test = LabTest.query.filter_by(id=tid, user_id=uid).first_or_404()
    d    = request.get_json() or {}

    for f in ["test_name","test_category","unit","lab_name","doctor_name","notes","ref_range_label","document_id","repeat_reminder_months"]:
        if f in d: setattr(test, f, d[f])
    if "value"         in d: test.value          = float(d["value"])
    if "ref_range_low" in d and d["ref_range_low"] is not None: test.ref_range_low  = float(d["ref_range_low"])
    if "ref_range_high"in d and d["ref_range_high"]is not None: test.ref_range_high = float(d["ref_range_high"])
    if "test_date"     in d:
        try: test.test_date = date.fromisoformat(d["test_date"][:10])
        except: pass

    db.session.commit()
    return jsonify({"success": True, "message": "Updated", "data": test.to_dict(include_linked_doc=True)})


@lab_api_bp.route("/<int:tid>", methods=["DELETE"])
@jwt_required()
def delete_test(tid):
    uid  = get_jwt_identity()
    test = LabTest.query.filter_by(id=tid, user_id=uid).first_or_404()
    name = test.test_name
    # Note: linked Document is NOT deleted
    db.session.delete(test)
    db.session.commit()
    return jsonify({"success": True, "message": f"🗑️ {name} deleted. Linked document is kept."})


# ════════════════════════════════════════════════════════════════
# AI INSIGHTS (Premium/Family)
# ════════════════════════════════════════════════════════════════

@lab_api_bp.route("/<int:tid>/ai-insight", methods=["GET"])
@jwt_required()
def ai_insight(tid):
    uid  = get_jwt_identity()
    err  = _require_premium(uid)
    if err: return err

    test = LabTest.query.filter_by(id=tid, user_id=uid).first_or_404()
    prev = LabTest.query.filter(
        LabTest.user_id == uid,
        LabTest.test_name == test.test_name,
        LabTest.test_date < test.test_date,
    ).order_by(LabTest.test_date.desc()).first()

    try:
        import anthropic
        client = anthropic.Anthropic(api_key=current_app.config.get("ANTHROPIC_API_KEY",""))
        prompt = f"""Lab test result for a health app user:

Test: {test.test_name}
Result: {test.value} {test.unit or ''}
Status: {test.status}
Date: {test.test_date}
Reference Range: {test.ref_range_label or 'Standard range'}
{f'Previous result: {prev.value} {prev.unit or ""} on {prev.test_date}' if prev else 'No previous result.'}

Please:
1. Explain this result in simple, easy-to-understand language (2-3 sentences)
2. Compare with the previous result if available (1-2 sentences)
3. Note if the trend is improving, worsening, or stable
4. If abnormal, recommend they discuss with their healthcare provider

Important: Do NOT provide medical diagnoses. Keep the tone supportive and informative.
Format your response in 3 short paragraphs."""

        resp = client.messages.create(model="claude-haiku-4-5-20251001", max_tokens=400, messages=[{"role":"user","content":prompt}])
        insight = resp.content[0].text
    except Exception as e:
        insight = f"AI insights are temporarily unavailable. ({str(e)[:80]})"

    return jsonify({"success": True, "data": {
        "insight": insight,
        "disclaimer": "⚕️ AI insights are for informational purposes only. Always consult your doctor for medical advice.",
        "test": test.to_dict(),
        "previous": prev.to_dict() if prev else None,
    }})


# ════════════════════════════════════════════════════════════════
# SETTINGS
# ════════════════════════════════════════════════════════════════

@lab_api_bp.route("/settings", methods=["GET", "POST"])
@jwt_required()
def settings():
    from models import UserSettings
    uid = get_jwt_identity()

    if request.method == "GET":
        s = UserSettings.query.filter_by(user_id=uid).first()
        return jsonify({"success": True, "data": {
            "reminders_enabled":   getattr(s, "lab_reminders", True),
            "ai_insights_enabled": getattr(s, "lab_ai_insights", True),
            "reminder_frequency":  getattr(s, "lab_reminder_freq", "none"),
        }})

    d = request.get_json() or {}
    from models import UserSettings
    s = UserSettings.query.filter_by(user_id=uid).first()
    if not s:
        s = UserSettings(user_id=uid); db.session.add(s)
    for field, attr in [("reminders_enabled","lab_reminders"),("ai_insights_enabled","lab_ai_insights"),("reminder_frequency","lab_reminder_freq")]:
        if field in d: setattr(s, attr, d[field])
    db.session.commit()
    return jsonify({"success": True, "message": "Settings saved"})


# ── Available test names + units ───────────────────────────────────
@lab_api_bp.route("/metadata", methods=["GET"])
@jwt_required()
def metadata():
    return jsonify({"success": True, "data": {
        "categories": {k: {"icon": v[0], "label": v[1], "tests": v[2]} for k, v in CATEGORIES.items()},
        "units": UNITS,
    }})


# ── Helper ─────────────────────────────────────────────────────────
def _create_repeat_reminder(user_id, test):
    from models import Reminder
    remind_date = test.test_date + timedelta(days=test.repeat_reminder_months * 30)
    r = Reminder(
        user_id=user_id,
        title=f"🧪 Time for {test.test_name}",
        message=f"Your last {test.test_name} was {test.value} {test.unit or ''} on {test.test_date}. Time for a repeat test.",
        category="lab_test", is_active=True, is_daily=False,
        remind_time="09:00", max_repeats=1, sound_name="health_alert",
    )
    db.session.add(r)