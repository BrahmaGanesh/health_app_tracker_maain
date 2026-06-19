# ============================================================
# seed_exercises.py — Exercise Library Seed Data
# Run with: python seed_exercises.py
# Populates ExerciseLibrary with BP-safe exercises across categories
# ============================================================

from app import create_app, db
from models import ExerciseLibrary

EXERCISES = [
    # ── CARDIO ────────────────────────────────────────────────
    {
        "name": "Brisk Walking", "category": "cardio", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "A low-impact cardio exercise that's one of the most effective ways to lower blood pressure naturally.",
        "instructions": "Walk at a pace where you can talk but not sing. Maintain for 20-30 minutes. Keep arms swinging naturally and posture upright.",
        "benefits": "Lowers systolic BP by 4-9 mmHg, improves circulation, aids weight management, boosts mood.",
        "duration_mins": 30, "calories_per_min": 4.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "none", "is_featured": True,
    },
    {
        "name": "Stationary Cycling", "category": "cardio", "muscle_group": "lower",
        "difficulty": "beginner",
        "description": "Low-impact cycling that builds cardiovascular endurance without joint strain.",
        "instructions": "Set moderate resistance. Pedal at a steady cadence for 15-20 minutes. Keep back straight and core engaged.",
        "benefits": "Improves heart health, strengthens legs, low joint impact, great for all fitness levels.",
        "duration_mins": 20, "calories_per_min": 6.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "stationary bike", "is_featured": True,
    },
    {
        "name": "Swimming", "category": "cardio", "muscle_group": "full_body",
        "difficulty": "intermediate",
        "description": "Full-body, joint-friendly cardio workout in water — excellent for BP and joint health.",
        "instructions": "Swim at a comfortable pace for 20-30 minutes, alternating strokes. Rest between laps as needed.",
        "benefits": "Reduces BP, builds endurance, low-impact on joints, full-body toning.",
        "duration_mins": 30, "calories_per_min": 7.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": False,
        "equipment": "pool", "is_featured": False,
    },
    {
        "name": "Light Jogging", "category": "cardio", "muscle_group": "lower",
        "difficulty": "intermediate",
        "description": "A step up from walking — light jogging for those with moderate fitness levels.",
        "instructions": "Jog at a conversational pace for 15-20 minutes. Warm up with 5 min walking first.",
        "benefits": "Improves cardiovascular fitness, burns calories, strengthens legs.",
        "duration_mins": 20, "calories_per_min": 8.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": False, "beginner_safe": False,
        "equipment": "none", "is_featured": False,
    },
    {
        "name": "Dancing", "category": "cardio", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "Fun, rhythmic movement that gets your heart pumping while improving coordination.",
        "instructions": "Dance to your favorite music for 20-30 minutes. Any style works — focus on continuous movement.",
        "benefits": "Improves cardiovascular health, mood booster, social activity, burns calories.",
        "duration_mins": 25, "calories_per_min": 5.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "none", "is_featured": True,
    },

    # ── STRENGTH ──────────────────────────────────────────────
    {
        "name": "Bodyweight Squats", "category": "strength", "muscle_group": "lower",
        "difficulty": "beginner",
        "description": "A foundational lower-body exercise using just your body weight.",
        "instructions": "Stand with feet shoulder-width apart. Lower hips back and down as if sitting in a chair. Keep knees behind toes. Rise back up. 2-3 sets of 10-15 reps.",
        "benefits": "Strengthens legs and glutes, improves balance, supports metabolism.",
        "duration_mins": 10, "calories_per_min": 5.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "none", "is_featured": True,
    },
    {
        "name": "Wall Push-Ups", "category": "strength", "muscle_group": "upper",
        "difficulty": "beginner",
        "description": "A gentler variation of push-ups, ideal for building upper body strength safely.",
        "instructions": "Stand arm's length from a wall. Place palms on wall at shoulder height. Bend elbows to bring chest toward wall, then push back. 2-3 sets of 10-12 reps.",
        "benefits": "Builds chest, shoulder, and arm strength without joint strain.",
        "duration_mins": 8, "calories_per_min": 3.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "wall", "is_featured": False,
    },
    {
        "name": "Resistance Band Rows", "category": "strength", "muscle_group": "upper",
        "difficulty": "beginner",
        "description": "Builds back and arm strength using light resistance bands.",
        "instructions": "Anchor band at chest height. Pull handles toward your ribs, squeezing shoulder blades together. 2-3 sets of 12-15 reps.",
        "benefits": "Strengthens back muscles, improves posture, low joint impact.",
        "duration_mins": 10, "calories_per_min": 4.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "resistance band", "is_featured": False,
    },
    {
        "name": "Bodyweight Lunges", "category": "strength", "muscle_group": "lower",
        "difficulty": "intermediate",
        "description": "Builds leg strength and balance through controlled stepping movements.",
        "instructions": "Step forward with one leg, lowering hips until both knees are bent at 90°. Push back to start. Alternate legs. 2 sets of 8-10 reps per leg.",
        "benefits": "Strengthens legs and glutes, improves balance and coordination.",
        "duration_mins": 10, "calories_per_min": 5.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": False,
        "equipment": "none", "is_featured": False,
    },
    {
        "name": "Plank Hold", "category": "strength", "muscle_group": "core",
        "difficulty": "intermediate",
        "description": "An isometric core exercise that builds total-body stability.",
        "instructions": "Hold a forearm plank position with body in a straight line. Engage core. Hold for 20-30 seconds, repeat 3 times.",
        "benefits": "Strengthens core, improves posture, builds endurance.",
        "duration_mins": 5, "calories_per_min": 4.0,
        "bp_safe": False, "diabetes_safe": True, "heart_safe": False, "beginner_safe": False,
        "equipment": "mat", "is_featured": False,
    },

    # ── YOGA ──────────────────────────────────────────────────
    {
        "name": "Gentle Morning Yoga Flow", "category": "yoga", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "A slow, gentle sequence to wake up the body and calm the mind — great for BP management.",
        "instructions": "Move through cat-cow, child's pose, gentle forward fold, and seated twists. Hold each pose for 5 breaths. 15 minutes total.",
        "benefits": "Reduces stress hormones, improves flexibility, lowers BP, calms nervous system.",
        "duration_mins": 15, "calories_per_min": 2.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "mat", "is_featured": True,
    },
    {
        "name": "Legs-Up-The-Wall Pose", "category": "yoga", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "A restorative yoga pose known to help lower blood pressure and reduce swelling.",
        "instructions": "Lie on your back with legs resting up against a wall, forming an L-shape. Relax arms by your sides. Hold for 5-10 minutes with slow breathing.",
        "benefits": "Promotes relaxation, improves circulation, reduces BP, relieves tired legs.",
        "duration_mins": 10, "calories_per_min": 1.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "wall, mat", "is_featured": True,
    },
    {
        "name": "Seated Forward Fold", "category": "yoga", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "A calming forward bend that stretches the spine and hamstrings while relaxing the mind.",
        "instructions": "Sit with legs extended. Hinge at hips and fold forward, reaching toward feet. Hold for 30-60 seconds, breathing deeply.",
        "benefits": "Relieves tension, calms nervous system, stretches hamstrings and back.",
        "duration_mins": 5, "calories_per_min": 2.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "mat", "is_featured": False,
    },
    {
        "name": "Sun Salutation (Slow)", "category": "yoga", "muscle_group": "full_body",
        "difficulty": "intermediate",
        "description": "A flowing sequence of poses that gently warms up the entire body.",
        "instructions": "Move slowly through mountain pose, forward fold, plank, cobra, and back to standing. Repeat 3-5 rounds at a gentle pace.",
        "benefits": "Improves flexibility, circulation, and gentle cardiovascular activation.",
        "duration_mins": 12, "calories_per_min": 3.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": False,
        "equipment": "mat", "is_featured": False,
    },

    # ── FLEXIBILITY / STRETCHING ─────────────────────────────
    {
        "name": "Neck & Shoulder Stretches", "category": "flexibility", "muscle_group": "upper",
        "difficulty": "beginner",
        "description": "Simple stretches to relieve tension in the neck and shoulders from daily stress.",
        "instructions": "Gently tilt head side to side, holding 15 seconds each side. Roll shoulders backward 10 times. Repeat twice.",
        "benefits": "Relieves tension, reduces stress, improves mobility.",
        "duration_mins": 5, "calories_per_min": 1.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "none", "is_featured": False,
    },
    {
        "name": "Full-Body Stretch Routine", "category": "flexibility", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "A complete stretching sequence to improve flexibility and reduce stiffness.",
        "instructions": "Stretch calves, hamstrings, quads, back, and arms — holding each stretch for 20-30 seconds without bouncing.",
        "benefits": "Improves flexibility, reduces injury risk, promotes relaxation.",
        "duration_mins": 12, "calories_per_min": 2.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "mat", "is_featured": False,
    },
    {
        "name": "Ankle & Wrist Mobility", "category": "flexibility", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "Quick mobility drills for joints often neglected in daily movement.",
        "instructions": "Rotate ankles and wrists in circles, 10 times each direction. Flex and point feet 10 times.",
        "benefits": "Improves joint mobility, prevents stiffness, great warm-up.",
        "duration_mins": 5, "calories_per_min": 1.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "none", "is_featured": False,
    },

    # ── BREATHING ─────────────────────────────────────────────
    {
        "name": "4-7-8 Breathing", "category": "breathing", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "A calming breath technique that activates the body's relaxation response.",
        "instructions": "Inhale through nose for 4 seconds, hold for 7 seconds, exhale through mouth for 8 seconds. Repeat 4 rounds.",
        "benefits": "Can lower systolic BP by 5-10 mmHg, reduces anxiety, improves sleep.",
        "duration_mins": 2, "calories_per_min": 1.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "none", "is_featured": True,
    },
    {
        "name": "Box Breathing", "category": "breathing", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "Equal-count breathing pattern used to reduce stress and improve focus.",
        "instructions": "Inhale 4 seconds, hold 4 seconds, exhale 4 seconds, hold 4 seconds. Repeat 5 rounds.",
        "benefits": "Reduces cortisol, improves focus, regulates nervous system.",
        "duration_mins": 2, "calories_per_min": 1.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "none", "is_featured": False,
    },
    {
        "name": "Deep Belly Breathing", "category": "breathing", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "Diaphragmatic breathing that improves oxygen flow and calms the body.",
        "instructions": "Place hand on belly. Inhale for 5 seconds feeling belly rise, exhale for 5 seconds feeling belly fall. Repeat 10 rounds.",
        "benefits": "Improves oxygen levels, lowers resting heart rate, reduces BP.",
        "duration_mins": 2, "calories_per_min": 1.0,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "none", "is_featured": False,
    },

    # ── SPORTS ────────────────────────────────────────────────
    {
        "name": "Badminton (Casual)", "category": "sports", "muscle_group": "full_body",
        "difficulty": "intermediate",
        "description": "A fun, social racquet sport that provides moderate cardiovascular exercise.",
        "instructions": "Play casually for 20-30 minutes, focusing on rallying rather than competitive smashes.",
        "benefits": "Improves cardiovascular fitness, coordination, social engagement.",
        "duration_mins": 25, "calories_per_min": 6.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": False, "beginner_safe": False,
        "equipment": "racquet", "is_featured": False,
    },
    {
        "name": "Table Tennis", "category": "sports", "muscle_group": "full_body",
        "difficulty": "beginner",
        "description": "A light, engaging sport that improves reflexes and provides gentle cardio.",
        "instructions": "Play for 15-20 minutes, focusing on rallies and movement.",
        "benefits": "Improves hand-eye coordination, light cardio, mentally engaging.",
        "duration_mins": 20, "calories_per_min": 4.5,
        "bp_safe": True, "diabetes_safe": True, "heart_safe": True, "beginner_safe": True,
        "equipment": "paddle", "is_featured": False,
    },
]


def seed_exercise_library():
    app = create_app()
    with app.app_context():
        added = 0
        for ex in EXERCISES:
            existing = ExerciseLibrary.query.filter_by(name=ex["name"]).first()
            if existing:
                continue
            db.session.add(ExerciseLibrary(**ex))
            added += 1
        db.session.commit()
        print(f"✅ Seeded {added} new exercises (skipped {len(EXERCISES)-added} existing).")
        print(f"📚 Total exercises in library: {ExerciseLibrary.query.count()}")


if __name__ == "__main__":
    seed_exercise_library()