"""
WSGI entry point for HealthTrack Flask application.

This WSGI file is used by Gunicorn and other WSGI servers to serve the Flask application.
It imports the application object from the app module.
"""
from app import create_app

application = create_app()