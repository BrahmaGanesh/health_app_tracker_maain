# routes/api/meal_api.py — Meal & Recipe API for APK
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_current_user
from datetime import date, datetime, timedelta

from models import (
    Recipe, MealPlan, MealItem, Favorite, GroceryItem,
    NutritionDailyLog
)

meal_api_bp = Blueprint("meal_api", __name__)


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None:
        r["data"] = data
    return jsonify(r), code


def err(msg, code=400):
    return jsonify({"success": False, "message": msg}), code


# ── RECIPE SEARCH & LIST ───────────────────────────────────────

@meal_api_bp.route("/recipes", methods=["GET"])
@jwt_required()
def list_recipes():
    user = get_current_user()
    page = request.args.get("page", 1, type=int) or 1
    per_page = request.args.get("per_page", 12, type=int) or 12

    category = request.args.get("category", "")
    meal_type = request.args.get("meal_type", "")
    diet = request.args.get("diet", "")

    recipes = Recipe.get_all()

    if category:
        recipes = [r for r in recipes if r.category == category]
    if meal_type:
        recipes = [r for r in recipes if r.meal_type == meal_type]
    if diet == "veg":
        recipes = [r for r in recipes if r.is_veg]
    elif diet == "nonveg":
        recipes = [r for r in recipes if not r.is_veg]

    # Pagination (in-memory since Firestore doesn't support offset pagination easily)
    total = len(recipes)
    start = (page - 1) * per_page
    end = start + per_page
    paginated = recipes[start:end]

    fav_ids = {f.recipe_id for f in Favorite.get_by_field("user_id", user.id)}

    recipes_data = []
    for r in paginated:
        d = r.to_dict()
        d["is_favourite"] = r.id in fav_ids
        d["score"] = r.composite_score(user.condition_names)
        recipes_data.append(d)

    categories = sorted(set(
        r.category for r in Recipe.get_all() if r.category
    ))

    return ok({
        "recipes": recipes_data,
        "total": total,
        "page": page,
        "has_more": (start + per_page) < total,
        "categories": categories,
    })


# ── RECIPE DETAIL ─────────────────────────────────────────────

@meal_api_bp.route("/recipes/<int:recipe_id>", methods=["GET"])
@jwt_required()
def get_recipe(recipe_id):
    user = get_current_user()
    recipe = Recipe.get_by_id_or_404(recipe_id)

    fav_list = Favorite.get_all(filters={"user_id": user.id, "recipe_id": recipe.id})
    is_fav = len(fav_list) > 0

    d = recipe.to_dict()
    d["is_favourite"] = is_fav
    d["score"] = recipe.composite_score(user.condition_names)

    # Related recipes (same category or meal_type)
    related_recipes = Recipe.get_all(filters={"category": recipe.category})
    related = [r for r in related_recipes if r.id != recipe.id][:4]

    d["related"] = [r.to_dict() for r in related]
    d["ingredients_list"] = [i.strip() for i in (recipe.ingredients or "").split(",") if i.strip()]

    return ok(d)


# ── TOGGLE FAVOURITE ──────────────────────────────────────────

@meal_api_bp.route("/recipes/<int:recipe_id>/favourite", methods=["POST"])
@jwt_required()
def toggle_favourite(recipe_id):
    user = get_current_user()
    Recipe.get_by_id_or_404(recipe_id)

    existing_list = Favorite.get_all(filters={"user_id": user.id, "recipe_id": recipe_id}, limit=1)
    existing = existing_list[0] if existing_list else None

    if existing:
        existing.delete()
        return ok({"is_favourite": False}, "Removed from favourites")
    else:
        fav = Favorite(user_id=user.id, recipe_id=recipe_id)
        fav.save()
        return ok({"is_favourite": True}, "Added to favourites")


# ── MEAL PLAN ENDPOINTS ────────────────────────────────────────

@meal_api_bp.route("/plans", methods=["GET"])
@jwt_required()
def list_meal_plans():
    user = get_current_user()
    plans = MealPlan.get_all(filters={"user_id": user.id}, order_by="-week_start_date")

    plans_data = []
    for p in plans:
        d = p.to_dict()
        # Count meals
        items = MealItem.get_all(filters={"plan_id": p.id})
        d["meal_count"] = len(items)
        plans_data.append(d)

    return ok({"plans": plans_data})


@meal_api_bp.route("/plans", methods=["POST"])
@jwt_required()
def create_meal_plan():
    user = get_current_user()
    data = request.get_json() or {}

    week_start_str = data.get("week_start_date")
    if not week_start_str:
        return err("week_start_date required", 422)

    week_start = datetime.strptime(week_start_str, "%Y-%m-%d").date()

    # Deactivate previous plans
    active_plans = MealPlan.get_all(filters={"user_id": user.id, "is_active": True})
    for p in active_plans:
        p.is_active = False
        p.save()

    plan = MealPlan(
        user_id=user.id,
        week_start_date=week_start,
        generated_at=datetime.utcnow(),
        is_active=True,
        notes=data.get("notes", "")
    )
    plan.save()

    return ok(plan.to_dict(), "Meal plan created", 201)


@meal_api_bp.route("/plans/<int:plan_id>", methods=["GET"])
@jwt_required()
def get_meal_plan(plan_id):
    user = get_current_user()
    plan = MealPlan.get_by_id_or_404(plan_id)
    if plan.user_id != user.id:
        from flask import abort
        abort(403)

    items = MealItem.get_all(filters={"plan_id": plan.id})
    plan_data = plan.to_dict()
    plan_data["items"] = [item.to_dict() for item in items]

    return ok(plan_data)


@meal_api_bp.route("/plans/<int:plan_id>", methods=["DELETE"])
@jwt_required()
def delete_meal_plan(plan_id):
    user = get_current_user()
    plan = MealPlan.get_by_id_or_404(plan_id)
    if plan.user_id != user.id:
        from flask import abort
        abort(403)

    # Delete items first
    items = MealItem.get_all(filters={"plan_id": plan.id})
    for item in items:
        item.delete()

    plan.delete()
    return ok(None, "Meal plan deleted")


# ── MEAL ITEM ENDPOINTS ────────────────────────────────────────

@meal_api_bp.route("/plans/<int:plan_id>/items", methods=["POST"])
@jwt_required()
def add_meal_item(plan_id):
    user = get_current_user()
    plan = MealPlan.get_by_id_or_404(plan_id)
    if plan.user_id != user.id:
        from flask import abort
        abort(403)

    data = request.get_json() or {}
    recipe_id = data.get("recipe_id")
    day = data.get("day")
    meal_slot = data.get("meal_slot")

    if not all([recipe_id, day, meal_slot]):
        return err("recipe_id, day, meal_slot required", 422)

    recipe = Recipe.get_by_id_or_404(recipe_id)

    # Check for existing slot
    existing_list = MealItem.get_all(filters={"plan_id": plan_id, "day": day, "meal_slot": meal_slot}, limit=1)
    if existing_list:
        return err("Meal slot already filled", 409)

    # Get next slot_order
    existing_items = MealItem.get_all(filters={"plan_id": plan_id, "day": day})
    slot_order = max([i.slot_order for i in existing_items], default=-1) + 1

    item = MealItem(
        plan_id=plan_id,
        recipe_id=recipe_id,
        day=day,
        meal_slot=meal_slot,
        slot_order=slot_order,
        completed=False,
        locked=False,
        note=data.get("note", "")
    )
    item.save()

    return ok(item.to_dict(), "Meal item added", 201)


@meal_api_bp.route("/items/<int:item_id>", methods=["PUT"])
@jwt_required()
def update_meal_item(item_id):
    user = get_current_user()
    item = MealItem.get_by_id_or_404(item_id)

    plan = MealPlan.get_by_id(item.plan_id)
    if not plan or plan.user_id != user.id:
        from flask import abort
        abort(403)

    data = request.get_json() or {}
    if "completed" in data:
        item.completed = data["completed"]
        item.completed_at = datetime.utcnow() if data["completed"] else None
    if "note" in data:
        item.note = data["note"]
    if "locked" in data:
        item.locked = data["locked"]
    if "recipe_id" in data:
        item.recipe_id = data["recipe_id"]

    item.save()
    return ok(item.to_dict(), "Meal item updated")


@meal_api_bp.route("/items/<int:item_id>", methods=["DELETE"])
@jwt_required()
def delete_meal_item(item_id):
    user = get_current_user()
    item = MealItem.get_by_id_or_404(item_id)

    plan = MealPlan.get_by_id(item.plan_id)
    if not plan or plan.user_id != user.id:
        from flask import abort
        abort(403)

    item.delete()
    return ok(None, "Meal item deleted")


# ── DAILY NUTRITION LOG ────────────────────────────────────────

@meal_api_bp.route("/nutrition-log", methods=["GET"])
@jwt_required()
def get_nutrition_log():
    user = get_current_user()
    log_date_str = request.args.get("date")
    log_date = datetime.strptime(log_date_str, "%Y-%m-%d").date() if log_date_str else date.today()

    log = NutritionDailyLog.get_one(filters={"user_id": user.id, "log_date": log_date})

    return ok(log.to_dict() if log else None)


@meal_api_bp.route("/nutrition-log", methods=["POST"])
@jwt_required()
def save_nutrition_log():
    user = get_current_user()
    data = request.get_json() or {}

    log_date_str = data.get("log_date", date.today().isoformat())
    log_date = datetime.strptime(log_date_str, "%Y-%m-%d").date() if isinstance(log_date_str, str) else log_date_str

    log = NutritionDailyLog.get_one(filters={"user_id": user.id, "log_date": log_date})
    if not log:
        log = NutritionDailyLog(user_id=user.id, log_date=log_date)

    log.total_calories = data.get("total_calories", 0)
    log.total_protein = data.get("total_protein", 0)
    log.total_carbs = data.get("total_carbs", 0)
    log.total_fats = data.get("total_fats", 0)
    log.total_fiber = data.get("total_fiber", 0)
    log.total_sodium = data.get("total_sodium", 0)
    log.total_water = data.get("total_water", 0)
    log.meals_completed = data.get("meals_completed", 0)
    log.meals_planned = data.get("meals_planned", 5)

    log.save()

    return ok(log.to_dict(), "Nutrition log saved")


@meal_api_bp.route("/nutrition-log/history", methods=["GET"])
@jwt_required()
def nutrition_history():
    user = get_current_user()
    days = request.args.get("days", 30, type=int) or 30
    since = date.today() - timedelta(days=days)

    logs = NutritionDailyLog.get_all(
        filters={"user_id": user.id, "log_date_gte": since},
        order_by="-log_date"
    )

    return ok({"logs": [l.to_dict() for l in logs]})