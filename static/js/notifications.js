/* ============================================================
   notifications.js — Web Push + In-App Sound Notifications
   ============================================================ */

'use strict';

const HealthNotifications = {
  swRegistration: null,
  permission:     'default',

  sounds: {
    health_alert: null,
    water_drop:   null,
    medicine:     null,
    gentle:       null,
    urgent:       null,
  },

  // ── Init ───────────────────────────────────────────────────
  async init() {
    await this._loadSounds();
    if ('serviceWorker' in navigator) {
      try {
        this.swRegistration = await navigator.serviceWorker.register('/static/js/sw.js');
        console.log('[Notifications] Service Worker registered');
      } catch(e) {
        console.warn('[Notifications] SW registration failed:', e);
      }
    }
    await this._checkPermission();
    this._startPolling();
  },

  // ── Load audio files ───────────────────────────────────────
  async _loadSounds() {
    const soundFiles = {
      health_alert: '/static/sounds/health_alert.mp3',
      water_drop:   '/static/sounds/water_drop.mp3',
      medicine:     '/static/sounds/medicine.mp3',
      gentle:       '/static/sounds/gentle.mp3',
      urgent:       '/static/sounds/urgent.mp3',
    };
    for (const [name, url] of Object.entries(soundFiles)) {
      try {
        const audio = new Audio(url);
        audio.preload = 'auto';
        audio.volume  = 0.7;
        this.sounds[name] = audio;
      } catch(e) {}
    }
  },

  // ── Play sound ─────────────────────────────────────────────
  playSound(soundName = 'health_alert') {
    const audio = this.sounds[soundName] || this.sounds.health_alert;
    if (!audio) return;
    try {
      audio.currentTime = 0;
      audio.play().catch(() => {});
    } catch(e) {}
  },

  // ── Request permission ─────────────────────────────────────
  async requestPermission() {
    if (!('Notification' in window)) return false;
    const result = await Notification.requestPermission();
    this.permission = result;
    return result === 'granted';
  },

  async _checkPermission() {
    if ('Notification' in window) {
      this.permission = Notification.permission;
    }
  },

  // ── Subscribe to Web Push ──────────────────────────────────
  async subscribePush(vapidPublicKey) {
    if (!this.swRegistration || this.permission !== 'granted') return false;
    try {
      const sub = await this.swRegistration.pushManager.subscribe({
        userVisibleOnly:      true,
        applicationServerKey: this._urlBase64ToUint8Array(vapidPublicKey),
      });

      // Save subscription to server
      await fetch('/api/v1/notifications/web-push/subscribe', {
        method:  'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Bearer ${this._getJWT()}`,
        },
        body: JSON.stringify({ subscription: sub.toJSON() }),
      });

      console.log('[Notifications] Web Push subscribed');
      return true;
    } catch(e) {
      console.warn('[Notifications] Push subscribe failed:', e);
      return false;
    }
  },

  // ── Show in-app toast notification with sound ──────────────
  showToast(title, message, type = 'info', sound = 'health_alert', duration = 6000) {
    // Play sound immediately
    if (sound && sound !== 'none') {
      this.playSound(sound);
    }

    // Create toast element
    const toast = document.createElement('div');
    toast.className = `notif-toast notif-${type}`;
    toast.style.cssText = `
      position: fixed; top: 80px; right: 16px; z-index: 99999;
      background: white; border-radius: 14px; padding: 14px 18px;
      min-width: 300px; max-width: 420px;
      box-shadow: 0 8px 32px rgba(20,45,76,0.18);
      display: flex; gap: 12px; align-items: flex-start;
      border-left: 4px solid ${this._typeColor(type)};
      animation: slideInRight 0.3s cubic-bezier(0.34,1.56,0.64,1);
      font-family: 'DM Sans', sans-serif;
    `;

    const icons = { emergency: '🚨', warning: '⚠️', info: 'ℹ️', success: '✅', reminder: '🔔', water: '💧', medicine: '💊', bp: '❤️' };
    const icon  = icons[type] || '🔔';

    toast.innerHTML = `
      <span style="font-size:20px;flex-shrink:0;">${icon}</span>
      <div style="flex:1;">
        <div style="font-size:14px;font-weight:700;color:#142d4c;margin-bottom:3px;">${title}</div>
        <div style="font-size:13px;color:#6b839e;line-height:1.5;">${message}</div>
      </div>
      <button onclick="this.parentElement.remove()" style="background:none;border:none;cursor:pointer;font-size:16px;color:#6b839e;flex-shrink:0;padding:0;">✕</button>
    `;

    // Add style for animation if not exists
    if (!document.getElementById('notif-style')) {
      const style = document.createElement('style');
      style.id = 'notif-style';
      style.textContent = `
        @keyframes slideInRight {
          from { opacity:0; transform:translateX(100%); }
          to   { opacity:1; transform:translateX(0); }
        }
      `;
      document.head.appendChild(style);
    }

    document.body.appendChild(toast);

    // Stack multiple toasts
    const existing = document.querySelectorAll('.notif-toast');
    existing.forEach((t, i) => {
      t.style.top = `${80 + i * 80}px`;
    });

    // Auto-remove
    setTimeout(() => {
      if (toast.parentElement) {
        toast.style.animation = 'none';
        toast.style.opacity   = '0';
        toast.style.transform = 'translateX(100%)';
        toast.style.transition = 'opacity 0.3s, transform 0.3s';
        setTimeout(() => toast.remove(), 300);
      }
    }, duration);

    return toast;
  },

  // ── Show browser notification (when tab not focused) ───────
  async showBrowserNotification(title, body, options = {}) {
    if (this.permission !== 'granted') return;
    const sound = options.sound || 'health_alert';
    this.playSound(sound);
    try {
      new Notification(title, {
        body,
        icon:  '/static/images/icon-192.png',
        badge: '/static/images/badge-72.png',
        tag:   options.tag || 'healthtrack',
        ...options,
      });
    } catch(e) {}
  },

  // ── Poll for new in-app notifications (every 30s) ──────────
  _startPolling() {
    let lastCheck = new Date().toISOString();
    setInterval(async () => {
      try {
        const jwt = this._getJWT();
        if (!jwt) return;

        const resp = await fetch(`/api/v1/notifications/?unread_only=true`, {
          headers: { 'Authorization': `Bearer ${jwt}` }
        });
        if (!resp.ok) return;

        const data = await resp.json();
        if (!data.success) return;

        const notifs = data.data.notifications || [];
        const newOnes = notifs.filter(n => n.created_at > lastCheck);

        if (newOnes.length > 0) {
          lastCheck = new Date().toISOString();
          for (const n of newOnes.slice(0, 3)) {
            // Show in-app toast
            this.showToast(n.title, n.message, n.notif_type, n.sound);
            // Update badge counter
            this._updateBadge(data.data.unread_count);
          }
        }
      } catch(e) {}
    }, 30000);
  },

  // ── Update notification badge in navbar ───────────────────
  _updateBadge(count) {
    const badges = document.querySelectorAll('.notif-badge, #notif-count');
    badges.forEach(b => {
      b.textContent = count > 0 ? count : '';
      b.style.display = count > 0 ? 'flex' : 'none';
    });
  },

  // ── Helpers ────────────────────────────────────────────────
  _typeColor(type) {
    const colors = {
      emergency: '#ef4444', warning: '#f59e0b',
      info: '#3b82f6', success: '#22c55e',
      reminder: '#9fd3c7', water: '#0ea5e9',
      medicine: '#8b5cf6', bp: '#ef4444',
    };
    return colors[type] || '#9fd3c7';
  },

  _getJWT() {
    return localStorage.getItem('ht_access_token') || '';
  },

  _urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64  = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw     = window.atob(base64);
    return new Uint8Array([...raw].map(char => char.charCodeAt(0)));
  },
};

// Auto-init when DOM ready
document.addEventListener('DOMContentLoaded', () => HealthNotifications.init());
window.HealthNotifications = HealthNotifications;