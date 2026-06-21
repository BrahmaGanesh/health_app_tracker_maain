from app import app
from extensions import db
from models import seed_health_conditions

with app.app_context():
    db.drop_all()
    db.create_all()
    seed_health_conditions()
    db.session.commit()

print("Database reset successfully.")