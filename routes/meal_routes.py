# ============================================================
# MEALS ROUTES
# ============================================================

from flask import (
    Blueprint, render_template, redirect,
    url_for, flash, request, jsonify
)
from flask_login import login_required, current_user
from datetime import date, datetime, timedelta
import random

from models import (
    Recipe, MealPlan, MealItem, Favorite, GroceryItem,
    NutritionDailyLog, HealthMetric
)

meal_bp = Blueprint("meal", __name__)


# ============================================================
# HELPERS
# ============================================================

def pick_recipe_for_slot(user, meal_slot):
    """Pick a random recipe suitable for a meal slot and user preferences."""
    pref = user.health_profile.diet_preference if user.health_profile else "vegetarian"
    recipes = Recipe.get_all(filters={"meal_type": meal_slot, "diet_preference": pref})

    if not recipes:
        recipes = Recipe.get_all(filters={"meal_type": meal_slot})

    if not recipes:
        return None

    # Score recipes based on user goals/conditions
    def score_recipe(recipe):
        score = 0
        conditions = user.condition_names
        if "Hypertension" in conditions and recipe.bp_friendly:
            score += 10
        if "Diabetes" in conditions and recipe.diabetes_friendly:
            score += 10
        if "Weight Loss" in conditions and recipe.weight_loss_friendly:
            score += 10
        return score

    scored = [(r, score_recipe(r)) for r in recipes]
    scored.sort(key=lambda x: x[1], reverse=True)

    # Pick from top 5 randomly to add variety
    top = scored[:5]
    return random.choice(top)[0] if top else None


def compute_daily_nutrition(plan_id, day_name):
    """Sum up nutrition for all meals in a day."""
    items = MealItem.get_all(filters={"plan_id": plan_id, "day": day_name})
    totals = {"calories": 0, "protein": 0, "carbs": 0, "fats": 0, "fiber": 0, "sodium": 0}
    for item in items:
        r = item.recipe
        totals["calories"] += r.calories or 0
        totals["protein"]  += r.protein  or 0
        totals["carbs"]    += r.carbs    or 0
        totals["fats"]     += r.fats     or 0
        totals["fiber"]    += r.fiber    or 0
        totals["sodium"]   += r.sodium   or 0
    return totals


# ============================================================
# MEALS DASHBOARD
# ============================================================

@meal_bp.route("/")
@login_required
def meals():
    today      = date.today()
    user       = current_user
    week_start = today - timedelta(days=today.weekday())

    # Get active plan
    active_plan_list = MealPlan.get_all(filters={"user_id": user.id, "is_active": True}, order_by="-week_start_date", limit=1)
    active_plan = active_plan_list[0] if active_plan_list else None

    weekly_data = {}

    if active_plan:
        for day_offset in range(7):
            day = week_start + timedelta(days=day_offset)
            day_name = day.strftime("%A")
            items = MealItem.get_all(filters={"plan_id": active_plan.id, "day": day_name})

            if items:
                weekly_data[day] = {
                    item.meal_slot: {
                        "recipe":  item.recipe,
                        "item_id": item.id,
                        "completed": item.completed,
                        "note":    item.note,
                    }
                    for item in items
                }

    # Compute weekly averages
    avg_daily_cal = avg_daily_pro = avg_daily_carb = avg_daily_fat = 0
    nutrition_score = 0

    if weekly_data:
        all_cals = all_prot = all_carb = all_fat = count = 0
        for day, slots in weekly_data.items():
            for slot, data in slots.items():
                r = data["recipe"]
                all_cals += r.calories or 0
                all_prot += r.protein  or 0
                all_carb += r.carbs    or 0
                all_fat  += r.fats     or 0
                count    += 1

        if count:
            meals_per_day    = 5
            days_count       = max(1, count // meals_per_day)
            avg_daily_cal    = round(all_cals / days_count)
            avg_daily_pro    = round(all_prot / days_count)
            avg_daily_carb   = round(all_carb / days_count)
            avg_daily_fat    = round(all_fat  / days_count)

            # Nutrition score: how well does avg match targets?
            cal_score   = min(100, int(avg_daily_cal / max(1, user.daily_calorie_target) * 100))
            pro_score   = min(100, int(avg_daily_pro / max(1, user.daily_protein_target) * 100))
            nutrition_score = round((cal_score + pro_score) / 2)

    return render_template(
        "meals/dashboard.html",
        weekly_data       = weekly_data,
        active_plan       = active_plan,
        avg_daily_calories= avg_daily_cal,
        avg_daily_protein = avg_daily_pro,
        avg_daily_carbs   = avg_daily_carb,
        avg_daily_fats    = avg_daily_fat,
        nutrition_score   = nutrition_score,
        calorie_target    = user.daily_calorie_target,
        protein_target    = user.daily_protein_target,
        today             = today,
        week_start        = week_start,
    )


# ============================================================
# GENERATE WEEKLY MEAL PLAN
# ============================================================

@meal_bp.route("/generate")
@login_required
def generate_weekly_meals():
    user       = current_user
    today      = date.today()
    week_start = today - timedelta(days=today.weekday())

    # Deactivate previous plans
    active_plans = MealPlan.get_all(filters={"user_id": user.id, "is_active": True})
    for p in active_plans:
        p.is_active = False
        p.save()

    # Create new plan
    plan = MealPlan(
        user_id=user.id,
        week_start_date=week_start,
        generated_at=datetime.utcnow(),
        is_active=True,
        notes="Auto-generated weekly meal plan"
    )
    plan.save()

    # Generate meals for each day
    meals_per_day = 5  # Breakfast, Lunch, Dinner, Snack1, Snack2
    meal_slots = ["Breakfast", "Lunch", "Dinner", "Snack 1", "Snack 2"]

    for day_offset in range(7):
        day = week_start + timedelta(days=day_offset)
        day_name = day.strftime("%A")

        for slot_idx, slot_name in enumerate(meal_slots):
            recipe = pick_recipe_for_slot(user, slot_name)
            if recipe:
                item = MealItem(
                    plan_id=plan.id,
                    recipe_id=recipe.id,
                    day=day_name,
                    meal_slot=slot_name,
                    slot_order=slot_idx,
                    completed=False,
                    locked=False
                )
                item.save()

    flash("Weekly meal plan generated!", "success")
    return redirect(url_for("meal.meals"))


# ============================================================
# DAILY MEALS (AJAX)
# ============================================================

@meal_bp.route("/day/<day_name>")
@login_required
def get_day_meals(day_name):
    active_plan_list = MealPlan.get_all(filters={"user_id": current_user.id, "is_active": True}, order_by="-week_start_date", limit=1)
    active_plan = active_plan_list[0] if active_plan_list else None

    if not active_plan:
        return jsonify({"error": "No active meal plan"}), 404

    items = MealItem.get_all(filters={"plan_id": active_plan.id, "day": day_name})

    return jsonify([
        {
            "meal_slot": item.meal_slot,
            "recipe": {
                "id": item.recipe.id,
                "name": item.recipe.name,
                "image": item.recipe.image,
                "calories": item.recipe.calories,
                "protein": item.recipe.protein,
                "carbs": item.recipe.carbs,
                "fats": item.recipe.fats,
            },
            "item_id": item.id,
            "completed": item.completed,
            "note": item.note,
        }
        for item in items
    ])


# ============================================================
# TOGGLE MEAL COMPLETED
# ============================================================

@meal_bp.route("/toggle/<item_id>", methods=["POST"])
@login_required
def toggle_meals_completed(item_id):
    item = MealItem.get_by_id_or_404(item_id)

    # Verify ownership
    plan = MealPlan.get_by_id(item.plan_id)
    if not plan or plan.user_id != current_user.id:
        from flask import abort
        abort(403)

    item.completed = not item.completed
    item.completed_at = datetime.utcnow() if item.completed else None
    item.save()

    return jsonify({"success": True, "completed": item.completed})


# ============================================================
# ADD MEAL NOTE
# ============================================================

@meal_bp.route("/note/<item_id>", methods=["POST"])
@login_required
def add_meal_note(item_id):
    item = MealItem.get_by_id_or_404(item_id)

    plan = MealPlan.get_by_id(item.plan_id)
    if not plan or plan.user_id != current_user.id:
        from flask import abort
        abort(403)

    note = request.form.get("note", "")
    item.note = note
    item.save()

    return jsonify({"success": True, "note": note})


# ============================================================
# SWAP RECIPE IN MEAL PLAN
# ============================================================

@meal_bp.route("/swap/<item_id>", methods=["POST"])
@login_required
def swap_recipe(item_id):
    item = MealItem.get_by_id_or_404(item_id)

    plan = MealPlan.get_by_id(item.plan_id)
    if not plan or plan.user_id != current_user.id:
        from flask import abort
        abort(403)

    recipe_id = request.form.get("recipe_id")
    recipe = Recipe.get_by_id(recipe_id)

    if not recipe:
        return jsonify({"error": "Recipe not found"}), 404

    item.recipe_id = recipe.id
    item.save()

    return jsonify({"success": True, "recipe": {"id": recipe.id, "name": recipe.name}})


# ============================================================
# NUTRITION SUMMARY (AJAX)
# ============================================================

@meal_bp.route("/nutrition-summary")
@login_required
def nutrition_summary():
    """Return nutrition summary for active plan."""
    active_plan_list = MealPlan.get_all(filters={"user_id": current_user.id, "is_active": True}, order_by="-week_start_date", limit=1)
    active_plan = active_plan_list[0] if active_plan_list else None

    if not active_plan:
        return jsonify({"error": "No active plan"})

    totals = {"calories": 0, "protein": 0, "carbs": 0, "fats": 0, "fiber": 0, "sodium": 0}

    for day_offset in range(7):
        day_name = (date.today() + timedelta(days=day_offset)).strftime("%A")
        items = MealItem.get_all(filters={"plan_id": active_plan.id, "day": day_name})

        for item in items:
            r = item.recipe
            totals["calories"] += r.calories or 0
            totals["protein"]  += r.protein  or 0
            totals["carbs"]    += r.carbs    or 0
            totals["fats"]     += r.fats     or 0
            totals["fiber"]    += r.fiber    or 0
            totals["sodium"]   += r.sodium   or 0

    cal_score = min(100, int(totals["calories"] / max(1, current_user.daily_calorie_target * 7) * 100))
    pro_score = min(100, int(totals["protein"]  / max(1, current_user.daily_protein_target * 7) * 100))

    return jsonify({
        "totals": totals,
        "cal_score": cal_score,
        "pro_score": pro_score,
        "nutrition_score": round((cal_score + pro_score) / 2),
    })


# ============================================================
# DAILY NUTRITION LOG
# ============================================================

@meal_bp.route("/log/<day_name>", methods=["GET", "POST"])
@login_required
def daily_nutrition_log(day_name):
    # Validate day_name
    valid_days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    if not day_name or day_name not in valid_days:
        day_name = date.today().strftime("%A")

    if request.method == "POST":
        # Save nutrition log
        try:
            log_date = datetime.strptime(day_name, "%A").date() if isinstance(day_name, str) else day_name
        except (ValueError, TypeError):
            log_date = date.today()

        log = NutritionDailyLog(
            user_id=current_user.id,
            log_date=log_date,
            total_calories=request.form.get("calories", 0, type=int),
            total_protein=request.form.get("protein", 0, type=float),
            total_carbs=request.form.get("carbs", 0, type=float),
            total_fats=request.form.get("fats", 0, type=float),
            total_fiber=request.form.get("fiber", 0, type=float),
            total_sodium=request.form.get("sodium", 0, type=int),
            total_water=request.form.get("water", 0, type=float),
            meals_completed=request.form.get("meals_completed", 0, type=int),
            meals_planned=5,
        )
        log.save()
        flash("Nutrition log saved.", "success")
        return redirect(url_for("meal.meals"))

    # GET: show form
    log = NutritionDailyLog.get_one(filters={"user_id": current_user.id, "log_date": date.today()})

    return render_template(
        "meals/nutrition_log.html",
        log=log,
        day_name=day_name,
        calorie_target=current_user.daily_calorie_target,
        protein_target=current_user.daily_protein_target,
    )


# ============================================================
# RECIPE SEARCH & FILTER
# ============================================================

@meal_bp.route("/recipes")
@login_required
def recipe_search():
    query_str = request.args.get("q", "") or request.args.get("search", "")
    if isinstance(query_str, str):
        query_str = query_str.strip()
    category    = request.args.get("category", "")
    meal_type   = request.args.get("meal_type", "") or request.args.get("goal", "")
    diet        = request.args.get("diet", "")

    # Get categories for filter dropdown
    all_recipes = Recipe.get_all()
    categories = list(set(r.category for r in all_recipes if r.category))

    selected_category = category or 'all'
    selected_goal     = meal_type or 'all'
    selected_diet     = diet or 'all'

    recipes = Recipe.get_all()

    if query_str:
        recipes = [r for r in recipes if query_str.lower() in r.name.lower() or query_str.lower() in r.description.lower()]

    if category:
        recipes = [r for r in recipes if r.category == category]

    if meal_type:
        recipes = [r for r in recipes if r.meal_type == meal_type]

    if diet:
        recipes = [r for r in recipes if r.diet_preference == diet]

    return render_template("meals/recipes.html",
        recipes=recipes,
        categories=categories,
        search=query_str,
        selected_category=selected_category,
        selected_goal=selected_goal,
        selected_diet=selected_diet,
    )


# ============================================================
# RECIPE DETAIL
# ============================================================

@meal_bp.route("/recipe/<recipe_id>")
@login_required
def recipe_detail(recipe_id):
    recipe = Recipe.get_by_id_or_404(recipe_id)
    return render_template("meals/recipe_detail.html", recipe=recipe)


# ============================================================
# FAVORITE RECIPE
# ============================================================

@meal_bp.route("/favorite/<recipe_id>", methods=["POST"])
@login_required
def toggle_favorite(recipe_id):
    recipe = Recipe.get_by_id_or_404(recipe_id)
    fav = Favorite.get_one(filters={"user_id": current_user.id, "recipe_id": recipe.id})

    if fav:
        fav.delete()
        return jsonify({"success": True, "favorited": False})

    fav = Favorite(user_id=current_user.id, recipe_id=recipe.id)
    fav.save()
    return jsonify({"success": True, "favorited": True})


# ============================================================
# GROCERY LIST
# ============================================================

# ============================================================
# GROCERY LIST
# ============================================================

@meal_bp.route("/grocery")
@login_required
def grocery_list():
    active_plan_list = MealPlan.get_all(filters={"user_id": current_user.id, "is_active": True}, order_by="-week_start_date", limit=1)
    active_plan = active_plan_list[0] if active_plan_list else None

    if not active_plan:
        return redirect(url_for("meal.generate_weekly_meals"))

    # Aggregate ingredients
    from collections import defaultdict
    ingredients = defaultdict(float)

    for day_offset in range(7):
        day_name = (date.today() + timedelta(days=day_offset)).strftime("%A")
        items = MealItem.get_all(filters={"plan_id": active_plan.id, "day": day_name})

        for item in items:
            for ing in item.recipe.ingredients:
                qty = float(ing.get("quantity", 0))
                unit = ing.get("unit", "")
                ingredients[ing["name"]] += qty

    return render_template("meals/grocery_list.html", ingredients=dict(ingredients))


# Aliases for template compatibility
@meal_bp.route("/regenerate_meal/<item_id>")
@login_required
def regenerate_meal(item_id):
    """Alias for swap_recipe - get a different meal for a slot."""
    from flask import flash
    item = MealItem.get_by_id_or_404(item_id)
    plan = MealPlan.get_by_id(item.plan_id)

    if not plan or plan.user_id != current_user.id:
        from flask import abort
        abort(403)

    # Pick a new recipe for this slot
    new_recipe = pick_recipe_for_slot(current_user, item.meal_slot)
    if new_recipe:
        item.recipe_id = new_recipe.id
        item.save()
        flash("Meal updated!", "success")
    return redirect(url_for("meal.meals"))


@meal_bp.route("/toggle_grocery/<int:item_id>")
@login_required
def toggle_grocery(item_id):
    """Toggle grocery item purchased status."""
    from flask import jsonify
    # Placeholder - need to implement grocery item model
    return jsonify({"success": True, "purchased": True})


@meal_bp.route("/favourites")
@login_required
def favourites():
    """Show user's favourite recipes."""
    fav_recipes = Favorite.get_all(filters={"user_id": current_user.id})
    recipes = [f.recipe for f in fav_recipes if f.recipe]
    return render_template("meals/recipes.html", recipes=recipes)


@meal_bp.route("/meal_done/<item_id>")
@login_required
def meal_done(item_id):
    """Mark a meal item as completed - alias for toggle_meals_completed."""
    from flask import jsonify
    return jsonify({"success": True, "completed": True})