# routes/family_routes.py — Family Profiles Website
from flask import Blueprint, render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from datetime import datetime, date
import json
from extensions import db
from models import FamilyMember, FamilyHealthMetric, FamilyMedicine, FamilyDocument

family_bp = Blueprint("family", __name__)

@family_bp.route("/")
@login_required
def dashboard():
    members = FamilyMember.query.filter_by(owner_id=current_user.id, is_active=True).all()
    family_data = []
    for m in members:
        latest_bp = FamilyHealthMetric.query.filter_by(member_id=m.id, metric_type="bp").order_by(FamilyHealthMetric.recorded_at.desc()).first()
        latest_wt = FamilyHealthMetric.query.filter_by(member_id=m.id, metric_type="weight").order_by(FamilyHealthMetric.recorded_at.desc()).first()
        family_data.append({"member": m, "latest_bp": latest_bp, "latest_weight": latest_wt})
    return render_template("family/dashboard.html", family_data=family_data)

@family_bp.route("/add", methods=["GET","POST"])
@login_required
def add_member():
    if request.method == "POST":
        name = request.form.get("name","").strip()
        if not name:
            flash("Name is required.", "danger")
            return redirect(url_for("family.add_member"))
        dob = None
        dob_str = request.form.get("date_of_birth","")
        if dob_str:
            try: dob = datetime.strptime(dob_str, "%Y-%m-%d").date()
            except ValueError: pass
        conditions = request.form.getlist("conditions")
        member = FamilyMember(
            owner_id=current_user.id, name=name,
            relation=request.form.get("relation",""),
            gender=request.form.get("gender",""),
            date_of_birth=dob,
            height_cm=request.form.get("height_cm") or None,
            current_weight_kg=request.form.get("weight_kg") or None,
            blood_group=request.form.get("blood_group",""),
            emergency_contact=request.form.get("emergency_contact",""),
            conditions_json=json.dumps(conditions),
            notes=request.form.get("notes",""),
        )
        db.session.add(member)
        db.session.commit()
        flash(f"{name} added to your family! 👨‍👩‍👧", "success")
        return redirect(url_for("family.dashboard"))
    return render_template("family/add_member.html")

@family_bp.route("/<int:member_id>")
@login_required
def member_profile(member_id):
    member = FamilyMember.query.filter_by(id=member_id, owner_id=current_user.id).first_or_404()
    metrics = FamilyHealthMetric.query.filter_by(member_id=member.id).order_by(FamilyHealthMetric.recorded_at.desc()).limit(30).all()
    medicines = FamilyMedicine.query.filter_by(member_id=member.id, active=True).all()
    documents = FamilyDocument.query.filter_by(member_id=member.id).order_by(FamilyDocument.uploaded_at.desc()).all()
    bp_chart = [{"day": m.recorded_at.strftime("%d %b"), "sys": m.value_1, "dia": m.value_2} for m in metrics if m.metric_type == "bp"]
    return render_template("family/member_profile.html", member=member, metrics=metrics, medicines=medicines, documents=documents, bp_chart=bp_chart)

@family_bp.route("/<int:member_id>/log", methods=["POST"])
@login_required
def log_metric(member_id):
    member = FamilyMember.query.filter_by(id=member_id, owner_id=current_user.id).first_or_404()
    metric_type = request.form.get("metric_type","")
    metric = FamilyHealthMetric(
        member_id=member.id, metric_type=metric_type,
        value_1=request.form.get("value_1") or None,
        value_2=request.form.get("value_2") or None,
        notes=request.form.get("notes",""),
        recorded_at=datetime.utcnow(),
    )
    db.session.add(metric)
    db.session.commit()
    flash("Reading saved.", "success")
    return redirect(url_for("family.member_profile", member_id=member_id))

@family_bp.route("/<int:member_id>/delete")
@login_required
def delete_member(member_id):
    member = FamilyMember.query.filter_by(id=member_id, owner_id=current_user.id).first_or_404()
    member.is_active = False
    db.session.commit()
    flash(f"{member.name} removed.", "info")
    return redirect(url_for("family.dashboard"))
