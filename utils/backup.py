# ============================================================
# utils/backup.py — Data Backup & Restore
# ============================================================

import json, os, zipfile, io
from datetime import datetime, date


def create_backup(user, backup_type="manual", fmt="json"):
    from app import db
    from models import (
        Backup, HealthMetric, SleepLog, StepLog, ExerciseLog,
        MedicineLog, Medicine, NutritionDailyLog, DailyHealthScore,
        FamilyMember, FamilyHealthMetric
    )

    data = {
        "exported_at": datetime.utcnow().isoformat(),
        "user": user.to_dict(),
        "profile": user.health_profile.to_dict() if user.health_profile else None,
        "goals": user.goals.to_dict() if user.goals else None,
        "conditions": user.condition_names,
        "health_metrics": [m.to_dict() for m in user.health_metrics.order_by(HealthMetric.recorded_at.desc()).limit(1000).all()],
        "sleep_logs": [s.to_dict() for s in user.sleep_logs.order_by(SleepLog.log_date.desc()).limit(365).all()],
        "step_logs":  [s.to_dict() for s in user.step_logs.order_by(StepLog.log_date.desc()).limit(365).all()],
        "exercise_logs": [e.to_dict() for e in user.exercise_logs.order_by(ExerciseLog.log_date.desc()).limit(365).all()],
        "medicines": [m.to_dict() for m in user.medicines],
        "nutrition_logs": [n.to_dict() for n in user.nutrition_logs.order_by(NutritionDailyLog.log_date.desc()).limit(365).all()],
        "health_scores": [h.to_dict() for h in user.health_scores.order_by(DailyHealthScore.score_date.desc()).limit(365).all()],
        "family_members": [m.to_dict() for m in user.family_members],
    }

    json_bytes = json.dumps(data, indent=2, default=str).encode("utf-8")
    filename   = f"healthtrack_backup_{user.id}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"

    os.makedirs("static/backups", exist_ok=True)
    filepath = f"static/backups/{filename}"
    with open(filepath, "wb") as f:
        f.write(json_bytes)

    size_kb = len(json_bytes) // 1024

    backup = Backup(
        user_id     = user.id,
        backup_type = backup_type,
        file_name   = filename,
        file_path   = filepath,
        file_size_kb= size_kb,
        format      = fmt,
        status      = "completed",
    )
    db.session.add(backup)
    db.session.commit()

    return {"success": True, "filename": filename, "size_kb": size_kb, "path": filepath, "data": data}


def get_backup_bytes(user, fmt="json"):
    result = create_backup(user, backup_type="export", fmt=fmt)
    if not result["success"]:
        return None, None

    if fmt == "zip":
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.write(result["path"], result["filename"])
        buf.seek(0)
        return buf, result["filename"].replace(".json", ".zip")

    with open(result["path"], "rb") as f:
        buf = io.BytesIO(f.read())
    buf.seek(0)
    return buf, result["filename"]