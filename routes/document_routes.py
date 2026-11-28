# routes/document_routes.py — Medical Document Vault
import os
from flask import Blueprint, render_template, redirect, url_for, flash, request, send_file, abort
from flask_login import login_required, current_user
from datetime import datetime, date
from werkzeug.utils import secure_filename
from models import Document, User, now_ist, today_ist, UserSubscription

document_bp = Blueprint("documents", __name__)

ALLOWED = {"pdf","png","jpg","jpeg","gif","webp","doc","docx"}

def allowed(filename):
    return "." in filename and filename.rsplit(".",1)[1].lower() in ALLOWED


def _plan(uid):
    from models import UserSubscription
    sub_list = UserSubscription.get_all(filters={"user_id": uid}, limit=1)
    sub = sub_list[0] if sub_list else None
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
    }


document_bp = Blueprint("documents", __name__)


# ════════════════════════════════════════════════════════════════
# LIST
# ════════════════════════════════════════════════════════════════

@document_bp.route("/")
@login_required
def vault():
    doc_type = request.args.get("type","all")

    # Build filters
    filters = {"user_id": current_user.id}
    if doc_type != "all":
        filters["doc_type"] = doc_type

    docs = Document.get_all(filters=filters, order_by="-created_at")

    important = Document.count(filters={"user_id": current_user.id, "is_important": True})
    counts = {}
    for d in ["lab_report","prescription","insurance","xray","ecg","mri","vaccination","other"]:
        counts[d] = Document.count(filters={"user_id": current_user.id, "doc_type": d})
    return render_template("documents/vault.html", docs=docs, counts=counts,
                           selected_type=doc_type, important_count=important)


@document_bp.route("/upload", methods=["POST"])
@login_required
def upload():
    file = request.files.get("file")
    if not file or not file.filename:
        flash("Please select a file.", "danger"); return redirect(url_for("documents.vault"))
    if not allowed(file.filename):
        flash("File type not allowed.", "danger"); return redirect(url_for("documents.vault"))

    title     = request.form.get("title","").strip() or file.filename
    doc_type  = request.form.get("doc_type","other")
    safe_name = secure_filename(file.filename)
    from flask import current_app
    folder    = current_app.config.get("DOCS_FOLDER","static/documents")
    user_dir  = os.path.join(folder, str(current_user.id))
    os.makedirs(user_dir, exist_ok=True)

    ts        = datetime.utcnow().strftime("%Y%m%d%H%M%S")
    filename  = f"{ts}_{safe_name}"
    filepath  = os.path.join(user_dir, filename)
    file.save(filepath)
    size_kb   = os.path.getsize(filepath) // 1024

    report_date = None
    rd_str = request.form.get("report_date","")
    if rd_str:
        try: report_date = datetime.strptime(rd_str, "%Y-%m-%d").date()
        except ValueError: pass

    doc = Document(
        user_id=current_user.id, title=title, doc_type=doc_type,
        file_name=filename, file_path=filepath, file_size_kb=size_kb,
        mime_type=file.mimetype, doctor_name=request.form.get("doctor_name",""),
        hospital_name=request.form.get("hospital_name",""),
        report_date=report_date, notes=request.form.get("notes",""),
        is_important=bool(request.form.get("is_important")),
    )
    doc.save()
    # db.session.commit()  # Firestore auto-commits
    flash(f"✅ '{title}' uploaded successfully!", "success")
    return redirect(url_for("documents.vault"))


@document_bp.route("/view/<int:doc_id>")
@login_required
def view_doc(doc_id):
    doc = Document.get_by_id_or_404(doc_id)
    if doc.user_id != current_user.id:
        from flask import abort
        abort(403)
    if not os.path.exists(doc.file_path): abort(404)
    return send_file(doc.file_path, mimetype=doc.mime_type or "application/octet-stream",
                     as_attachment=False, download_name=doc.file_name)


@document_bp.route("/download/<int:doc_id>")
@login_required
def download_doc(doc_id):
    doc = Document.get_by_id_or_404(doc_id)
    if doc.user_id != current_user.id:
        from flask import abort
        abort(403)
    if not os.path.exists(doc.file_path): abort(404)
    return send_file(doc.file_path, as_attachment=True, download_name=doc.file_name)


@document_bp.route("/delete/<int:doc_id>")
@login_required
def delete_doc(doc_id):
    doc = Document.get_by_id_or_404(doc_id)
    if doc.user_id != current_user.id:
        from flask import abort
        abort(403)
    try:
        if os.path.exists(doc.file_path): os.remove(doc.file_path)
    except Exception: pass
    doc.delete()
    # db.session.commit()  # Firestore auto-commits
    flash("Document deleted.", "info")
    return redirect(url_for("documents.vault"))


@document_bp.route("/toggle-important/<int:doc_id>", methods=["POST"])
@login_required
def toggle_important(doc_id):
    doc = Document.get_by_id_or_404(doc_id)
    if doc.user_id != current_user.id:
        from flask import abort
        abort(403)
    doc.is_important = not doc.is_important
    doc.save()
    # db.session.commit()  # Firestore auto-commits
    return redirect(url_for("documents.vault"))