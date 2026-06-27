# ============================================================
# utils/health_score.py — Daily Health Score Calculator
# Computes weighted score from all metrics (0-100)
# ============================================================

import logging
from datetime import date, timedelta, datetime
from sqlalchemy import func

logger = logging.getLogger(__name__)


# Score weights (must sum to 100)
WEIGHTS = {
    "bp":        20,
    "water":     15,
    "sleep":     15,
    "exercise":  15,
    "steps":     10,
    "nutrition": 10,
    "medicine":  10,
    "weight":     5,
}


def compute_score_for_user(user, score_date=None):
    """
    Compute daily health score for a user.
    Returns DailyHealthScore model instance (not saved — caller saves it).
    """
    from models import (
        HealthMetric, SleepLog, StepLog, ExerciseLog,
        MedicineLog, Medicine, NutritionDailyLog, DailyHealthScore
    )

    if score_date is None:
        score_date = date.today()

    scores = {}

    # ── BP Score ──────────────────────────────────────────────
    if user.has_bp:
        latest_bp = HealthMetric.query.filter(
            HealthMetric.user_id    == user.id,
            HealthMetric.metric_type == "bp",
            func.date(HealthMetric.recorded_at) == score_date
        ).order_by(HealthMetric.recorded_at.desc()).first()

        if latest_bp:
            s, d = latest_bp.value_1 or 0, latest_bp.value_2 or 0
            if s < 120 and d < 80:    scores["bp"] = 100
            elif s < 130 and d < 80:  scores["bp"] = 80
            elif s < 140 or d < 90:   scores["bp"] = 60
            elif s < 160 or d < 100:  scores["bp"] = 40
            elif s < 180 or d < 120:  scores["bp"] = 20
            else:                      scores["bp"] = 0
        else:
            scores["bp"] = 0  # Not tracked = 0
    else:
        scores["bp"] = 100  # Not applicable = full score

    # ── Water Score ───────────────────────────────────────────
    water_total = HealthMetric.query.filter(
        HealthMetric.user_id     == user.id,
        HealthMetric.metric_type == "water",
        func.date(HealthMetric.recorded_at) == score_date
    ).with_entities(func.sum(HealthMetric.value_1)).scalar() or 0

    target_water = user.goals.target_water_litres if user.goals else 2.5
    if target_water:
        pct = min(100, int(float(water_total) / target_water * 100))
        scores["water"] = pct
    else:
        scores["water"] = 0

    # ── Sleep Score ───────────────────────────────────────────
    sleep = SleepLog.query.filter_by(user_id=user.id, log_date=score_date).first()
    if sleep and sleep.duration_hours:
        h = sleep.duration_hours
        target_sleep = user.goals.target_sleep_hours if user.goals else 7.5
        if h >= target_sleep:        scores["sleep"] = 100
        elif h >= target_sleep - 1:  scores["sleep"] = 75
        elif h >= target_sleep - 2:  scores["sleep"] = 50
        elif h >= 5:                 scores["sleep"] = 30
        else:                         scores["sleep"] = 10
        # Quality bonus
        if sleep.quality:
            quality_bonus = (sleep.quality - 3) * 5  # -10 to +10
            scores["sleep"] = max(0, min(100, scores["sleep"] + quality_bonus))
    else:
        scores["sleep"] = 0

    # ── Steps Score ───────────────────────────────────────────
    step_log = StepLog.query.filter_by(user_id=user.id, log_date=score_date).first()
    target_steps = user.goals.target_steps if user.goals else 8000
    if step_log and step_log.steps:
        pct = min(100, int(step_log.steps / target_steps * 100))
        scores["steps"] = pct
    else:
        scores["steps"] = 0

    # ── Exercise Score ────────────────────────────────────────
    exercise_today = ExerciseLog.query.filter_by(
        user_id=user.id, log_date=score_date
    ).all()

    target_mins = user.goals.target_exercise_mins if user.goals else 30
    if exercise_today:
        total_mins = sum(e.duration_minutes or 0 for e in exercise_today)
        pct = min(100, int(total_mins / target_mins * 100))
        scores["exercise"] = pct
    else:
        scores["exercise"] = 0

    # ── Nutrition Score ───────────────────────────────────────
    nutrition = NutritionDailyLog.query.filter_by(
        user_id=user.id, log_date=score_date
    ).first()

    if nutrition and nutrition.total_calories:
        cal_pct = min(100, int(nutrition.total_calories / user.daily_calorie_target * 100)) if user.daily_calorie_target else 0
        pro_pct = min(100, int(nutrition.total_protein / user.daily_protein_target * 100)) if user.daily_protein_target else 0
        sodium  = nutrition.total_sodium or 0
        sodium_score = 100 if sodium < 1500 else (75 if sodium < 2000 else (50 if sodium < 2500 else 25))
        scores["nutrition"] = int((cal_pct * 0.4) + (pro_pct * 0.4) + (sodium_score * 0.2))
    else:
        scores["nutrition"] = 0

    # ── Medicine Score ────────────────────────────────────────
    active_meds = Medicine.query.filter_by(user_id=user.id, active=True).all()
    if active_meds:
        taken = 0
        for med in active_meds:
            log = MedicineLog.query.filter_by(
                medicine_id=med.id, log_date=score_date, taken=True
            ).first()
            if log: taken += 1
        scores["medicine"] = int(taken / len(active_meds) * 100)
    else:
        scores["medicine"] = 100  # No meds = full score

    # ── Weight Score ──────────────────────────────────────────
    goals = user.goals
    if goals and goals.target_weight_kg and goals.start_weight_kg:
        latest_w = HealthMetric.query.filter_by(
            user_id=user.id, metric_type="weight"
        ).order_by(HealthMetric.recorded_at.desc()).first()
        if latest_w:
            total_needed = abs(goals.start_weight_kg - goals.target_weight_kg)
            achieved     = abs(goals.start_weight_kg - latest_w.value_1)
            if total_needed > 0:
                scores["weight"] = min(100, int(achieved / total_needed * 100))
            else:
                scores["weight"] = 100
        else:
            scores["weight"] = 0
    else:
        scores["weight"] = 50  # No goal set = neutral

    # ── Weighted Total ────────────────────────────────────────
    total = sum(scores.get(k, 0) * w for k, w in WEIGHTS.items()) // 100

    grade = "Critical"
    if total >= 90:   grade = "Excellent"
    elif total >= 75: grade = "Good"
    elif total >= 60: grade = "Fair"
    elif total >= 40: grade = "Needs Attention"

    # Create or update record
    from models import DailyHealthScore
    from app import db

    existing = DailyHealthScore.query.filter_by(
        user_id=user.id, score_date=score_date
    ).first()

    if existing:
        hs = existing
    else:
        hs = DailyHealthScore(user_id=user.id, score_date=score_date)
        db.session.add(hs)

    hs.bp_score        = scores.get("bp", 0)
    hs.water_score     = scores.get("water", 0)
    hs.sleep_score     = scores.get("sleep", 0)
    hs.exercise_score  = scores.get("exercise", 0)
    hs.steps_score     = scores.get("steps", 0)
    hs.nutrition_score = scores.get("nutrition", 0)
    hs.medicine_score  = scores.get("medicine", 0)
    hs.weight_score    = scores.get("weight", 0)
    hs.total_score     = total
    hs.grade           = grade
    hs.computed_at     = datetime.utcnow()

    return hs


def compute_all_scores():
    """
    Scheduler job: compute health scores for ALL users at end of day.
    """
    from app import app, db
    with app.app_context():
        from models import User
        users = User.query.filter_by(is_active=True).all()
        count = 0
        for user in users:
            try:
                hs = compute_score_for_user(user)
                count += 1
            except Exception as e:
                logger.error(f"Score error for user {user.id}: {e}")
                continue
        try:
            db.session.commit()
            logger.info(f"Health scores computed for {count} users")
        except Exception as e:
            db.session.rollback()
            logger.error(f"Score commit error: {e}")