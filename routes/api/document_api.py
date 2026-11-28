# routes/api/document_api.py — Document Vault API (Free/Premium/Family)

import os
import base64
from datetime import datetime, date
from flask import Blueprint, request, jsonify, send_file, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity

from models import Document, User, now_ist, today_ist, UserSubscription

document_api_bp = Blueprint("document_api", __name__)

MAX_FILE_BYTES = 10 * 1024 * 1024  # 10 MB hard limit

MIME_ALLOWED = {
    "pdf": "application/pdf",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
}


# ── Plan helpers ───────────────────────────────────────────────────
def _plan(user_id):
    sub = (UserSubscription.get_all(filters={"user_id": user_id}, limit=1) or [None])[0]
    if not sub:
        return "free"
    return sub.plan if sub.is_active else "free"


def _doc_limit(user_id):
    return Document.PLAN_LIMITS.get(_plan(user_id), 3)


def _is_premium(user_id):
    return _plan(user_id) in ("premium", "family")


def _plan_info(user_id):
    plan = _plan(user_id)
    limit = Document.PLAN_LIMITS.get(plan, 3)
    return {
        "plan": plan,
        "limit": limit,
        "is_premium": _is_premium(user_id),
        "can_search": _is_premium(user_id),
        "can_filter": _is_premium(user_id),
        "can_sort": _is_premium(user_id),
        "can_rename": _is_premium(user_id),
        "can_favourite": _is_premium(user_id),
        "can_preview": _is_premium(user_id),
        "categories": list(Document.CATEGORIES.keys()),
    }


def _safe_filename(name):
    name = (name or "document.pdf").strip()
    name = os.path.basename(name)
    if not name:
        name = "document.pdf"
    return name.replace("/", "_").replace("\\", "_")


def _decode_base64_file(file_b64):
    if not file_b64:
        raise ValueError("File data is required")

    if "," in file_b64 and file_b64.startswith("data:"):
        file_b64 = file_b64.split(",", 1)[1]

    try:
        return base64.b64decode(file_b64)
    except Exception:
        raise ValueError("Invalid file data (base64 decode failed)")


def _validate_extension(file_name):
    ext = file_name.rsplit(".", 1)[-1].lower() if "." in file_name else ""
    if ext not in MIME_ALLOWED:
        raise ValueError("Unsupported file type. Allowed: PDF, JPG, JPEG, PNG")
    return ext


def _save_file_for_user(uid, file_name, file_bytes):
    folder = os.path.join(current_app.config.get("DOCS_FOLDER", "static/documents"), str(uid))
    os.makedirs(folder, exist_ok=True)

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_name = f"{ts}_{file_name}"
    filepath = os.path.join(folder, safe_name)

    with open(filepath, "wb") as f:
        f.write(file_bytes)

    return filepath


# ════════════════════════════════════════════════════════════════
# LIST documents
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/list", methods=["GET"])
@jwt_required()
def list_documents():
    uid = get_jwt_identity()
    limit = _doc_limit(uid)

    docs = Document.get_all(filters={"user_id": uid}, order_by="-created_at")
    count = Document.count(filters={"user_id": uid})

    return jsonify({
        "success": True,
        "data": {
            "documents": [d.to_dict() for d in docs],
            "total": count,
            "limit": limit,
            "used": count,
            "remaining": max(0, limit - count),
            "can_upload": count < limit,
            "plan_info": _plan_info(uid),
            "categories": Document.CATEGORIES,
        }
    })


# ════════════════════════════════════════════════════════════════
# UPLOAD — camera / gallery / file picker
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/upload", methods=["POST"])
@jwt_required()
def upload_document():
    uid = get_jwt_identity()
    count = Document.count(filters={"user_id": uid})
    limit = _doc_limit(uid)

    if count >= limit:
        plan = _plan(uid)
        upgrade_to = "Premium" if plan in ("free", "normal") else "Family"
        return jsonify({
            "success": False,
            "message": f"🔒 {plan.title()} plan: {limit} document limit reached. Upgrade to {upgrade_to} for more.",
            "upgrade_required": True,
            "used": count,
            "limit": limit,
        }), 403

    d = request.get_json() or {}
    title = (d.get("title") or "").strip() or "Untitled Document"
    doc_type = (d.get("doc_type") or "other").strip()
    file_b64 = d.get("file_data", "")
    file_name = _safe_filename(d.get("file_name", "document.pdf"))
    doctor = (d.get("doctor_name") or "").strip() or None
    hospital = (d.get("hospital_name") or "").strip() or None
    notes = (d.get("notes") or "").strip() or None

    report_dt = None
    if d.get("report_date"):
        try:
            report_dt = date.fromisoformat(str(d["report_date"])[:10])
        except Exception:
            report_dt = None

    try:
        ext = _validate_extension(file_name)
        file_bytes = _decode_base64_file(file_b64)
    except ValueError as e:
        return jsonify({"success": False, "message": str(e)}), 400

    if len(file_bytes) > MAX_FILE_BYTES:
        return jsonify({
            "success": False,
            "message": "File too large. Maximum size is 10 MB."
        }), 400

    filepath = _save_file_for_user(uid, file_name, file_bytes)

    doc = Document(
        user_id=uid,
        title=title,
        doc_type=doc_type,
        file_name=file_name,
        file_path=filepath,
        file_size_kb=max(1, len(file_bytes) // 1024),
        mime_type=MIME_ALLOWED[ext],
        doctor_name=doctor,
        hospital_name=hospital,
        report_date=report_dt,
        notes=notes,
        uploaded_at=now_ist(),
    )

    doc.save()
    # # db.session.commit()  # Firestore auto-commits  # Firestore auto-commits

    return jsonify({
        "success": True,
        "message": f"✅ {title} uploaded",
        "data": doc.to_dict()
    }), 201


# ════════════════════════════════════════════════════════════════
# RENAME — Premium only
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>/rename", methods=["PUT"])
@jwt_required()
def rename_document(did):
    uid = get_jwt_identity()
    if not _is_premium(uid):
        return jsonify({
            "success": False,
            "message": "🔒 Renaming requires Premium plan",
            "upgrade_required": True
        }), 403

    doc = Document.get_by_id_or_404(id=did, user_id=uid)
    d = request.get_json() or {}
    new_title = (d.get("title") or "").strip()

    if not new_title:
        return jsonify({"success": False, "message": "Title cannot be empty"}), 400

    doc.title = new_title
    # # db.session.commit()  # Firestore auto-commits  # Firestore auto-commits
    return jsonify({"success": True, "message": "✅ Renamed", "data": doc.to_dict()})


# ════════════════════════════════════════════════════════════════
# TOGGLE FAVOURITE — Premium only
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>/favourite", methods=["POST"])
@jwt_required()
def toggle_favourite(did):
    uid = get_jwt_identity()
    if not _is_premium(uid):
        return jsonify({
            "success": False,
            "message": "🔒 Favourites require Premium plan",
            "upgrade_required": True
        }), 403

    doc = Document.get_by_id_or_404(id=did, user_id=uid)
    doc.is_important = not bool(doc.is_important)
    # # db.session.commit()  # Firestore auto-commits  # Firestore auto-commits

    action = "⭐ Starred" if doc.is_important else "Unstarred"
    return jsonify({
        "success": True,
        "message": f"{action}: {doc.title}",
        "data": doc.to_dict()
    })


# ════════════════════════════════════════════════════════════════
# UPDATE metadata
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>", methods=["PUT"])
@jwt_required()
def update_document(did):
    uid = get_jwt_identity()
    doc = Document.get_by_id_or_404(id=did, user_id=uid)
    d = request.get_json() or {}

    if "title" in d and d["title"]:
        doc.title = str(d["title"]).strip()
    if "doc_type" in d and d["doc_type"] is not None:
        doc.doc_type = d["doc_type"]
    if "doctor_name" in d:
        doc.doctor_name = d["doctor_name"] or None
    if "hospital_name" in d:
        doc.hospital_name = d["hospital_name"] or None
    if "notes" in d:
        doc.notes = d["notes"] or None
    if "report_date" in d and d["report_date"]:
        try:
            doc.report_date = date.fromisoformat(str(d["report_date"])[:10])
        except Exception:
            pass

    # # db.session.commit()  # Firestore auto-commits  # Firestore auto-commits
    return jsonify({"success": True, "message": "Updated", "data": doc.to_dict()})


# ════════════════════════════════════════════════════════════════
# REPLACE file — Premium only
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>/replace", methods=["POST"])
@jwt_required()
def replace_document(did):
    uid = get_jwt_identity()
    if not _is_premium(uid):
        return jsonify({
            "success": False,
            "message": "🔒 Replace requires Premium plan",
            "upgrade_required": True
        }), 403

    doc = Document.get_by_id_or_404(id=did, user_id=uid)
    d = request.get_json() or {}

    file_b64 = d.get("file_data", "")
    file_name = _safe_filename(d.get("file_name", doc.file_name or "document.pdf"))

    try:
        ext = _validate_extension(file_name)
        file_bytes = _decode_base64_file(file_b64)
    except ValueError as e:
        return jsonify({"success": False, "message": str(e)}), 400

    if len(file_bytes) > MAX_FILE_BYTES:
        return jsonify({"success": False, "message": "File too large (max 10 MB)"}), 400

    if doc.file_path and os.path.exists(doc.file_path):
        try:
            os.remove(doc.file_path)
        except Exception:
            pass

    filepath = _save_file_for_user(uid, file_name, file_bytes)

    doc.file_path = filepath
    doc.file_name = file_name
    doc.file_size_kb = max(1, len(file_bytes) // 1024)
    doc.mime_type = MIME_ALLOWED[ext]
    doc.uploaded_at = now_ist()

    # # db.session.commit()  # Firestore auto-commits  # Firestore auto-commits
    return jsonify({
        "success": True,
        "message": "✅ File replaced",
        "data": doc.to_dict()
    })


# ════════════════════════════════════════════════════════════════
# DOWNLOAD / VIEW
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>/download", methods=["GET"])
@jwt_required()
def download_document(did):
    uid = get_jwt_identity()
    doc = Document.get_by_id_or_404(id=did, user_id=uid)

    if not doc.file_path or not os.path.exists(doc.file_path):
        return jsonify({"success": False, "message": "File not found on server"}), 404

    return send_file(
        doc.file_path,
        as_attachment=True,
        download_name=doc.file_name,
        mimetype=doc.mime_type or "application/octet-stream"
    )


@document_api_bp.route("/<int:did>/preview", methods=["GET"])
@jwt_required()
def preview_document(did):
    uid = get_jwt_identity()
    if not _is_premium(uid):
        return jsonify({
            "success": False,
            "message": "🔒 Preview requires Premium plan"
        }), 403

    doc = Document.get_by_id_or_404(id=did, user_id=uid)

    if not doc.file_path or not os.path.exists(doc.file_path):
        return jsonify({"success": False, "message": "File not found"}), 404

    return send_file(
        doc.file_path,
        as_attachment=False,
        download_name=doc.file_name,
        mimetype=doc.mime_type or "application/octet-stream"
    )


# ════════════════════════════════════════════════════════════════
# DELETE
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>", methods=["DELETE"])
@jwt_required()
def delete_document(did):
    uid = get_jwt_identity()
    doc = Document.get_by_id_or_404(id=did, user_id=uid)
    title = doc.title

    if doc.file_path and os.path.exists(doc.file_path):
        try:
            os.remove(doc.file_path)
        except Exception:
            pass

    doc.delete()
    # # db.session.commit()  # Firestore auto-commits  # Firestore auto-commits

    return jsonify({"success": True, "message": f"🗑️ {title} deleted"})