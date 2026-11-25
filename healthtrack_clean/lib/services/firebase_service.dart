// lib/services/firebase_service.dart — Firebase Integration for HealthTrack
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../constants/app_theme.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  late final FirebaseAuth _auth;
  late final FirebaseFirestore _firestore;
  late final FirebaseMessaging _messaging;

  // Initialize Firebase services
  Future<void> initialize() async {
    _auth = FirebaseAuth.instance;
    _firestore = FirebaseFirestore.instance;
    _messaging = FirebaseMessaging.instance;

    // Configure Firestore settings
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Request notification permissions
    await _requestNotificationPermissions();

    // Get FCM token
    await _getAndStoreFCMToken();
  }

  // Getters
  FirebaseAuth get auth => _auth;
  FirebaseFirestore get firestore => _firestore;
  FirebaseMessaging get messaging => _messaging;

  // Auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Current user
  User? get currentUser => _auth.currentUser;

  // ─── Authentication ────────────────────────────────────────────

  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  // Register with email and password
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );

    // Update display name
    await credential.user?.updateDisplayName(name.trim());

    // Create user document in Firestore
    await _createUserDocument(credential.user!.uid, {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'created_at': FieldValue.serverTimestamp(),
      'last_login': FieldValue.serverTimestamp(),
      'is_active': true,
      'is_verified': false,
      'onboarding_done': false,
      'dark_mode': false,
      'family_member_limit': 2,
    });

    return credential;
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  // Update user profile
  Future<void> updateProfile({
    String? name,
    String? photoURL,
  }) async {
    final user = _auth.currentUser;
    if (user != null) {
      if (name != null) await user.updateDisplayName(name);
      if (photoURL != null) await user.updatePhotoURL(photoURL);
    }
  }

  // ─── Firestore Operations ──────────────────────────────────────

  // Create user document
  Future<void> _createUserDocument(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).set(data);
  }

  // Get user document
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  // Update user document
  Future<void> updateUserData(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).update({
      ...data,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // Get user's subcollection reference
  CollectionReference _userSubcollection(String uid, String collection) {
    return _firestore.collection('users').doc(uid).collection(collection);
  }

  // ─── Health Metrics ────────────────────────────────────────────

  // Save health metric
  Future<void> saveHealthMetric({
    required String uid,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    await _userSubcollection(uid, 'health_metrics').add({
      'type': type,
      ...data,
      'recorded_at': FieldValue.serverTimestamp(),
      'synced': true,
    });
  }

  // Get health metrics
  Future<List<QueryDocumentSnapshot>> getHealthMetrics({
    required String uid,
    required String type,
    int limit = 50,
    DateTime? since,
  }) async {
    Query query = _userSubcollection(uid, 'health_metrics')
        .where('type', isEqualTo: type)
        .orderBy('recorded_at', descending: true)
        .limit(limit);

    if (since != null) {
      query = query.where('recorded_at', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    }

    final snapshot = await query.get();
    return snapshot.docs;
  }

  // ─── Medicines ────────────────────────────────────────────────

  // Get medicines
  Future<List<QueryDocumentSnapshot>> getMedicines({
    required String uid,
    bool activeOnly = true,
  }) async {
    Query query = _userSubcollection(uid, 'medicines')
        .orderBy('created_at', descending: true);

    if (activeOnly) {
      query = query.where('is_active', isEqualTo: true);
    }

    final snapshot = await query.get();
    return snapshot.docs;
  }

  // Add medicine
  Future<DocumentReference> addMedicine({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    return await _userSubcollection(uid, 'medicines').add({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // Update medicine
  Future<void> updateMedicine({
    required String uid,
    required String medicineId,
    required Map<String, dynamic> data,
  }) async {
    await _userSubcollection(uid, 'medicines').doc(medicineId).update({
      ...data,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // Delete medicine (soft delete)
  Future<void> deleteMedicine({
    required String uid,
    required String medicineId,
  }) async {
    await _userSubcollection(uid, 'medicines').doc(medicineId).update({
      'is_active': false,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // Log medicine taken
  Future<void> logMedicineTaken({
    required String uid,
    required String medicineId,
    required bool taken,
    String? scheduledTime,
  }) async {
    final today = DateTime.now();
    final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    await _userSubcollection(uid, 'medicine_logs').doc('${medicineId}_$dateStr${scheduledTime ?? ''}').set({
      'medicine_id': medicineId,
      'log_date': dateStr,
      'taken': taken,
      'scheduled_time': scheduledTime,
      'logged_at': FieldValue.serverTimestamp(),
      'synced': true,
    });

    // Auto-reduce stock if taken
    if (taken) {
      final medDoc = await _userSubcollection(uid, 'medicines').doc(medicineId).get();
      if (medDoc.exists) {
        final medData = medDoc.data() as Map<String, dynamic>;
        final stockCount = (medData['stock_count'] as int? ?? 0);
        if (stockCount > 0 && (medData['auto_reduce_stock'] as bool? ?? true)) {
          await _userSubcollection(uid, 'medicines').doc(medicineId).update({
            'stock_count': stockCount - 1,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }
    }
  }

  // ─── Lab Tests ────────────────────────────────────────────────

  Future<List<QueryDocumentSnapshot>> getLabTests({
    required String uid,
    required String category,
  }) async {
    final snapshot = await _userSubcollection(uid, 'lab_tests')
        .where('category', isEqualTo: category)
        .orderBy('test_date', descending: true)
        .limit(50)
        .get();
    return snapshot.docs;
  }

  Future<DocumentReference> addLabTest({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    return await _userSubcollection(uid, 'lab_tests').add({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ─── Appointments ────────────────────────────────────────────

  Future<List<QueryDocumentSnapshot>> getAppointments({
    required String uid,
    DateTime? since,
    bool upcomingOnly = false,
  }) async {
    Query query = _userSubcollection(uid, 'appointments')
        .orderBy('appointment_date', descending: false);

    if (upcomingOnly) {
      query = query.where('appointment_date', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now()));
    } else if (since != null) {
      query = query.where('appointment_date', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    }

    final snapshot = await query.get();
    return snapshot.docs;
  }

  Future<DocumentReference> addAppointment({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    return await _userSubcollection(uid, 'appointments').add({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // ─── Documents ────────────────────────────────────────────────

  Future<List<QueryDocumentSnapshot>> getDocuments({
    required String uid,
    String? type,
  }) async {
    Query query = _userSubcollection(uid, 'documents')
        .orderBy('uploaded_at', descending: true);

    if (type != null) {
      query = query.where('doc_type', isEqualTo: type);
    }

    final snapshot = await query.get();
    return snapshot.docs;
  }

  // ─── Family Members ──────────────────────────────────────────

  Future<List<QueryDocumentSnapshot>> getFamilyMembers(String uid) async {
    final snapshot = await _userSubcollection(uid, 'family_members')
        .where('is_active', isEqualTo: true)
        .get();
    return snapshot.docs;
  }

  // ─── Notifications ──────────────────────────────────────────

  Future<void> saveNotification({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    await _userSubcollection(uid, 'notifications').add({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
    });
  }

  Future<List<QueryDocumentSnapshot>> getNotifications({
    required String uid,
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    Query query = _userSubcollection(uid, 'notifications')
        .orderBy('created_at', descending: true)
        .limit(limit);

    if (unreadOnly) {
      query = query.where('is_read', isEqualTo: false);
    }

    final snapshot = await query.get();
    return snapshot.docs;
  }

  // ─── FCM & Push Notifications ────────────────────────────────

  Future<void> _requestNotificationPermissions() async {
    if (!kIsWeb) {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    }
  }

  Future<void> _getAndStoreFCMToken() async {
    try {
      String? token;
      if (kIsWeb) {
        // For web, use VAPID key
        token = await _messaging.getToken(vapidKey: 'YOUR_VAPID_KEY');
      } else {
        token = await _messaging.getToken();
      }

      if (token != null && currentUser != null) {
        await updateUserData(currentUser!.uid, {'fcm_token': token});
      }
    } catch (e) {
    // Use print instead of debugPrint for compatibility
    print('FCM token error: $e');
  }
  }

  // Listen to foreground messages
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  // Listen to background message taps
  Future<RemoteMessage?> getInitialMessage() async {
    return await _messaging.getInitialMessage();
  }

  // ─── Offline Sync Support ────────────────────────────────────

  // Enable offline persistence
  void enableOfflinePersistence() {
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // ─── Utility ──────────────────────────────────────────────────

  // Convert Firestore timestamp to DateTime
  DateTime? _timestampToDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  // Batch write for multiple operations
  Future<void> batchWrite(List<Future<void>> operations) async {
    final batch = _firestore.batch();
    for (final op in operations) {
      await op; // For simplicity, await each - in production use WriteBatch
    }
  }
}

// Extension for easy access
extension FirebaseServiceExtension on FirebaseService {
  // Quick access to common collections
  Query<Map<String, dynamic>> healthMetrics(String uid, String type) =>
      _userSubcollection(uid, 'health_metrics')
          .where('type', isEqualTo: type)
          .withConverter(
            fromFirestore: (snapshot, _) => snapshot.data() as Map<String, dynamic>,
            toFirestore: (firebaseObj, _) => firebaseObj,
          );

  CollectionReference medicines(String uid) => _userSubcollection(uid, 'medicines');
  CollectionReference medicineLogs(String uid) => _userSubcollection(uid, 'medicine_logs');
  CollectionReference labTests(String uid) => _userSubcollection(uid, 'lab_tests');
  CollectionReference appointments(String uid) => _userSubcollection(uid, 'appointments');
  CollectionReference documents(String uid) => _userSubcollection(uid, 'documents');
  CollectionReference familyMembers(String uid) => _userSubcollection(uid, 'family_members');
  CollectionReference notifications(String uid) => _userSubcollection(uid, 'notifications');
  CollectionReference reminders(String uid) => _userSubcollection(uid, 'reminders');
  CollectionReference healthTimeline(String uid) => _userSubcollection(uid, 'health_timeline');
}