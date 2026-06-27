# utils/scheduler.py — Background job scheduler
from datetime import date, timedelta
import logging
logger = logging.getLogger(__name__)

def run_daily_aggregation():
    from app import app, db
    with app.app_context():
        from models import User, NutritionDailyLog, MealPlan, MealItem
        from sqlalchemy import func
        yesterday = date.today() - timedelta(days=1)
        users = User.query.filter_by(is_active=True).all()
        for user in users:
            try:
                plan = MealPlan.query.filter_by(user_id=user.id, is_active=True).first()
                if not plan: continue
                day_name = yesterday.strftime("%A")
                items = MealItem.query.filter_by(plan_id=plan.id, day=day_name).all()
                totals = {"calories":0,"protein":0,"carbs":0,"fats":0,"fiber":0,"sodium":0}
                completed = 0
                for item in items:
                    if item.completed:
                        completed += 1
                        r = item.recipe
                        totals["calories"] += r.calories or 0
                        totals["protein"]  += r.protein  or 0
                        totals["carbs"]    += r.carbs    or 0
                        totals["fats"]     += r.fats     or 0
                        totals["fiber"]    += r.fiber    or 0
                        totals["sodium"]   += r.sodium   or 0
                log = NutritionDailyLog.query.filter_by(user_id=user.id, log_date=yesterday).first()
                if not log:
                    log = NutritionDailyLog(user_id=user.id, log_date=yesterday)
                    db.session.add(log)
                for k, v in totals.items():
                    setattr(log, f"total_{k}", v)
                log.meals_completed = completed
                log.meals_planned   = len(items)
            except Exception as e:
                logger.error(f"Aggregation error user {user.id}: {e}")
        try:
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            logger.error(f"Aggregation commit error: {e}")

def run_weekly_insights():
    from app import app, db
    with app.app_context():
        from models import User
        from utils.health_score import compute_score_for_user
        users = User.query.filter_by(is_active=True).all()
        for user in users:
            try:
                compute_score_for_user(user)
            except Exception as e:
                logger.error(f"Weekly insight error user {user.id}: {e}")
        try:
            db.session.commit()
        except Exception as e:
            db.session.rollback()