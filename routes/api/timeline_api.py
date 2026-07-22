# routes/api/timeline_api.py — Health Timeline API (Auto-generated)
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from datetime import date, datetime, timedelta
from extensions import db
from models import User, now_ist, today_ist
from models import HealthTimelineEvent, UserSubscription

timeline_api_bp = Blueprint("timeline_api", __name__)

# ── Category config ────────────────────────────────────────────────
CATEGORIES = {
    "vitals":       ("❤️",  "Vitals",       "#EF4444"),
    "medicines":    ("💊",  "Medicines",    "#8B5CF6"),
    "lab":          ("🧪",  "Lab Tests",    "#F59E0B"),
    "appointments": ("📅",  "Appointments", "#3B82F6"),
    "documents":    ("🗂️", "Documents",    "#6B7280"),
    "exercise":     ("🏃",  "Exercise",     "#10B981"),
    "meals":        ("🍽️", "Meals",        "#F97316"),
    "water":        ("💧",  "Water",        "#0EA5E9"),
    "sleep":        ("😴",  "Sleep",        "#7C3AED"),
    "score":        ("📊",  "Health Score", "#22C55E"),
    "family":       ("👨‍👩‍👧", "Family",   "#EC4899"),
    "other":        ("📋",  "Other",        "#9CA3AF"),
}

# ── Event type → category mapping ─────────────────────────────────
EVENT_CATEGORIES = {
    "bp": "vitals", "weight": "vitals", "sugar": "vitals", "heart_rate": "vitals",
    "spo2": "vitals", "bmi": "vitals",
    "water": "water", "sleep": "sleep",
    "medicine": "medicines", "medicine_taken": "medicines",
    "medicine_missed": "medicines", "medicine_skipped": "medicines",
    "ai_verified": "medicines",
    "lab": "lab", "lab_test": "lab",
    "appointment": "appointments", "visit": "appointments",
    "document": "documents",
    "exercise": "exercise",
    "meal": "meals",
    "score": "score", "health_score": "score",
    "family": "family",
}


# ════════════════════════════════════════════════════════════════
# DASHBOARD SUMMARY
# ════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/summary", methods=["GET"])
@jwt_required()
def summary():
    uid        = get_jwt_identity()
    member_id  = request.args.get("member_id", type=int)
    today      = today_ist()
    week_start = today - timedelta(days=7)

    q = HealthTimelineEvent.query.filter_by(user_id=uid)
    if member_id: q = q.filter_by(member_id=member_id)

    all_events = q.all()
    today_evts = [e for e in all_events if e.event_date == today]
    week_evts  = [e for e in all_events if week_start <= e.event_date <= today]

    # Category counts
    def _count(evts, cat):
        return sum(1 for e in evts if EVENT_CATEGORIES.get(e.event_type, "other") == cat)

    return jsonify({"success": True, "data": {
        "today_count":        len(today_evts),
        "week_count":         len(week_evts),
        "today_by_category":  {cat: _count(today_evts, cat) for cat in CATEGORIES},
        "week_by_category":   {cat: _count(week_evts, cat)  for cat in CATEGORIES},
        "missed_medicines":   sum(1 for e in week_evts if e.event_type in ("medicine_missed","missed")),
        "completed_appts":    sum(1 for e in week_evts if e.event_type in ("appointment","visit") and "Completed" in (e.title or "")),
        "new_lab_results":    sum(1 for e in week_evts if e.event_type in ("lab","lab_test")),
        "documents_uploaded": sum(1 for e in week_evts if e.event_type == "document"),
        "score_updates":      sum(1 for e in week_evts if e.event_type in ("score","health_score")),
        "total_all_time":     len(all_events),
        "categories":         {k: {"icon": v[0], "label": v[1], "color": v[2]} for k, v in CATEGORIES.items()},
    }})


# ════════════════════════════════════════════════════════════════
# TIMELINE LIST
# ════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/", methods=["GET"])
@jwt_required()
def list_timeline():
    uid       = get_jwt_identity()
    member_id = request.args.get("member_id", type=int)
    category  = request.args.get("category")          # filter by category
    search    = request.args.get("search", "").strip()
    sort      = request.args.get("sort", "newest")    # newest / oldest
    page      = request.args.get("page", 1, type=int)
    per_page  = request.args.get("per_page", 30, type=int)

    # Date filter
    date_from = request.args.get("date_from")
    date_to   = request.args.get("date_to")

    q = HealthTimelineEvent.query.filter_by(user_id=uid)
    if member_id: q = q.filter_by(member_id=member_id)
    if search:    q = q.filter(HealthTimelineEvent.title.ilike(f"%{search}%"))

    if date_from:
        try: q = q.filter(HealthTimelineEvent.event_date >= date.fromisoformat(date_from))
        except: pass
    if date_to:
        try: q = q.filter(HealthTimelineEvent.event_date <= date.fromisoformat(date_to))
        except: pass

    # Category filter
    if category and category != "all":
        cat_types = [k for k, v in EVENT_CATEGORIES.items() if v == category]
        if cat_types:
            q = q.filter(HealthTimelineEvent.event_type.in_(cat_types))

    q = q.order_by(
        HealthTimelineEvent.event_date.desc() if sort == "newest" else HealthTimelineEvent.event_date.asc(),
        HealthTimelineEvent.created_at.desc(),
    )

    paginated = q.paginate(page=page, per_page=per_page, error_out=False)
    events    = paginated.items

    return jsonify({"success": True, "data": {
        "events":   [_enrich(e) for e in events],
        "total":    paginated.total,
        "page":     page,
        "pages":    paginated.pages,
        "per_page": per_page,
    }})


# ════════════════════════════════════════════════════════════════
# CALENDAR VIEW — events for a specific month
# ════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/calendar", methods=["GET"])
@jwt_required()
def calendar_view():
    uid       = get_jwt_identity()
    year      = request.args.get("year",  today_ist().year,  type=int)
    month     = request.args.get("month", today_ist().month, type=int)
    member_id = request.args.get("member_id", type=int)

    month_start = date(year, month, 1)
    if month == 12: month_end = date(year + 1, 1, 1) - timedelta(days=1)
    else:           month_end = date(year, month + 1, 1) - timedelta(days=1)

    q = HealthTimelineEvent.query.filter(
        HealthTimelineEvent.user_id == uid,
        HealthTimelineEvent.event_date >= month_start,
        HealthTimelineEvent.event_date <= month_end,
    )
    if member_id: q = q.filter_by(member_id=member_id)
    events = q.order_by(HealthTimelineEvent.event_date.asc(), HealthTimelineEvent.created_at.asc()).all()

    # Group by date
    by_date: dict = {}
    for e in events:
        ds = str(e.event_date)
        if ds not in by_date:
            by_date[ds] = {"date": ds, "count": 0, "categories": [], "events": []}
        by_date[ds]["count"] += 1
        cat = EVENT_CATEGORIES.get(e.event_type, "other")
        if cat not in by_date[ds]["categories"]:
            by_date[ds]["categories"].append(cat)
        by_date[ds]["events"].append(_enrich(e))

    return jsonify({"success": True, "data": {
        "year": year, "month": month,
        "month_name": month_start.strftime("%B %Y"),
        "days": list(by_date.values()),
        "total_events": len(events),
    }})


# ════════════════════════════════════════════════════════════════
# DAY VIEW — all events for a specific date
# ════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/day", methods=["GET"])
@jwt_required()
def day_view():
    uid       = get_jwt_identity()
    day_str   = request.args.get("date", str(today_ist()))
    member_id = request.args.get("member_id", type=int)

    try: day = date.fromisoformat(day_str[:10])
    except: day = today_ist()

    q = HealthTimelineEvent.query.filter(
        HealthTimelineEvent.user_id == uid,
        HealthTimelineEvent.event_date == day,
    )
    if member_id: q = q.filter_by(member_id=member_id)
    events = q.order_by(HealthTimelineEvent.created_at.asc()).all()

    return jsonify({"success": True, "data": {
        "date":   str(day),
        "events": [_enrich(e) for e in events],
        "total":  len(events),
        "by_category": _group_by_category(events),
    }})


# ════════════════════════════════════════════════════════════════
# DELETE event (cascades to source? No — just removes timeline entry)
# ════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/<int:eid>", methods=["DELETE"])
@jwt_required()
def delete_event(eid):
    uid = get_jwt_identity()
    e   = HealthTimelineEvent.query.filter_by(id=eid, user_id=uid).first_or_404()
    db.session.delete(e)
    db.session.commit()
    return jsonify({"success": True, "message": "Timeline event removed"})


# ════════════════════════════════════════════════════════════════
# FAMILY — combined timeline
# ════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/family", methods=["GET"])
@jwt_required()
def family_timeline():
    uid  = get_jwt_identity()
    sub  = UserSubscription.query.filter_by(user_id=uid).first()
    if not sub or sub.plan not in ("family",):
        return jsonify({"success": False, "message": "🔒 Family timeline requires Family plan"}), 403

    from models import FamilyMember
    members  = FamilyMember.query.filter_by(owner_id=uid).all()
    page     = request.args.get("page", 1, type=int)

    # Member colour palette
    colours = ["#EF4444","#3B82F6","#10B981","#F59E0B","#8B5CF6","#EC4899"]
    member_colours = {m.id: colours[i % len(colours)] for i, m in enumerate(members)}

    q = HealthTimelineEvent.query.filter_by(user_id=uid).filter(
        HealthTimelineEvent.member_id.in_([m.id for m in members])
    ).order_by(HealthTimelineEvent.event_date.desc(), HealthTimelineEvent.created_at.desc())

    paginated = q.paginate(page=page, per_page=30, error_out=False)
    member_map = {m.id: m.name for m in members}

    events = []
    for e in paginated.items:
        d = _enrich(e)
        d["member_name"]  = member_map.get(e.member_id, "Family")
        d["member_color"] = member_colours.get(e.member_id, "#9CA3AF")
        events.append(d)

    return jsonify({"success": True, "data": {
        "events":  events, "total": paginated.total,
        "page": page, "pages": paginated.pages,
        "members": [{"id": m.id, "name": m.name, "color": member_colours[m.id]} for m in members],
    }})


# ════════════════════════════════════════════════════════════════
# AUTO-CREATE helpers — called from other modules
# ════════════════════════════════════════════════════════════════

def add_event(user_id: int, event_type: str, title: str, description: str = "",
              icon: str = None, event_date=None, member_id: int = None):
    """Add a timeline event. Called automatically from all modules."""
    if event_date is None:
        event_date = today_ist()
    cat  = EVENT_CATEGORIES.get(event_type, "other")
    auto_icon = icon or CATEGORIES.get(cat, ("📋",))[0]
    e = HealthTimelineEvent(
        user_id=user_id, event_type=event_type,
        event_date=event_date if isinstance(event_date, date) else today_ist(),
        title=title, description=description or "",
        icon=auto_icon, member_id=member_id,
    )
    db.session.add(e)
    # Commit lazily — caller commits


# ═══════════════════════════════════════════════════════════════
# PRIVATE
# ═══════════════════════════════════════════════════════════════

def _enrich(e: HealthTimelineEvent) -> dict:
    d   = e.to_dict()
    cat = EVENT_CATEGORIES.get(e.event_type, "other")
    cfg = CATEGORIES.get(cat, ("📋", "Other", "#9CA3AF"))
    d["category"]       = cat
    d["category_icon"]  = cfg[0]
    d["category_label"] = cfg[1]
    d["category_color"] = cfg[2]
    d["icon"]           = e.icon or cfg[0]
    d["time_str"]       = e.created_at.strftime("%I:%M %p") if e.created_at else ""
    return d


def _group_by_category(events):
    result = {}
    for e in events:
        cat = EVENT_CATEGORIES.get(e.event_type, "other")
        if cat not in result:
            cfg = CATEGORIES.get(cat, ("📋","Other","#9CA3AF"))
            result[cat] = {"icon": cfg[0], "label": cfg[1], "color": cfg[2], "events": []}
        result[cat]["events"].append(_enrich(e))
    return result

from datetime import date