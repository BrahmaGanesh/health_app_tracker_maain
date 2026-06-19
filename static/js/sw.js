
/* ============================================================
   sw.js — Service Worker for Web Push Notifications
   Handles background notifications for the website
   ============================================================ */

const CACHE_NAME  = 'healthtrack-v2';
const SOUND_FILES = [
  '/static/sounds/health_alert.mp3',
  '/static/sounds/water_drop.mp3',
  '/static/sounds/medicine.mp3',
  '/static/sounds/gentle.mp3',
  '/static/sounds/urgent.mp3',
];

// ── Install ───────────────────────────────────────────────────
self.addEventListener('install', event => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache =>
      cache.addAll(SOUND_FILES).catch(() => {})
    )
  );
});

// ── Activate ──────────────────────────────────────────────────
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// ── Push Event ────────────────────────────────────────────────
self.addEventListener('push', event => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch(e) {
    payload = { title: 'HealthTrack', body: event.data ? event.data.text() : 'New notification' };
  }

  const title   = payload.title   || 'HealthTrack';
  const body    = payload.body    || '';
  const icon    = payload.icon    || '/static/images/icon-192.png';
  const badge   = payload.badge   || '/static/images/badge-72.png';
  const sound   = payload.sound   || '/static/sounds/health_alert.mp3';
  const data    = payload.data    || {};
  const tag     = data.category   || 'healthtrack';

  const options = {
    body,
    icon,
    badge,
    tag,
    renotify:          true,
    requireInteraction: data.type === 'reminder',
    vibrate:           [200, 100, 200, 100, 200],
    sound,
    data: { url: data.action_url || '/', ...data },
    actions: [
      { action: 'done',    title: '✓ Done',    icon: '/static/images/done-icon.png' },
      { action: 'snooze',  title: '⏰ Snooze 10min', icon: '/static/images/snooze-icon.png' },
    ],
  };

  event.waitUntil(
    self.registration.showNotification(title, options)
  );
});

// ── Notification Click ────────────────────────────────────────
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const data        = event.notification.data || {};
  const action      = event.action;
  const reminderId  = data.reminder_id;

  if (action === 'done' && reminderId) {
    // Mark reminder done via API
    event.waitUntil(
      fetch(`/api/v1/notifications/reminders/${reminderId}/done`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${data.token || ''}` }
      }).catch(() => {})
    );
  } else if (action === 'snooze' && reminderId) {
    event.waitUntil(
      fetch(`/api/v1/notifications/reminders/${reminderId}/snooze`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${data.token || ''}`
        },
        body: JSON.stringify({ minutes: 10 })
      }).catch(() => {})
    );
  } else {
    // Open app
    event.waitUntil(
      clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clientList => {
        const url = data.url || '/dashboard';
        for (const client of clientList) {
          if (client.url.includes(self.location.origin) && 'focus' in client) {
            client.navigate(url);
            return client.focus();
          }
        }
        if (clients.openWindow) return clients.openWindow(url);
      })
    );
  }
});

// ── Background Sync ───────────────────────────────────────────
self.addEventListener('sync', event => {
  if (event.tag === 'sync-health-data') {
    event.waitUntil(syncHealthData());
  }
});

async function syncHealthData() {
  // Sync any queued offline health data
  const db = await openDB();
  const queue = await db.getAll('offline-queue');
  for (const item of queue) {
    try {
      await fetch(item.url, { method: 'POST', body: JSON.stringify(item.data), headers: { 'Content-Type': 'application/json' } });
      await db.delete('offline-queue', item.id);
    } catch(e) {}
  }
}

function openDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open('healthtrack-offline', 1);
    req.onupgradeneeded = e => e.target.result.createObjectStore('offline-queue', { keyPath: 'id', autoIncrement: true });
    req.onsuccess = e => resolve(e.target.result);
    req.onerror   = reject;
  });
}