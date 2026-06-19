# ============================================================
# routes/api/meal_api.py — Meals & Recipes API (APK)
# ============================================================

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_current_user
from datetime import date, timedelta
import random

from extensions import db
from models import Recipe, MealPlan, MealItem, Favorite, GroceryItem

meal_api_bp = Blueprint("meal_api", __name__)


def ok(data=None, msg="Success", code=200):
    r = {"success": True, "message": msg}
    if data is not None: r["data"] = data
    return jsonify(r), code


def err(msg="Error", code=400):
    return jsonify({"success": False, "message": msg}), code


# ── RECIPES LIST ──────────────────────────────────────────────
@meal_api_bp.route("/recipes", methods=["GET"])
@jwt_required()
def get_recipes():
    user     = get_current_user()
    search   = request.args.get("search", "").strip()
    category = request.args.get("category", "all")
    goal     = request.args.get("goal", "all")
    diet     = request.args.get("diet", "all")
    page     = int(request.args.get("page", 1))
    per_page = int(request.args.get("per_page", 20))

    q = Recipe.query
    if search:
        q = q.filter(Recipe.name.ilike(f"%{search}%"))
    if category and category != "all":
        q = q.filter(Recipe.category == category)
    if goal == "bp":
        q = q.filter(Recipe.bp_friendly == True)
    elif goal == "weight":
        q = q.filter(Recipe.weight_loss_friendly == True)
    if diet == "veg":
        q = q.filter(Recipe.is_veg == True)
    elif diet == "nonveg":
        q = q.filter(Recipe.is_veg == False)

    paginated = q.order_by(Recipe.name).paginate(page=page, per_page=per_page, error_out=False)
    fav_ids   = {f.recipe_id for f in Favorite.query.filter_by(user_id=user.id).all()}

    recipes_data = []
    for r in paginated.items:
        d = r.to_dict()
        d["is_favourite"] = r.id in fav_ids
        d["score"]        = r.composite_score(user.condition_names)
        recipes_data.append(d)

    categories = sorted(set(
        r.category for r in Recipe.query.with_entities(Recipe.category).distinct().all()
        if r.category
    ))

    return ok({
        "recipes":    recipes_data,
        "total":      paginated.total,
        "page":       page,
        "has_more":   paginated.has_next,
        "categories": categories,
    })


# ── RECIPE DETAIL ─────────────────────────────────────────────
@meal_api_bp.route("/recipes/<int:recipe_id>", methods=["GET"])
@jwt_required()
def get_recipe(recipe_id):
    user   = get_current_user()
    recipe = Recipe.query.get_or_404(recipe_id)
    is_fav = Favorite.query.filter_by(user_id=user.id, recipe_id=recipe_id).first() is not None

    related = Recipe.query.filter(
        Recipe.category == recipe.category, Recipe.id != recipe_id
    ).limit(4).all()

    d = recipe.to_dict()
    d["is_favourite"]  = is_fav
    d["score"]         = recipe.composite_score(user.condition_names)
    d["related"]       = [r.to_dict() for r in related]
    d["ingredients_list"] = [i.strip() for i in (recipe.ingredients or "").split(",") if i.strip()]

    return ok(d)


# ── TOGGLE FAVOURITE ──────────────────────────────────────────
@meal_api_bp.route("/recipes/<int:recipe_id>/favourite", methods=["POST"])
@jwt_required()
def toggle_favourite(recipe_id):
    user   = get_current_user()
    Recipe.query.get_or_404(recipe_id)

    existing = Favorite.query.filter_by(user_id=user.id, recipe_id=recipe_id).first()
    if existing:
        db.session.delete(existing)
        db.session.commit()
        return ok({"is_favourite": False}, "Removed from favourites")
    else:
        fav = Favorite(user_id=user.id, recipe_id=recipe_id)
        db.session.add(fav)
        db.session.commit()
        return ok({"is_favourite": True}, "Added to favourites ❤️")


# ── GET FAVOURITES ────────────────────────────────────────────
@meal_api_bp.route("/favourites", methods=["GET"])
@jwt_required()
def get_favourites():
    user  = get_current_user()
    favs  = Favorite.query.filter_by(user_id=user.id).order_by(Favorite.saved_at.desc()).all()
    return ok({"recipes": [f.recipe.to_dict() for f in favs]})


# ── GET WEEKLY MEAL PLAN ──────────────────────────────────────
@meal_api_bp.route("/plan", methods=["GET"])
@jwt_required()
def get_meal_plan():
    user       = get_current_user()
    today      = date.today()
    week_start = today - timedelta(days=today.weekday())

    active_plan = MealPlan.query.filter_by(
        user_id=user.id, is_active=True
    ).order_by(MealPlan.generated_at.desc()).first()

    if not active_plan:
        return ok({"has_plan": False, "plan": None, "week_start": str(week_start)})

    days_data = {}
    for day in ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]:
        items = MealItem.query.filter_by(
            plan_id=active_plan.id, day=day
        ).order_by(MealItem.slot_order.asc()).all()
        days_data[day] = [
            {
                "id":        item.id,
                "meal_slot": item.meal_slot,
                "slot_order": item.slot_order,
                "completed": item.completed,
                "completed_at": item.completed_at.isoformat() if item.completed_at else None,
                "recipe":    item.recipe.to_dict(),
            }
            for item in items
        ]

    # Today's stats
    today_name = today.strftime("%A")
    today_items= days_data.get(today_name, [])
    meals_done = sum(1 for m in today_items if m["completed"])
    meals_total= len(today_items)
    today_calories = sum(m["recipe"]["calories"] for m in today_items if m["completed"])

    return ok({
        "has_plan":    True,
        "plan_id":     active_plan.id,
        "week_start":  str(active_plan.week_start_date),
        "generated_at": active_plan.generated_at.isoformat(),
        "days":        days_data,
        "today": {
            "day_name":    today_name,
            "meals_done":  meals_done,
            "meals_total": meals_total,
            "meals_pct":   int(meals_done / meals_total * 100) if meals_total else 0,
            "today_calories_consumed": today_calories,
        }
    })


# ── GENERATE MEAL PLAN ────────────────────────────────────────
@meal_api_bp.route("/plan/generate", methods=["POST"])
@jwt_required()
def generate_plan():
    user       = get_current_user()
    today      = date.today()
    week_start = today - timedelta(days=today.weekday())

    # Deactivate old
    MealPlan.query.filter_by(user_id=user.id, is_active=True).update({"is_active": False})

    plan = MealPlan(user_id=user.id, week_start_date=week_start, is_active=True)
    db.session.add(plan)
    db.session.flush()

    SLOTS = [
        ("Morning Drink", 1, 100),
        ("Breakfast",     2, 320),
        ("Lunch",         3, 500),
        ("Snacks",        4, 180),
        ("Dinner",        5, 400),
    ]

    SLOT_CATS = {
        "Morning Drink": ["Morning", "BP Special"],
        "Breakfast":     ["Breakfast"],
        "Lunch":         ["Lunch"],
        "Snacks":        ["Snack"],
        "Dinner":        ["Dinner", "Soup"],
    }

    conditions = user.condition_names
    diet_pref  = user.health_profile.diet_preference if user.health_profile else "vegetarian"

    used_ids = []
    for day in ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]:
        day_used = []
        for slot_name, slot_order, cal_budget in SLOTS:
            cats   = SLOT_CATS.get(slot_name, ["General"])
            q      = Recipe.query.filter(Recipe.category.in_(cats))

            if diet_pref in ("vegetarian", "vegan"):
                q = q.filter(Recipe.is_veg == True)
            if user.has_bp:
                q = q.filter(Recipe.bp_friendly == True)
            elif user.has_diabetes:
                q = q.filter(Recipe.diabetes_friendly == True)

            q = q.filter(Recipe.calories <= cal_budget * 1.5)
            if day_used + used_ids[-15:]:
                q = q.filter(~Recipe.id.in_(day_used + used_ids[-15:]))

            recipes = q.all()
            if not recipes:
                recipes = Recipe.query.filter(Recipe.category.in_(cats)).all()

            if recipes:
                scored  = sorted(recipes, key=lambda r: r.composite_score(conditions), reverse=True)
                recipe  = random.choice(scored[:5])
                item    = MealItem(
                    plan_id=plan.id, recipe_id=recipe.id,
                    day=day, meal_slot=slot_name, slot_order=slot_order
                )
                db.session.add(item)
                day_used.append(recipe.id)
                used_ids.append(recipe.id)

    db.session.commit()

    # Generate grocery list
    _generate_grocery(user.id, plan.id, week_start)

    return ok({"plan_id": plan.id, "week_start": str(week_start)}, "Meal plan generated!", 201)


def _generate_grocery(user_id, plan_id, week_start):
    GroceryItem.query.filter_by(user_id=user_id, week_start=week_start).delete()
    items = MealItem.query.filter_by(plan_id=plan_id).all()
    seen  = set()
    for item in items:
        r = item.recipe
        if not r.ingredients: continue
        for ing in r.ingredients.split(","):
            ing = ing.strip()
            if not ing or ing.lower() in seen: continue
            seen.add(ing.lower())
            db.session.add(GroceryItem(
                user_id=user_id, week_start=week_start,
                ingredient_name=ing, category=_categorize(ing)
            ))
    db.session.commit()


def _categorize(name):
    n = name.lower()
    if any(x in n for x in ["spinach","palak","methi","bathua","amaranth"]): return "Leafy Greens"
    if any(x in n for x in ["banana","apple","orange","pomegranate","guava","papaya","amla"]): return "Fruits"
    if any(x in n for x in ["tomato","onion","carrot","cucumber","capsicum","cauliflower","peas","beans","lauki","karela","gourd","potato","beetroot","mushroom"]): return "Vegetables"
    if any(x in n for x in ["moong","masoor","toor","chana","rajma","lobia","urad","dal","lentil","chickpea","sprout","soya"]): return "Lentils & Legumes"
    if any(x in n for x in ["rice","wheat","atta","oats","ragi","bajra","jowar","quinoa","millet","barley","rava","poha","bread"]): return "Grains & Cereals"
    if any(x in n for x in ["milk","curd","yogurt","buttermilk","paneer","ghee","butter","dairy"]): return "Dairy"
    if any(x in n for x in ["egg"]): return "Eggs"
    if any(x in n for x in ["chicken","fish","salmon","sardine","mackerel","tuna","prawn"]): return "Protein / Non-Veg"
    if any(x in n for x in ["almond","walnut","cashew","peanut","pumpkin seed","sunflower","flaxseed","chia","sesame"]): return "Nuts & Seeds"
    if any(x in n for x in ["garlic","ginger","turmeric","cumin","coriander","pepper","cardamom","cinnamon","mustard","fenugreek","tulsi","mint","lemon","spice","masala","herb"]): return "Herbs & Spices"
    return "Other"


# ── MARK MEAL DONE ────────────────────────────────────────────
@meal_api_bp.route("/plan/items/<int:item_id>/done", methods=["POST"])
@jwt_required()
def mark_meal_done(item_id):
    from datetime import datetime
    user = get_current_user()
    item = MealItem.query.get_or_404(item_id)
    if item.meal_plan.user_id != user.id: return err("Unauthorised", 403)

    item.completed    = not item.completed
    item.completed_at = datetime.utcnow() if item.completed else None
    db.session.commit()

    return ok({"completed": item.completed, "item_id": item.id})


# ── GROCERY LIST ──────────────────────────────────────────────
@meal_api_bp.route("/grocery", methods=["GET"])
@jwt_required()
def get_grocery():
    user       = get_current_user()
    today      = date.today()
    week_start = today - timedelta(days=today.weekday())

    items = GroceryItem.query.filter_by(
        user_id=user.id, week_start=week_start
    ).order_by(GroceryItem.category, GroceryItem.ingredient_name).all()

    from collections import defaultdict
    grouped = defaultdict(list)
    for item in items:
        grouped[item.category].append({
            "id":         item.id,
            "name":       item.ingredient_name,
            "purchased":  item.purchased,
            "category":   item.category,
        })

    total     = len(items)
    purchased = sum(1 for i in items if i.purchased)

    return ok({
        "grouped":   dict(grouped),
        "items":     [{"id": i.id, "name": i.ingredient_name, "purchased": i.purchased, "category": i.category} for i in items],
        "total":     total,
        "purchased": purchased,
        "pct":       int(purchased / total * 100) if total else 0,
        "week_start": str(week_start),
    })


# ── TOGGLE GROCERY ITEM ───────────────────────────────────────
@meal_api_bp.route("/grocery/<int:item_id>/toggle", methods=["POST"])
@jwt_required()
def toggle_grocery(item_id):
    from datetime import datetime
    user = get_current_user()
    item = GroceryItem.query.filter_by(id=item_id, user_id=user.id).first_or_404()
    item.purchased    = not item.purchased
    item.purchased_at = datetime.utcnow() if item.purchased else None
    db.session.commit()
    return ok({"purchased": item.purchased, "item_id": item.id})