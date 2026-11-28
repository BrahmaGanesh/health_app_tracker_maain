# routes/family_routes.py — Family Profiles Website
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from datetime import datetime, date
import json
from models import FamilyMember, FamilyHealthMetric, FamilyMedicine, FamilyDocument

family_bp = Blueprint("family", __name__)


@family_bp.route("/")
@login_required
def dashboard():
    members = FamilyMember.get_all(filters={"owner_id": current_user.id, "is_active": True})
    family_data = []
    for m in members:
        # Get latest BP for this member
        latest_bp_list = FamilyHealthMetric.get_all(
            filters={"member_id": m.id, "metric_type": "bp"},
            order_by="-recorded_at",
            limit=1
        )
        latest_bp = latest_bp_list[0] if latest_bp_list else None

        # Get medicines
        medicines = FamilyMedicine.get_all(filters={"member_id": m.id})

        # Get documents
        documents = FamilyDocument.get_all(filters={"member_id": m.id})

        # Get BP chart
        bp_metrics = FamilyHealthMetric.get_all(
            filters={"member_id": m.id, "metric_type": "bp"},
            order_by="recorded_at"
        )
        bp_chart = [{"day": m.recorded_at.strftime("%d %b"), "sys": m.value1, "dia": m.value2} for m in bp_metrics]

        family_data.append({
            "member": m,
            "latest_bp": latest_bp,
            "medicines": medicines,
            "documents": documents,
            "bp_chart": bp_chart,
        })

    return render_template("family/dashboard.html", family_data=family_data)


@family_bp.route("/add", methods=["GET", "POST"])
@login_required
def add_member():
    if request.method == "POST":
        name = request.form.get("name", "").strip()
        relationship = request.form.get("relationship", "")
        dob_str = request.form.get("date_of_birth", "")
        gender = request.form.get("gender", "")
        blood_group = request.form.get("blood_group", "")
        phone = request.form.get("phone", "")
        email = request.form.get("email", "")

        if not name or not relationship or not dob_str:
            flash("Name, relationship, and date of birth are required.", "danger")
            return render_template("family/add_member.html")

        try:
            dob = datetime.strptime(dob_str, "%Y-%m-%d").date()
        except ValueError:
            flash("Invalid date format.", "danger")
            return render_template("family/add_member.html")

        member = FamilyMember(
            owner_id=current_user.id,
            name=name,
            relationship=relationship,
            date_of_birth=dob,
            gender=gender,
            blood_group=blood_group,
            phone=phone,
            email=email,
        )
        member.save()
        flash(f"{name} added to your family.", "success")
        return redirect(url_for("family.dashboard"))

    return render_template("family/add_member.html")


@family_bp.route("/<int:member_id>")
@login_required
def member_profile(member_id):
    member = FamilyMember.get_by_id_or_404(member_id)
    if member.owner_id != current_user.id:
        from flask import abort
        abort(403)

    # Get all metrics for this member
    metrics = FamilyHealthMetric.get_all(
        filters={"member_id": member.id},
        order_by="-recorded_at"
    )

    # Latest BP
    latest_bp_list = FamilyHealthMetric.get_all(
        filters={"member_id": member.id, "metric_type": "bp"},
        order_by="-recorded_at",
        limit=1
    )
    latest_bp = latest_bp_list[0] if latest_bp_list else None

    # Medicines
    medicines = FamilyMedicine.get_all(filters={"member_id": member.id})

    # Documents
    documents = FamilyDocument.get_all(filters={"member_id": member.id})

    # BP chart
    bp_metrics = FamilyHealthMetric.get_all(
        filters={"member_id": member.id, "metric_type": "bp"},
        order_by="recorded_at"
    )
    bp_chart = [{"day": m.recorded_at.strftime("%d %b"), "sys": m.value1, "dia": m.value2} for m in bp_metrics]

    return render_template("family/member_profile.html", member=member, metrics=metrics, medicines=medicines, documents=documents, bp_chart=bp_chart)


@family_bp.route("/<int:member_id>/log", methods=["POST"])
@login_required
def log_metric(member_id):
    member = FamilyMember.get_by_id_or_404(member_id, owner_id=current_user.id)
    metric_type = request.form.get("metric_type","")
    value_1 = request.form.get("value_1") or None
    value_2 = request.form.get("value_2") or None
    notes = request.form.get("notes","")

    if not metric_type:
        flash("Metric type is required.", "danger")
        return redirect(url_for("family.member_profile", member_id=member_id))

    try:
        if value_1 is not None:
            value_1 = float(value_1)
    except (TypeError, ValueError):
        flash("Invalid value.", "danger")
        return redirect(url_for("family.member_profile", member_id=member_id))

    metric = FamilyHealthMetric(
        member_id=member.id, metric_type=metric_type,
        value_1=value_1,
        value_2=request.form.get("value_2") or None,
        notes=notes,
        recorded_at=datetime.utcnow(),
    )
    metric.save()
    flash("Reading saved.", "success")
    return redirect(url_for("family.member_profile", member_id=member_id))


@family_bp.route("/<int:member_id>/delete")
@login_required
def delete_member(member_id):
    member = FamilyMember.get_by_id_or_404(member_id, owner_id=current_user.id)
    member.is_active = False
    member.save()
    flash(f"{member.name} removed.", "info")
    return redirect(url_for("family.dashboard"))


@family_bp.route("/<int:member_id>/medicine/add", methods=["POST"])
@login_required
def add_medicine(member_id):
    member = FamilyMember.get_by_id_or_404(member_id, owner_id=current_user.id)
    name = request.form.get("name", "").strip()
    dosage = request.form.get("dosage", "").strip()
    timing = request.form.get("timing", "08:00")
    frequency = request.form.get("frequency", "daily")
    condition = request.form.get("condition", "")

    if not name:
        flash("Medicine name is required.", "danger")
        return redirect(url_for("family.member_profile", member_id=member_id))

    med = FamilyMedicine(
        member_id=member.id,
        name=name,
        dosage=dosage,
        timing=timing,
        frequency=frequency,
        condition=condition,
    )
    med.save()
    flash(f"Medicine '{name}' added for {member.name}.", "success")
    return redirect(url_for("family.member_profile", member_id=member_id))


@family_bp.route("/<int:member_id>/medicine/<med_id>/delete")
@login_required
def delete_medicine(member_id, med_id):
    med = FamilyMedicine.get_by_id_or_404(med_id)
    if med.member_id != member_id:
        from flask import abort
        abort(403)
    med.delete()
    flash("Medicine removed.", "info")
    return redirect(url_for("family.member_profile", member_id=member_id))


@family_bp.route("/<int:member_id>/document/add", methods=["POST"])
@login_required
def add_document(member_id):
    member = FamilyMember.get_by_id_or_404(member_id, owner_id=current_user.id)
    title = request.form.get("title", "").strip()
    doc_type = request.form.get("document_type", "other")
    file = request.files.get("file")

    if not title or not file:
        flash("Title and file are required.", "danger")
        return redirect(url_for("family.member_profile", member_id=member_id))

    # In a real app, you'd upload to Cloud Storage here
    # For now, just save the metadata
    doc = FamilyDocument(
        member_id=member.id,
        title=title,
        document_type=doc_type,
        file_name=file.filename,
        file_url="",  # Would be Cloud Storage URL
        notes=request.form.get("notes", ""),
    )
    doc.save()
    flash("Document added.", "success")
    return redirect(url_for("family.member_profile", member_id=member_id))


@family_bp.route("/<int:member_id>/document/<doc_id>/delete")
@login_required
def delete_document(member_id, doc_id):
    doc = FamilyDocument.get_by_id_or_404(doc_id)
    if doc.member_id != member_id:
        from flask import abort
        abort(403)
    doc.delete()
    flash("Document removed.", "info")
    return redirect(url_for("family.member_profile", member_id=member_id))