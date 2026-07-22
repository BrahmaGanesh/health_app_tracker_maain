# routes/api/medicine_api.py — Complete Medicine Module API
import json
from datetime import date, datetime, timedelta
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from extensions import db
from models import User, now_ist, today_ist
from models import Medicine, MedicineLog, UserSubscription
from utils.firebase_push import send_push_to_user

medicine_api_bp = Blueprint("medicine_api", __name__)

# ── Plan helpers ───────────────────────────────────────────────────
def _plan(uid):
    sub = UserSubscription.query.filter_by(user_id=uid).first()
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
    uid     = get_jwt_identity()
    today   = today_ist()
    meds    = Medicine.query.filter_by(user_id=uid, is_active=True).all()
    plan    = _plan(uid)
    limit   = _med_limit(uid)

    today_logs = {}
    for m in meds:
        log = MedicineLog.query.filter_by(medicine_id=m.id, log_date=today).first()
        today_logs[m.id] = log.status if log else "pending"

    total       = len(meds)
    due_today   = total
    pending     = sum(1 for mid, st in today_logs.items() if st == "pending")
    taken       = sum(1 for mid, st in today_logs.items() if st in ("taken", "ai_verified"))
    missed      = sum(1 for mid, st in today_logs.items() if st == "missed")
    skipped     = sum(1 for mid, st in today_logs.items() if st == "skipped")
    low_stock   = sum(1 for m in meds if m.stock_count <= m.low_stock_threshold)
    completion  = round((taken / total) * 100) if total > 0 else 0

    return jsonify({"success": True, "data": {
        "total": total, "due_today": due_today,
        "pending": pending, "taken": taken, "missed": missed,
        "skipped": skipped, "low_stock": low_stock,
        "completion_pct": completion,
        "limit": limit, "used": total, "can_add": total < limit,
        "plan": plan, "is_premium": _is_premium(uid),
    }})


# ════════════════════════════════════════════════════════════════
# LIST MEDICINES
# ════════════════════════════════════════════════════════════════

@medicine_api_bp.route("/", methods=["GET"])
@jwt_required()
def get_medicines():
    uid       = get_jwt_identity()
    member_id = request.args.get("member_id", type=int)
    search    = request.args.get("search", "").strip()
    status_f  = request.args.get("status")
    schedule_f= request.args.get("schedule")
    sort_by   = request.args.get("sort", "time")  # name/time/date_added

    q = Medicine.query.filter_by(user_id=uid, is_active=True)
    if member_id:  q = q.filter_by(member_id=member_id)
    if search:     q = q.filter(Medicine.name.ilike(f"%{search}%"))
    if schedule_f: q = q.filter_by(schedule_type=schedule_f)

    sort_map = {"name": Medicine.name.asc(), "date_added": Medicine.created_at.desc()}
    q = q.order_by(sort_map.get(sort_by, Medicine.name.asc()))
    meds = q.all()

    # Filter by today status
    if status_f:
        today   = today_ist()
        filtered = []
        for m in meds:
            log = MedicineLog.query.filter_by(medicine_id=m.id, log_date=today).first()
            st  = log.status if log else "pending"
            if st == status_f:
                filtered.append(m)
        meds = filtered

    return jsonify({"success": True, "data": {
        "medicines": [m.to_dict() for m in meds],
        "low_stock": [m.to_dict() for m in meds if m.stock_count <= m.low_stock_threshold],
        "total": len(meds),
        "limit": _med_limit(uid),
        "can_add": len(meds) < _med_limit(uid),
    }})


# ════════════════════════════════════════════════════════════════
# ADD MEDICINE
# ════════════════════════════════════════════════════════════════

@medicine_api_bp.route("/", methods=["POST"])
@jwt_required()
def add_medicine():
    uid   = get_jwt_identity()
    count = Medicine.query.filter_by(user_id=uid, is_active=True).count()
    limit = _med_limit(uid)

    if count >= limit:
        plan = _plan(uid)
        return jsonify({
            "success": False,
            "message": f"🔒 {plan.title()} plan allows {limit} medicines. Upgrade for more.",
            "upgrade_required": True, "used": count, "limit": limit,
        }), 403

    d = request.get_json() or {}
    if not d.get("name"):
        return jsonify({"success": False, "message": "Medicine name required"}), 400

    # Parse start/end date
    def _date(val):
        if not val: return None
        try: return date.fromisoformat(str(val)[:10])
        except: return None

    med = Medicine(
        user_id=uid,
        name=d["name"].strip(),
        generic_name=(d.get("generic_name") or "").strip() or None,
        dosage=(d.get("dosage") or "").strip() or None,
        medicine_type=d.get("medicine_type", "tablet"),
        with_food=d.get("with_food", "after_food"),
        condition_name=(d.get("condition_name") or "").strip() or None,
        prescribed_by=(d.get("prescribed_by") or "").strip() or None,
        notes=(d.get("notes") or "").strip() or None,
        schedule_type=d.get("schedule_type", "morning"),
        custom_times_json=json.dumps(d.get("custom_times", [])),
        start_date=_date(d.get("start_date")) or today_ist(),
        end_date=_date(d.get("end_date")),
        stock_count=int(d.get("stock_count", 0)),
        low_stock_threshold=int(d.get("low_stock_threshold", 5)),
        auto_reduce_stock=bool(d.get("auto_reduce_stock", True)),
        reminder_enabled=bool(d.get("reminder_enabled", True)),
        snooze_minutes=int(d.get("snooze_minutes", 10)),
        max_reminders=int(d.get("max_reminders", 3) if _is_premium(uid) else 1),
        reminder_sound=d.get("reminder_sound", "medicine"),
        caregiver_alert=bool(d.get("caregiver_alert", False)) and _is_family_plan(uid),
        member_id=d.get("member_id"),
    )
    db.session.add(med)
    db.session.commit()

    # Auto-create reminder
    if med.reminder_enabled:
        _create_med_reminders(uid, med)

    return jsonify({"success": True, "message": f"💊 {med.name} added", "data": med.to_dict()}), 201


# ════════════════════════════════════════════════════════════════
# UPDATE / DELETE MEDICINE
# ════════════════════════════════════════════════════════════════

@medicine_api_bp.route("/<int:mid>", methods=["PUT", "DELETE"])
@jwt_required()
def medicine_detail(mid):
    uid = get_jwt_identity()
    med = Medicine.query.filter_by(id=mid, user_id=uid).first_or_404()

    if request.method == "DELETE":
        med.is_active = False
        db.session.commit()
        return jsonify({"success": True, "message": f"💊 {med.name} deleted"})

    d = request.get_json() or {}
    for f in ["name","generic_name","dosage","medicine_type","with_food","condition_name",
              "prescribed_by","notes","schedule_type","stock_count","low_stock_threshold",
              "auto_reduce_stock","reminder_enabled","snooze_minutes","reminder_sound","caregiver_alert"]:
        if f in d: setattr(med, f, d[f])

    if "custom_times" in d:   med.custom_times_json = json.dumps(d["custom_times"])
    if "end_date"     in d:
        try: med.end_date = date.fromisoformat(d["end_date"][:10])
        except: pass
    if "is_discontinued" in d:
        med.is_discontinued = bool(d["is_discontinued"])
        med.is_active       = not med.is_discontinued

    db.session.commit()
    return jsonify({"success": True, "message": "Updated", "data": med.to_dict()})


# ════════════════════════════════════════════════════════════════
# LOG: MARK TAKEN / SKIP / SNOOZE
# ════════════════════════════════════════════════════════════════

@medicine_api_bp.route("/<int:mid>/log", methods=["POST"])
@jwt_required()
def log_medicine(mid):
    uid    = get_jwt_identity()
    med    = Medicine.query.filter_by(id=mid, user_id=uid).first_or_404()
    d      = request.get_json() or {}
    action = d.get("action", "taken")        # taken / skip / snooze / missed
    sched  = d.get("scheduled_time")
    today  = today_ist()

    # Get or create today's log
    log = MedicineLog.query.filter_by(medicine_id=mid, log_date=today, scheduled_time=sched).first()
    if not log:
        log = MedicineLog(medicine_id=mid, log_date=today, scheduled_time=sched)
        db.session.add(log)

    if action == "taken":
        log.status = "taken"
        log.taken  = True
        # Auto-reduce stock
        if med.auto_reduce_stock and med.stock_count > 0:
            med.stock_count -= 1
            # Low stock push
            if med.stock_count <= med.low_stock_threshold:
                send_push_to_user(uid, f"💊 Low Stock: {med.name}",
                    f"Only {med.stock_count} left. Please refill soon.",
                    data={"type":"medicine","sound":"medicine"})

    elif action == "skip":
        log.status = "skipped"
        log.taken  = False

    elif action == "missed":
        log.status = "missed"
        log.taken  = False
        # Check caregiver alert (Family plan)
        if med.caregiver_alert and _is_family_plan(uid):
            _check_caregiver_alert(uid, med, today)

    elif action == "snooze":
        snooze_mins = int(d.get("snooze_minutes", med.snooze_minutes))
        log.reminder_count = (log.reminder_count or 0) + 1
        db.session.commit()
        return jsonify({"success": True, "message": f"⏰ Snoozed for {snooze_mins} min", "data": log.to_dict()})

    log.logged_at = now_ist()
    db.session.commit()

    status_msg = {"taken":"✅ Marked as taken","skipped":"⚪ Dose skipped","missed":"🔴 Dose missed"}.get(action, "Updated")
    return jsonify({"success": True, "message": status_msg, "data": {**med.to_dict(), "log": log.to_dict()}})


# ════════════════════════════════════════════════════════════════
# AI VERIFICATION (Premium/Family)
# ════════════════════════════════════════════════════════════════

@medicine_api_bp.route("/<int:mid>/verify", methods=["POST"])
@jwt_required()
def ai_verify_medicine(mid):
    uid = get_jwt_identity()
    if not _is_premium(uid):
        return jsonify({"success": False, "message": "🔒 AI Verification requires Premium plan", "upgrade_required": True}), 403

    med   = Medicine.query.filter_by(id=mid, user_id=uid).first_or_404()
    d     = request.get_json() or {}
    img   = d.get("image", "")
    if not img:
        return jsonify({"success": False, "message": "Image data required"}), 400

    today = today_ist()
    log   = MedicineLog.query.filter_by(medicine_id=mid, log_date=today).first()
    if not log:
        return jsonify({"success": False, "message": "Please mark medicine as taken first"}), 400

    # AI verification via Claude
    ai_result = _run_ai_verification(med, img)

    log.ai_verified = ai_result.get("match", False)
    log.ai_result   = json.dumps(ai_result)
    if log.ai_verified:
        log.status = "ai_verified"

    db.session.commit()

    return jsonify({"success": True, "data": {
        "verified": log.ai_verified,
        "status":   log.status,
        "result":   ai_result,
        "note":     "AI confirmation only indicates a medicine was photographed, not necessarily consumed.",
    }})


# ════════════════════════════════════════════════════════════════
# ADHERENCE + HISTORY
# ════════════════════════════════════════════════════════════════

@medicine_api_bp.route("/<int:mid>/history", methods=["GET"])
@jwt_required()
def medicine_history(mid):
    uid  = get_jwt_identity()
    Medicine.query.filter_by(id=mid, user_id=uid).first_or_404()
    days = request.args.get("days", 30, type=int)
    since= today_ist() - timedelta(days=days)
    logs = MedicineLog.query.filter(MedicineLog.medicine_id==mid, MedicineLog.log_date>=since).order_by(MedicineLog.log_date.desc()).all()

    taken   = [l for l in logs if l.status in ("taken","ai_verified")]
    missed  = [l for l in logs if l.status == "missed"]
    skipped = [l for l in logs if l.status == "skipped"]
    pct     = round(len(taken)/len(logs)*100, 1) if logs else 0

    return jsonify({"success": True, "data": {
        "logs": [l.to_dict() for l in logs],
        "adherence_pct": pct,
        "taken_count":   len(taken),
        "missed_count":  len(missed),
        "skipped_count": len(skipped),
        "calendar":      [{"date":str(l.log_date),"status":l.status,"emoji":l.STATUS_EMOJI.get(l.status,"🟡")} for l in logs],
    }})


@medicine_api_bp.route("/<int:mid>/stock", methods=["POST"])
@jwt_required()
def update_stock(mid):
    uid = get_jwt_identity()
    med = Medicine.query.filter_by(id=mid, user_id=uid).first_or_404()
    d   = request.get_json() or {}
    med.stock_count = int(d.get("stock_count", med.stock_count))
    db.session.commit()
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
        s = UserSettings.query.filter_by(user_id=uid).first()
        return jsonify({"success": True, "data": {
            "notifications_enabled": getattr(s, "med_notifications", True),
            "auto_stock_reduction":  getattr(s, "med_auto_stock", True),
            "snooze_duration":       getattr(s, "med_snooze_mins", 10),
            "low_stock_threshold":   getattr(s, "med_low_stock_threshold", 5),
            "reminder_sound":        getattr(s, "med_sound", "medicine"),
            "escalating_reminders":  _is_premium(uid),
        }})

    d = request.get_json() or {}
    from models import UserSettings
    s = UserSettings.query.filter_by(user_id=uid).first()
    if not s:
        s = UserSettings(user_id=uid)
        db.session.add(s)
    for f, attr in [("notifications_enabled","med_notifications"),("auto_stock_reduction","med_auto_stock"),
                    ("snooze_duration","med_snooze_mins"),("low_stock_threshold","med_low_stock_threshold"),("reminder_sound","med_sound")]:
        if f in d: setattr(s, attr, d[f])
    db.session.commit()
    return jsonify({"success": True, "message": "Settings saved"})


# ════════════════════════════════════════════════════════════════
# PRIVATE HELPERS
# ════════════════════════════════════════════════════════════════

def _create_med_reminders(user_id, med):
    from models import Reminder
    for t in med.reminder_times:
        existing = Reminder.query.filter_by(user_id=user_id, title=f"Take {med.name}",remind_time=t).first()
        if not existing:
            r = Reminder(
                user_id=user_id,
                title=f"💊 Take {med.name}",
                message=f"{med.dosage or ''} {med.TYPES.get(med.medicine_type,'Tablet')} — {med.with_food.replace('_',' ').title()}",
                category="medicine", remind_time=t,
                repeat_interval_mins=med.snooze_minutes if _is_premium(user_id) else 0,
                sound_name=med.reminder_sound, sound_enabled=True,
                is_active=True, is_daily=True,
                max_repeats=med.max_reminders,
            )
            db.session.add(r)
    db.session.commit()


def _check_caregiver_alert(user_id, med, today):
    """Send caregiver email if medicine missed 3 days in a row."""
    from datetime import timedelta
    missed_days = 0
    for i in range(3):
        d = today - timedelta(days=i)
        log = MedicineLog.query.filter_by(medicine_id=med.id, log_date=d).first()
        if log and log.status == "missed": missed_days += 1
        else: break

    if missed_days >= 3:
        user = User.query.get(user_id)
        if not user: return
        subject = f"⚠️ HealthTrack Alert: {med.name} missed 3 days"
        body    = f"""
<p>Hi {user.name},</p>
<p>This is a caregiver alert from HealthTrack.</p>
<table border="1" cellpadding="8" style="border-collapse:collapse">
  <tr><td><b>Family Member</b></td><td>{med.member.name if med.member else user.name}</td></tr>
  <tr><td><b>Medicine</b></td><td>{med.name} {med.dosage or ''}</td></tr>
  <tr><td><b>Scheduled Time</b></td><td>{', '.join(med.reminder_times)}</td></tr>
  <tr><td><b>Consecutive Missed Days</b></td><td>3</td></tr>
  <tr><td><b>Date</b></td><td>{today}</td></tr>
</table>
<p>Please check on them. This alert stops when the medicine is taken, discontinued, or deleted.</p>
<p>HealthTrack App</p>
"""
        try:
            from utils.email_sender import send_email
            send_email(user.email, subject, body)
        except Exception as e:
            current_app.logger.error(f"Caregiver alert error: {e}")


def _run_ai_verification(med, base64_image):
    try:
        import anthropic, re
        client = anthropic.Anthropic(api_key=current_app.config.get("ANTHROPIC_API_KEY",""))
        resp   = client.messages.create(
            model="claude-haiku-4-5-20251001", max_tokens=300,
            messages=[{"role":"user","content":[
                {"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":base64_image}},
                {"type":"text","text":f"Does this image show a medicine that could be '{med.name}' ({med.dosage or ''} {med.medicine_type})? "
                 "Reply ONLY with JSON: {{\"match\": true/false, \"confidence\": \"high/medium/low\", \"detected_text\": \"...\", \"note\": \"...\"}}"
                 " Note: matching means the image SHOWS this medicine, NOT that it was consumed."}
            ]}])
        text  = resp.content[0].text
        match = re.search(r'\{.*\}', text, re.DOTALL)
        return json.loads(match.group()) if match else {"match": False, "note": "Could not parse AI response"}
    except Exception as e:
        return {"match": False, "note": str(e)}
