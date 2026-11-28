# routes/api/timeline_api.py — Health Timeline API (Auto-generated)
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from datetime import date, datetime, timedelta

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
    "other": "other",
}


# ══════════════════════════════════════════════════════════════════
# DASHBOARD SUMMARY
# ══════════════════════════════════════════════════════════════════

timeline_api_bp = Blueprint("timeline_api", __name__)


@timeline_api_bp.route("/summary", methods=["GET"])
@jwt_required()
def summary():
    uid = get_jwt_identity()
    member_id = request.args.get("member_id", type=int)
    today = today_ist()
    week_start = today - timedelta(days=7)

    filters = {"user_id": uid}
    if member_id:
        filters["member_id"] = member_id

    all_events = HealthTimelineEvent.get_all(filters=filters)

    today_evts = [e for e in all_events if e.event_date == today]
    week_evts = [e for e in all_events if week_start <= e.event_date <= today]

    def _count(evts, cat):
        return sum(1 for e in evts if EVENT_CATEGORIES.get(e.event_type, "other") == cat)

    return jsonify({"success": True,
        "week_by_category":   {cat: _count(week_evts, cat) for cat in CATEGORIES},
        "missed_medicines":   sum(1 for e in week_evts if e.event_type in ("medicine_missed", "missed")),
        "completed_appts":    sum(1 for e in week_evts if e.event_type in ("appointment", "visit") and "Completed" in (e.title or "")),
        "new_lab_results":    sum(1 for e in week_evts if e.event_type in ("lab", "lab_test")),
        "documents_uploaded": sum(1 for e in week_evts if e.event_type == "document"),
        "score_updates":      sum(1 for e in week_evts if e.event_type in ("score", "health_score")),
        "total_all_time":     len(all_events),
        "categories":         {k: {"icon": v[0], "label": v[1], "color": v[2]} for k, v in CATEGORIES.items()},
    })


# ═══════════════════════════════════════════════════════════════════
# TIMELINE LIST
# ═══════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/", methods=["GET"])
@jwt_required()
def list_timeline():
    uid = get_jwt_identity()
    member_id = request.args.get("member_id", type=int)
    category = request.args.get("category")
    search = request.args.get("search", "").strip()
    sort = request.args.get("sort", "newest")
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 30, type=int)

    # Date filter
    date_from = request.args.get("date_from")
    date_to = request.args.get("date_to")

    filters = {"user_id": uid}
    if member_id:
        filters["member_id"] = member_id
    if category:
        # Filter by event types in this category
        event_types = [k for k, v in EVENT_CATEGORIES.items() if v == category]
        if event_types:
            # We'll filter in Python since Firestore doesn't support IN queries easily
            pass

    events = HealthTimelineEvent.get_all(filters={"user_id": uid}, order_by="-event_date", limit=100)

    if member_id:
        events = [e for e in events if e.member_id == member_id]
    if category:
        events = [e for e in events if EVENT_CATEGORIES.get(e.event_type, "other") == category]

    # Filter by date range
    if date_from:
        try:
            df = date.fromisoformat(date_from[:10])
            events = [e for e in events if e.event_date >= df]
        except:
            pass
    if date_to:
        try:
            dt = date.fromisoformat(date_to[:10])
            events = [e for e in events if e.event_date <= dt]
        except:
            pass

    # Search
    if search:
        events = [e for e in events if search.lower() in (e.title or "").lower() or search.lower() in (e.description or "").lower()]

    # Sort
    if sort == "oldest":
        events.sort(key=lambda e: (e.event_date, e.created_at))
    else:
        events.sort(key=lambda e: (e.event_date, e.created_at), reverse=True)

    # Pagination
    start = (page - 1) * per_page
    end = start + per_page
    paginated = events[start:end]

    # Group by date
    by_date = {}
    for e in paginated:
        ds = str(e.event_date)
        if ds not in by_date:
            by_date[ds] = {"date": ds, "count": 0, "categories": [], "events": []}
        by_date[ds]["count"] += 1
        cat = EVENT_CATEGORIES.get(e.event_type, "other")
        if cat not in by_date[ds]["categories"]:
            by_date[ds]["categories"].append(cat)
        by_date[ds]["events"].append(_enrich(e))

    return jsonify({"success": True, "data": {
        "year": date.today().year, "month": date.today().month,
        "month_name": date.today().strftime("%B %Y"),
        "days": list(by_date.values()),
        "total_events": len(events),
    }})


# ═══════════════════════════════════════════════════════════════════
# DAY VIEW — all events for a specific date
# ═══════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/day", methods=["GET"])
@jwt_required()
def day_view():
    uid = get_jwt_identity()
    day_str = request.args.get("date", str(today_ist()))
    member_id = request.args.get("member_id", type=int)

    try:
        day = date.fromisoformat(day_str[:10])
    except:
        day = today_ist()

    filters = {"user_id": uid, "event_date": day}
    if member_id:
        filters["member_id"] = member_id

    events = HealthTimelineEvent.get_all(filters=filters, order_by="created_at")

    return jsonify({"success": True, "data": {
        "date": str(day),
        "events": [_enrich(e) for e in events],
        "total": len(events),
        "by_category": _group_by_category(events),
    }})


# ═══════════════════════════════════════════════════════════════════
# DELETE event (cascades to source? No — just removes timeline entry)
# ═══════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/<int:eid>", methods=["DELETE"])
@jwt_required()
def delete_event(eid):
    uid = get_jwt_identity()
    e = HealthTimelineEvent.get_by_id_or_404(eid)
    if e.user_id != uid:
        return jsonify({"success": False, "message": "Forbidden"}), 403
    e.delete()
    return jsonify({"success": True, "message": "Event deleted"})


# ═══════════════════════════════════════════════════════════════════
# COMPLETE LIST — for calendar view
# ═══════════════════════════════════════════════════════════════════

@timeline_api_bp.route("/all", methods=["GET"])
@jwt_required()
def all_timeline():
    uid = get_jwt_identity()
    member_id = request.args.get("member_id", type=int)

    filters = {"user_id": uid}
    if member_id:
        filters["member_id"] = member_id

    events = HealthTimelineEvent.get_all(filters=filters, order_by="-event_date", limit=200)

    return jsonify({"success": True, "data": {
        "events": [_enrich(e) for e in events],
        "total": len(events),
    }})


# ═══════════════════════════════════════════════════════════════════
# AUTO-CREATE helpers — called from other modules
# ═══════════════════════════════════════════════════════════════════

def add_event(user_id: int, event_type: str, title: str, description: str = "",
              icon: str = None, event_date=None, member_id: int = None):
    """Add a timeline event. Called automatically from all modules."""
    if event_date is None:
        event_date = today_ist()
    cat = EVENT_CATEGORIES.get(event_type, "other")
    auto_icon = icon or CATEGORIES.get(cat, ("📋",))[0]
    e = HealthTimelineEvent(
        user_id=user_id, event_type=event_type,
        event_date=event_date if isinstance(event_date, date) else today_ist(),
        title=title, description=description or "",
        icon=auto_icon, member_id=member_id,
    )
    e.save()


# ═══════════════════════════════════════════════════════════════════
# PRIVATE
# ════════════════════════════════════════════════════════════════════

def _enrich(e: HealthTimelineEvent) -> dict:
    d = e.to_dict()
    cat = EVENT_CATEGORIES.get(e.event_type, "other")
    cfg = CATEGORIES.get(cat, ("📋", "Other", "#9CA3AF"))
    d = e.to_dict()
    d["category"] = cat
    d["category_icon"] = cfg[0]
    d["category_label"] = cfg[1]
    d["category_color"] = cfg[2]
    d["icon"] = e.icon or cfg[0]
    d["time_str"] = e.created_at.strftime("%I:%M %p") if e.created_at else ""
    return d


def _group_by_category(events):
    result = {}
    for e in events:
        cat = EVENT_CATEGORIES.get(e.event_type, "other")
        if cat not in result:
            cfg = CATEGORIES.get(cat, ("📋", "Other", "#9CA3AF"))
            result[cat] = {"icon": cfg[0], "label": cfg[1], "color": cfg[2], "events": []}
        result[cat]["events"].append(_enrich(e))
    return result