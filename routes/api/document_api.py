# routes/api/document_api.py — Document Vault API (Free/Premium/Family)
import os, base64
from datetime import datetime, date
from flask import Blueprint, request, jsonify, send_file, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from extensions import db
from models import Document, User, now_ist, today_ist ,UserSubscription
# from models_new_modules import

document_api_bp = Blueprint("document_api", __name__)

MAX_FILE_BYTES = 10 * 1024 * 1024   # 10 MB hard limit

MIME_ALLOWED = {
    "pdf": "application/pdf",
    "jpg": "image/jpeg", "jpeg": "image/jpeg",
    "png": "image/png",
}

# ── Plan helpers ───────────────────────────────────────────────────
def _plan(user_id):
    sub = UserSubscription.query.filter_by(user_id=user_id).first()
    if not sub: return "free"
    return sub.plan if sub.is_active else "free"

def _doc_limit(user_id):
    return Document.PLAN_LIMITS.get(_plan(user_id), 3)

def _is_premium(user_id):
    return _plan(user_id) in ("premium", "family")

def _plan_info(user_id):
    plan  = _plan(user_id)
    limit = Document.PLAN_LIMITS.get(plan, 3)
    return {
        "plan":          plan,
        "limit":         limit,
        "is_premium":    _is_premium(user_id),
        "can_search":    _is_premium(user_id),
        "can_filter":    _is_premium(user_id),
        "can_sort":      _is_premium(user_id),
        "can_rename":    _is_premium(user_id),
        "can_favourite": _is_premium(user_id),
        "can_preview":   _is_premium(user_id),
        "categories":    list(Document.CATEGORIES.keys()),
    }


# ════════════════════════════════════════════════════════════════
# LIST documents
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/list", methods=["GET"])
@jwt_required()
def list_documents():
    uid  = get_jwt_identity()
    plan = _plan(uid)
    limit= _doc_limit(uid)

    # Base query
    q = Document.query.filter_by(user_id=uid)

    # Premium: filter + search + sort
    if _is_premium(uid):
        doc_type = request.args.get("type")
        search   = request.args.get("search", "").strip()
        fav_only = request.args.get("favourites") == "true"
        sort_by  = request.args.get("sort", "date")   # date | name | size | type

        if doc_type: q = q.filter(Document.doc_type == doc_type)
        if search:   q = q.filter(Document.title.ilike(f"%{search}%"))
        if fav_only: q = q.filter(Document.is_important == True)

        sort_map = {
            "date":  Document.uploaded_at.desc(),
            "name":  Document.title.asc(),
            "size":  Document.file_size_kb.desc(),
            "type":  Document.doc_type.asc(),
        }
        q = q.order_by(sort_map.get(sort_by, Document.uploaded_at.desc()))
    else:
        q = q.order_by(Document.uploaded_at.desc())

    docs  = q.limit(limit + 5).all()   # slight buffer for UI
    count = Document.query.filter_by(user_id=uid).count()

    return jsonify({"success": True, "data": {
        "documents":    [d.to_dict() for d in docs],
        "total":        count,
        "limit":        limit,
        "used":         count,
        "remaining":    max(0, limit - count),
        "can_upload":   count < limit,
        "plan_info":    _plan_info(uid),
        "categories":   Document.CATEGORIES,
    }})


# ════════════════════════════════════════════════════════════════
# UPLOAD — camera / gallery / file picker
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/upload", methods=["POST"])
@jwt_required()
def upload_document():
    uid   = get_jwt_identity()
    count = Document.query.filter_by(user_id=uid).count()
    limit = _doc_limit(uid)

    if count >= limit:
        plan = _plan(uid)
        upgrade_to = "Premium" if plan in ("free","normal") else "Family"
        return jsonify({
            "success": False,
            "message": f"🔒 {plan.title()} plan: {limit} document limit reached. Upgrade to {upgrade_to} for more.",
            "upgrade_required": True,
            "used": count, "limit": limit,
        }), 403

    d = request.get_json() or {}
    title      = (d.get("title") or "").strip() or "Untitled Document"
    doc_type   = d.get("doc_type", "other")
    file_b64   = d.get("file_data", "")
    file_name  = d.get("file_name", "document.pdf").strip()
    mime_type  = d.get("mime_type", "application/pdf")
    doctor     = (d.get("doctor_name") or "").strip() or None
    hospital   = (d.get("hospital_name") or "").strip() or None
    notes      = (d.get("notes") or "").strip() or None
    report_dt  = None
    if d.get("report_date"):
        try: report_dt = date.fromisoformat(d["report_date"][:10])
        except: pass

    # Validate
    if not file_b64:
        return jsonify({"success": False, "message": "File data is required"}), 400

    ext = file_name.rsplit(".", 1)[-1].lower() if "." in file_name else ""
    if ext not in MIME_ALLOWED:
        return jsonify({"success": False, "message": f"Unsupported file type. Allowed: PDF, JPG, JPEG, PNG"}), 400

    # Decode & size check
    try:
        file_bytes = base64.b64decode(file_b64)
    except Exception:
        return jsonify({"success": False, "message": "Invalid file data (base64 decode failed)"}), 400

    if len(file_bytes) > MAX_FILE_BYTES:
        return jsonify({"success": False, "message": "File too large. Maximum size is 10 MB."}), 400

    # Save to disk
    folder = os.path.join(current_app.config.get("DOCS_FOLDER", "static/documents"), str(uid))
    os.makedirs(folder, exist_ok=True)

    ts          = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_name   = f"{ts}_{file_name}"
    filepath    = os.path.join(folder, safe_name)
    with open(filepath, "wb") as f:
        f.write(file_bytes)

    doc = Document(
        user_id=uid, title=title, doc_type=doc_type,
        file_name=file_name, file_path=filepath,
        file_size_kb=len(file_bytes) // 1024,
        mime_type=MIME_ALLOWED.get(ext, mime_type),
        doctor_name=doctor, hospital_name=hospital,
        report_date=report_dt, notes=notes,
        uploaded_at=now_ist(),
    )
    db.session.add(doc)
    db.session.commit()

    return jsonify({"success": True, "message": f"✅ {title} uploaded", "data": doc.to_dict()}), 201


# ════════════════════════════════════════════════════════════════
# RENAME — Premium only
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>/rename", methods=["PUT"])
@jwt_required()
def rename_document(did):
    uid = get_jwt_identity()
    if not _is_premium(uid):
        return jsonify({"success": False, "message": "🔒 Renaming requires Premium plan", "upgrade_required": True}), 403

    doc = Document.query.filter_by(id=did, user_id=uid).first_or_404()
    d   = request.get_json() or {}
    new_title = (d.get("title") or "").strip()
    if not new_title:
        return jsonify({"success": False, "message": "Title cannot be empty"}), 400

    doc.title = new_title
    db.session.commit()
    return jsonify({"success": True, "message": "✅ Renamed", "data": doc.to_dict()})


# ════════════════════════════════════════════════════════════════
# TOGGLE FAVOURITE — Premium only
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>/favourite", methods=["POST"])
@jwt_required()
def toggle_favourite(did):
    uid = get_jwt_identity()
    if not _is_premium(uid):
        return jsonify({"success": False, "message": "🔒 Favourites require Premium plan", "upgrade_required": True}), 403

    doc = Document.query.filter_by(id=did, user_id=uid).first_or_404()
    doc.is_important = not doc.is_important
    db.session.commit()
    action = "⭐ Starred" if doc.is_important else "Unstarred"
    return jsonify({"success": True, "message": f"{action}: {doc.title}", "data": doc.to_dict()})


# ════════════════════════════════════════════════════════════════
# UPDATE metadata
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>", methods=["PUT"])
@jwt_required()
def update_document(did):
    uid = get_jwt_identity()
    doc = Document.query.filter_by(id=did, user_id=uid).first_or_404()
    d   = request.get_json() or {}

    if "title"         in d and d["title"]:         doc.title         = d["title"].strip()
    if "doc_type"      in d:                         doc.doc_type      = d["doc_type"]
    if "doctor_name"   in d:                         doc.doctor_name   = d["doctor_name"]
    if "hospital_name" in d:                         doc.hospital_name = d["hospital_name"]
    if "notes"         in d:                         doc.notes         = d["notes"]
    if "report_date"   in d and d["report_date"]:
        try: doc.report_date = date.fromisoformat(d["report_date"][:10])
        except: pass

    db.session.commit()
    return jsonify({"success": True, "message": "Updated", "data": doc.to_dict()})


# ════════════════════════════════════════════════════════════════
# REPLACE file — Premium only
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>/replace", methods=["POST"])
@jwt_required()
def replace_document(did):
    uid = get_jwt_identity()
    if not _is_premium(uid):
        return jsonify({"success": False, "message": "🔒 Replace requires Premium plan", "upgrade_required": True}), 403

    doc = Document.query.filter_by(id=did, user_id=uid).first_or_404()
    d   = request.get_json() or {}

    file_b64  = d.get("file_data", "")
    file_name = d.get("file_name", doc.file_name)
    if not file_b64:
        return jsonify({"success": False, "message": "file_data required"}), 400

    ext = file_name.rsplit(".", 1)[-1].lower()
    if ext not in MIME_ALLOWED:
        return jsonify({"success": False, "message": "Unsupported file type"}), 400

    try:
        file_bytes = base64.b64decode(file_b64)
    except Exception:
        return jsonify({"success": False, "message": "Invalid file data"}), 400

    if len(file_bytes) > MAX_FILE_BYTES:
        return jsonify({"success": False, "message": "File too large (max 10 MB)"}), 400

    # Remove old file
    if doc.file_path and os.path.exists(doc.file_path):
        try: os.remove(doc.file_path)
        except: pass

    # Save new file
    folder = os.path.dirname(doc.file_path) or os.path.join(current_app.config.get("DOCS_FOLDER", "static/documents"), str(uid))
    os.makedirs(folder, exist_ok=True)
    ts       = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = os.path.join(folder, f"{ts}_{file_name}")
    with open(filepath, "wb") as f:
        f.write(file_bytes)

    doc.file_path    = filepath
    doc.file_name    = file_name
    doc.file_size_kb = len(file_bytes) // 1024
    doc.mime_type    = MIME_ALLOWED.get(ext, "application/pdf")
    doc.uploaded_at  = now_ist()
    db.session.commit()
    return jsonify({"success": True, "message": "✅ File replaced", "data": doc.to_dict()})


# ════════════════════════════════════════════════════════════════
# DOWNLOAD / VIEW
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>/download", methods=["GET"])
@jwt_required()
def download_document(did):
    uid = get_jwt_identity()
    doc = Document.query.filter_by(id=did, user_id=uid).first_or_404()
    if not os.path.exists(doc.file_path):
        return jsonify({"success": False, "message": "File not found on server"}), 404
    return send_file(doc.file_path, as_attachment=True, download_name=doc.file_name, mimetype=doc.mime_type or "application/octet-stream")


@document_api_bp.route("/<int:did>/preview", methods=["GET"])
@jwt_required()
def preview_document(did):
    """Premium: preview in-browser (inline, not download)."""
    uid = get_jwt_identity()
    if not _is_premium(uid):
        return jsonify({"success": False, "message": "🔒 Preview requires Premium plan"}), 403

    doc = Document.query.filter_by(id=did, user_id=uid).first_or_404()
    if not os.path.exists(doc.file_path):
        return jsonify({"success": False, "message": "File not found"}), 404
    return send_file(doc.file_path, as_attachment=False, mimetype=doc.mime_type or "application/octet-stream")


# ════════════════════════════════════════════════════════════════
# DELETE
# ════════════════════════════════════════════════════════════════

@document_api_bp.route("/<int:did>", methods=["DELETE"])
@jwt_required()
def delete_document(did):
    uid = get_jwt_identity()
    doc = Document.query.filter_by(id=did, user_id=uid).first_or_404()
    title = doc.title

    # Remove file from disk
    if doc.file_path and os.path.exists(doc.file_path):
        try: os.remove(doc.file_path)
        except: pass

    db.session.delete(doc)
    db.session.commit()
    return jsonify({"success": True, "message": f"🗑️ {title} deleted"})