# HealthTrack 2.0 — Deployment Guide

**Date:** 2025-11-25  
**Architecture:** Flask (HTML/Jinja2) + Flutter (Android) + Shared Flask Backend + Firebase

---

## Prerequisites

### System Requirements
- **Python:** 3.11+ (3.12 recommended for google-genai)
- **Flutter:** 3.16+ (for Android APK)
- **Node.js:** 18+ (only if React frontend ever re-added)
- **Database:** PostgreSQL 14+ (production) / SQLite (development)
- **Firebase Project:** Configured with Auth, Firestore, Storage, FCM

### Environment Variables (`.env`)
```bash
# Flask Core
SECRET_KEY=your-flask-secret-key
DATABASE_URL=postgresql://user:pass@host:5432/dbname
FLASK_ENV=production

# JWT Auth
JWT_SECRET_KEY=your-jwt-secret-key

# Email (for reports)
MAIL_SERVER=smtp.gmail.com
MAIL_PORT=587
MAIL_USE_TLS=True
MAIL_USERNAME=your-email@gmail.com
MAIL_PASSWORD=your-app-password
MAIL_DEFAULT_SENDER=your-email@gmail.com

# Google OAuth
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
GOOGLE_REDIRECT_URI=https://yourdomain.com/auth/google/callback

# Firebase (Server - Firebase Admin SDK)
FIREBASE_CREDENTIALS=firebase-credentials.json
FCM_SERVER_KEY=your-fcm-server-key

# Web Push (VAPID)
VAPID_PUBLIC_KEY=your-vapid-public-key
VAPID_PRIVATE_KEY=your-vapid-private-key
VAPID_EMAIL=your@email.com

# AI Services
GEMINI_API_KEY=your-gemini-api-key
# NVIDIA_API_KEY=your-nvidia-api-key (if needed)

# CORS
CORS_ORIGINS=https://yourdomain.com,https://www.yourdomain.com
```

---

## Local Development

### 1. Flask Backend
```bash
cd /c/health_app_main

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run database migrations
flask db upgrade

# Start development server
python app.py
```
- **Access:** http://localhost:5000
- **API Base:** http://localhost:5000/api/v1/
- **Health Check:** http://localhost:5000/api/v1/health

### 2. Flutter Android App
```bash
cd /c/health_app_main/healthtrack_clean

# Get dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Build release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### 3. Firebase Configuration
1. **Firebase Console:** Create project at https://console.firebase.google.com
2. **Enable Services:** Authentication, Firestore, Storage, Cloud Messaging
3. **Android App:** Add package name `com.healthtrack.app`, download `google-services.json` → `healthtrack_clean/android/app/`
4. **iOS (optional):** Add bundle ID, download `GoogleService-Info.plist` → `healthtrack_clean/ios/Runner/`
5. **Web (if needed):** Add web app, copy config to `.env` as `VITE_FIREBASE_*`
6. **Service Account:** Generate private key → save as `firebase-credentials.json` (server only!)

---

## Production Deployment

### Option A: Traditional VPS (Recommended for Flask + Flutter)

#### Server Requirements
- Ubuntu 22.04+ LTS
- 2+ GB RAM, 2+ vCPU
- PostgreSQL 14+
- Nginx + Gunicorn
- SSL certificate (Let's Encrypt)

#### Deployment Steps

1. **Provision Server**
```bash
sudo apt update && sudo apt install -y python3.11 python3.11-venv nginx postgresql postgresql-contrib certbot python3-certbot-nginx
```

2. **Database Setup**
```bash
sudo -u postgres psql -c "CREATE DATABASE healthtrack;"
sudo -u postgres psql -c "CREATE USER healthtrack WITH PASSWORD 'secure_password';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE healthtrack TO healthtrack;"
```

3. **Deploy Flask App**
```bash
# Clone/copy to /var/www/healthtrack
cd /var/www/healthtrack
python3.11 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pip install gunicorn

# Set environment variables
cp .env.example .env
# Edit .env with production values

# Run migrations
flask db upgrade

# Create systemd service
sudo tee /etc/systemd/system/healthtrack.service << EOF
[Unit]
Description=HealthTrack Flask App
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/healthtrack
Environment="PATH=/var/www/healthtrack/venv/bin"
ExecStart=/var/www/healthtrack/venv/bin/gunicorn --workers 4 --bind 127.0.0.1:5000 wsgi:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable healthtrack
sudo systemctl start healthtrack
```

4. **Configure Nginx**
```nginx
sudo tee /etc/nginx/sites-available/healthtrack << EOF
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Static files
    location /static/ {
        alias /var/www/healthtrack/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/healthtrack /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

5. **SSL Certificate**
```bash
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

#### Android APK Distribution
- **Google Play Store:** Upload `app-release.apk` to Play Console
- **Direct Download:** Host APK on your server/CDN
- **Internal Testing:** Use Firebase App Distribution or Play Internal Testing

---

## Firebase Production Configuration

### Firestore Security Rules
Deploy from `/c/health_app_main/firebase/`:
```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only storage
```

### Firebase Auth Providers
- Enable: Email/Password, Google Sign-In
- Authorized Domains: Add your production domain
- OAuth Consent: Configure in Google Cloud Console

### Cloud Messaging (FCM)
- **Android:** Automatic with `google-services.json`
- **Web:** Generate VAPID keys in Firebase Console → Project Settings → Cloud Messaging
- **Server:** Use `firebase_admin.messaging` in Flask (`utils/firebase_push.py`)

### Firestore Rules Summary
- User data scoped to `/users/{userId}/**`
- Family members can read permitted subcollections
- Admin access via `isAdmin()` custom claim
- Public read for emergency cards and app assets

---

## Environment-Specific Configurations

### Development
```bash
FLASK_ENV=development
DATABASE_URL=sqlite:///health_tracker.db
CORS_ORIGINS=http://localhost:3000,http://localhost:5000
```

### Staging
```bash
FLASK_ENV=staging
DATABASE_URL=postgresql://user:pass@staging-db:5432/healthtrack_staging
CORS_ORIGINS=https://staging.yourdomain.com
```

### Production
```bash
FLASK_ENV=production
DATABASE_URL=postgresql://user:pass@prod-db:5432/healthtrack
CORS_ORIGINS=https://yourdomain.com,https://www.yourdomain.com
SESSION_COOKIE_SECURE=True
WTF_CSRF_SSL_STRICT=True
```

---

## Monitoring & Maintenance

### Health Checks
- **Endpoint:** `GET /api/v1/health`
- **Expected:** `{"status": "ok", "app": "HealthTrack", "version": "2.0.0"}`

### Logs
- **Flask:** `journalctl -u healthtrack -f`
- **Nginx:** `/var/log/nginx/access.log`, `/var/log/nginx/error.log`
- **Flutter:** Device logs via `adb logcat` or Firebase Crashlytics

### Database Maintenance
```bash
# Backup
pg_dump -U healthtrack healthtrack > backup_$(date +%Y%m%d).sql

# Restore
psql -U healthtrack -d healthtrack < backup_20251125.sql
```

### APK Versioning
```yaml
# pubspec.yaml
version: 2.0.0+1  # version+build_number
```
Increment `version` for releases, `build_number` for each build.

---

## Rollback Procedures

### Flask App
```bash
# Quick rollback (if using git)
cd /var/www/healthtrack
git checkout previous-stable-tag
flask db downgrade  # if migration applied
sudo systemctl restart healthtrack
```

### Flutter APK
- Keep previous APK versions in Play Console
- Use Play Console "Rollback" feature or re-upload previous APK

### Database
```bash
# Restore from backup
psql -U healthtrack -d healthtrack < backup_20251125.sql
```

---

## Security Checklist

- [ ] All secrets in `.env` (never committed)
- [ ] `FIREBASE_CREDENTIALS` file permissions: `600`
- [ ] HTTPS enforced (HSTS, secure cookies)
- [ ] Rate limiting on auth/AI endpoints
- [ ] Input validation on all API endpoints
- [ ] Firestore rules deployed and tested
- [ ] Firebase App Check enabled (production)
- [ ] Regular dependency updates (`pip list --outdated`, `flutter pub outdated`)
- [ ] Backup schedule configured and tested
- [ ] Error tracking (Sentry) configured

---

## Support & Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Flask won't start | Check `.env` exists, DB connection, port 5000 free |
| Flutter build fails | `flutter clean && flutter pub get`, check Kotlin plugin warnings |
| Firebase Auth fails | Check `google-services.json` package name matches |
| FCM not working | Verify `google-services.json`, FCM token registration |
| DB connection fails | Check `DATABASE_URL`, PostgreSQL running, firewall |
| APK won't install | Enable "Unknown Sources", check minSdkVersion |

### Log Locations
- **Flask:** `journalctl -u healthtrack -f`
- **Nginx:** `/var/log/nginx/access.log`, `/var/log/nginx/error.log`
- **Flutter (device):** `adb logcat | grep healthtrack`
- **Flutter (Crashlytics):** Firebase Console → Crashlytics

---

## Contacts & Resources

- **Firebase Console:** https://console.firebase.google.com
- **Google Cloud Console:** https://console.cloud.google.com
- **Flutter Docs:** https://docs.flutter.dev
- **Flask Docs:** https://flask.palletsprojects.com
- **PostgreSQL Docs:** https://www.postgresql.org/docs/

---

*Deployment Guide v1.0 — Generated 2025-11-25*
EOF