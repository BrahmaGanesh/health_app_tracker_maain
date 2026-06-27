# ============================================================
# utils/firebase_push.py — Firebase FCM + Web Push
# ============================================================

import json
import logging
from datetime import datetime

logger = logging.getLogger(__name__)


def _get_firebase_app():
    try:
        import firebase_admin
        from firebase_admin import credentials, messaging
        from flask import current_app
        if not firebase_admin._apps:
            cred_path = current_app.config.get("FIREBASE_CREDENTIALS", "firebase-credentials.json")
            try:
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
            except Exception as e:
                logger.warning(f"Firebase init failed: {e}")
                return None, None
        return firebase_admin, messaging
    except ImportError:
        logger.warning("firebase-admin not installed")
        return None, None


def send_fcm_notification(fcm_token, title, body, data=None, sound="default"):
    """Send push notification to Android APK via FCM."""
    if not fcm_token: return False
    firebase_admin, messaging = _get_firebase_app()
    if not messaging: return False

    try:
        android_sound = f"{sound}.mp3" if sound != "default" else "default"
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    title=title, body=body,
                    sound=android_sound,
                    channel_id="health_tracker_channel",
                    priority=messaging.AndroidNotificationPriority.HIGH,
                    default_sound=True, default_vibrate_timings=True,
                    visibility=messaging.AndroidNotificationVisibility.PUBLIC,
                ),
            ),
            data={k: str(v) for k, v in (data or {}).items()},
            token=fcm_token,
        )
        response = messaging.send(message)
        logger.info(f"FCM sent: {response}")
        return True
    except Exception as e:
        logger.error(f"FCM send failed: {e}")
        return False


def send_web_push_notification(subscription_json, title, body, data=None, sound="health_alert"):
    """Send push notification to browser via Web Push VAPID."""
    if not subscription_json: return False
    try:
        from pywebpush import webpush
        from flask import current_app
        vapid_private = current_app.config.get("VAPID_PRIVATE_KEY", "")
        vapid_email   = current_app.config.get("VAPID_EMAIL", "mailto:admin@healthtrack.app")
        if not vapid_private: return False
        subscription = json.loads(subscription_json) if isinstance(subscription_json, str) else subscription_json
        payload = json.dumps({
            "title": title, "body": body,
            "icon":  "/static/images/icon-192.png",
            "badge": "/static/images/badge-72.png",
            "sound": f"/static/sounds/{sound}.mp3",
            "data":  data or {},
        })
        webpush(
            subscription_info=subscription, data=payload,
            vapid_private_key=vapid_private,
            vapid_claims={"sub": vapid_email},
        )
        return True
    except Exception as e:
        logger.error(f"Web push failed: {e}")
        return False


def send_push_to_user(user, title, body, data=None, sound="health_alert"):
    """Send to both FCM (APK) and Web Push (Website)."""
    s1 = send_fcm_notification(user.fcm_token, title, body, data, sound) if user.fcm_token else False
    s2 = send_web_push_notification(user.web_push_sub, title, body, data, sound) if user.web_push_sub else False
    return s1 or s2