# routes/business_routes.py — Subscriber & Revenue Dashboard
from flask import Blueprint, render_template, redirect, url_for, make_response
from flask_login import login_required, current_user
from datetime import datetime, timedelta, date
from extensions import db
from models import User, now_ist, today_ist
from models_new_modules import UserSubscription

business_bp = Blueprint("business", __name__, url_prefix="/business")

# ── Admin-only guard ───────────────────────────────────────────────
def admin_required(f):
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_admin:
            return redirect(url_for("auth.login"))
        return f(*args, **kwargs)
    return decorated


@business_bp.route("/")
@login_required
@admin_required
def dashboard():
    today    = today_ist()
    all_subs = UserSubscription.query.all()

    # Plan counts
    premium_count = sum(1 for s in all_subs if s.plan == "premium" and s.is_active)
    family_count  = sum(1 for s in all_subs if s.plan == "family"  and s.is_active)
    free_count    = User.query.count() - premium_count - family_count

    # MRR
    mrr = (premium_count * 199) + (family_count * 349)

    # Last month MRR (simple estimate)
    last_month = datetime.now() - timedelta(days=30)
    last_premium = sum(1 for s in all_subs if s.plan == "premium" and s.created_at <= last_month)
    last_family  = sum(1 for s in all_subs if s.plan == "family"  and s.created_at <= last_month)
    prev_mrr     = (last_premium * 199) + (last_family * 349)
    mrr_growth   = round(((mrr - prev_mrr) / max(prev_mrr, 1)) * 100, 1) if prev_mrr else 0

    # New this month
    month_start = today.replace(day=1)
    new_this_month = sum(1 for s in all_subs if s.created_at and s.created_at.date() >= month_start)

    # Conversion rate
    total_users   = User.query.count()
    paid_users    = premium_count + family_count
    conversion_rate = round((paid_users / max(total_users, 1)) * 100, 1)

    # Expiring in 7 days
    in_7 = today + timedelta(days=7)
    expiring_subs = UserSubscription.query.filter(
        UserSubscription.expires_at != None,
        UserSubscription.expires_at <= datetime.combine(in_7, datetime.min.time()),
        UserSubscription.expires_at > datetime.now(),
        UserSubscription.plan != "free",
    ).all()
    expiring_users = [s.user for s in expiring_subs if s.user]

    # Revenue trend — last 6 months
    revenue_trend = []
    for i in range(5, -1, -1):
        month_dt  = datetime.now().replace(day=1) - timedelta(days=i * 30)
        month_end = (month_dt.replace(day=28) + timedelta(days=4)).replace(day=1)
        month_prem = sum(1 for s in all_subs if s.plan == "premium" and s.created_at and month_dt <= s.created_at < month_end)
        month_fam  = sum(1 for s in all_subs if s.plan == "family"  and s.created_at and month_dt <= s.created_at < month_end)
        revenue_trend.append({
            "month":  month_dt.strftime("%b"),
            "amount": (month_prem * 199) + (month_fam * 349),
        })

    revenue_6m = sum(m["amount"] for m in revenue_trend)

    # Enriched subscriptions list
    subscriptions = []
    for s in all_subs:
        user = s.user
        if not user: continue
        # Determine status
        if s.plan == "free":
            status = "free"
        elif s.expires_at and s.expires_at < datetime.now():
            status = "expired"
        elif s.expires_at and s.expires_at < datetime.now() + timedelta(days=3):
            status = "trial"
        else:
            status = "active"
        # Rough total paid (months active × plan price)
        price    = 199 if s.plan == "premium" else 349 if s.plan == "family" else 0
        months   = max(1, (datetime.now() - s.created_at).days // 30) if s.created_at else 1
        total_paid = price * months
        subscriptions.append({
            "user":       user,
            "user_id":    user.id,
            "plan":       s.plan,
            "status":     status,
            "created_at": s.created_at or datetime.now(),
            "expires_at": s.expires_at,
            "total_paid": total_paid,
        })

    subscriptions.sort(key=lambda x: x["created_at"], reverse=True)

    return render_template("admin/business_dashboard.html",
        today=today,
        mrr=mrr, mrr_growth=mrr_growth,
        total_subscribers=paid_users,
        premium_count=premium_count, family_count=family_count,
        free_count=free_count,
        new_this_month=new_this_month,
        conversion_rate=conversion_rate,
        expiring_7d=len(expiring_users), expiring_users=expiring_users,
        revenue_trend=revenue_trend, revenue_6m=revenue_6m,
        subscriptions=subscriptions,
    )


@business_bp.route("/subscriber/<int:user_id>")
@login_required
@admin_required
def subscriber_detail(user_id):
    user = User.query.get_or_404(user_id)
    sub  = UserSubscription.query.filter_by(user_id=user_id).first()
    return render_template("admin/subscriber_detail.html", user=user, sub=sub, today=today_ist())


@business_bp.route("/export/subscribers")
@login_required
@admin_required
def export_subscribers():
    """Export all subscribers as CSV."""
    subs = UserSubscription.query.all()
    rows = ["Name,Email,Plan,Status,Started,Expires,Total Paid (₹)"]
    for s in subs:
        u = s.user
        if not u: continue
        price  = 199 if s.plan == "premium" else 349 if s.plan == "family" else 0
        months = max(1, (datetime.now() - s.created_at).days // 30) if s.created_at else 1
        total  = price * months
        status = "active" if s.is_active else "expired"
        rows.append(f'{u.name},{u.email},{s.plan},{status},'
                    f'{s.created_at.strftime("%Y-%m-%d") if s.created_at else ""},'
                    f'{s.expires_at.strftime("%Y-%m-%d") if s.expires_at else ""},₹{total}')
    csv_data = "\n".join(rows)
    response = make_response(csv_data)
    response.headers["Content-Disposition"] = "attachment; filename=subscribers.csv"
    response.headers["Content-Type"] = "text/csv"
    return response


@business_bp.route("/api/stats")
@login_required
@admin_required
def api_stats():
    """JSON stats for external dashboard integrations."""
    from flask import jsonify
    all_subs = UserSubscription.query.all()
    premium  = sum(1 for s in all_subs if s.plan == "premium" and s.is_active)
    family   = sum(1 for s in all_subs if s.plan == "family"  and s.is_active)
    return jsonify({
        "mrr":      (premium * 199) + (family * 349),
        "premium":  premium,
        "family":   family,
        "free":     User.query.count() - premium - family,
        "total_users": User.query.count(),
        "as_of":    datetime.now().isoformat(),
    })