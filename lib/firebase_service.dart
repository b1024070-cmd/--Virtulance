// =============================================================
// firebase_service.dart
// Firebase(Auth / Firestore / Storage)へのアクセスをまとめたサービス層。
// 担当: すけすけ
//
// 各画面(search_page.dart, record_page.dart, global_page.dartなど)は
// Firestoreや Storage を直接扱わず、必ずこのクラス経由でアクセスする。
// 匿名認証を採用しているため、ユーザーはログイン操作なしにすぐ使い始められる。
// =============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'main.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // 現在のユーザーを取得
  User? get currentUser => _auth.currentUser;

  // 匿名認証でログイン
  Future<void> signInAnonymously() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  // ユーザー情報を保存・更新
  Future<void> saveUserProfile({
    required String userId,
    required String name,
    required String email,
    String? status,
    String? iconPath,
  }) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);

      Map<String, dynamic> userData = {
        'name': name,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (status != null && status.isNotEmpty) {
        userData['status'] = status;
      }

      // アイコン画像をアップロード
      if (iconPath != null && File(iconPath).existsSync()) {
        try {
          final ref = _storage.ref().child('user_icons/$userId.jpg');
          await ref.putFile(File(iconPath));
          final downloadUrl = await ref.getDownloadURL();
          userData['iconUrl'] = downloadUrl;
          print('アイコンをアップロードしました: $downloadUrl');
        } catch (e) {
          print('アイコンアップロードエラー: $e');
        }
      }

      await userRef.set(userData, SetOptions(merge: true));
      print('ユーザー情報を保存しました: $userId - $name');
    } catch (e) {
      print('ユーザー情報保存エラー: $e');
      rethrow;
    }
  }

  // ユーザー情報を取得
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (doc.exists) {
      return doc.data();
    }
    return null;
  }

  // 記録をFirestoreに保存
  Future<void> saveRecord(RecordItem record, String userId) async {
    try {
      final docRef = await _firestore.collection('records').add({
        'userId': userId,
        'type': record.type,
        'comment': record.comment,
        'value': record.value,
        'date': Timestamp.fromDate(record.date),
        'isPublic': record.isPublic,
        'likes': record.likes,
        'dislikes': record.dislikes,
        'likedBy': [], // いいねを押したユーザーIDのリスト
        'dislikedBy': [], // 低評価を押したユーザーIDのリスト
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('Firestoreに記録を保存しました: ${docRef.id} - ${record.comment}');
    } catch (e) {
      print('Firestore保存エラー: $e');
      rethrow;
    }
  }

  // 記録を更新
  Future<void> updateRecord(String recordId, RecordItem record) async {
    await _firestore.collection('records').doc(recordId).update({
      'type': record.type,
      'comment': record.comment,
      'value': record.value,
      'isPublic': record.isPublic,
      'likes': record.likes,
      'dislikes': record.dislikes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 記録を削除
  Future<void> deleteRecord(String recordId) async {
    await _firestore.collection('records').doc(recordId).delete();
  }

  // 公開された記録をリアルタイムで取得
  Stream<QuerySnapshot> getPublicRecordsStream() {
    return _firestore
        .collection('records')
        .where('isPublic', isEqualTo: true)
        .orderBy('date', descending: true)
        .limit(100) // パフォーマンス向上のため制限
        .snapshots()
        .handleError((error) {
      print('Firestore取得エラー: $error');
      // エラーが発生してもストリームを継続
    });
  }

  // 記録をRecordItemに変換
  Future<RecordItem> recordFromFirestore(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    return RecordItem(
      type: data['type'] as String,
      comment: data['comment'] as String,
      value: data['value'] as int,
      date: (data['date'] as Timestamp).toDate(),
      isPublic: data['isPublic'] as bool? ?? false,
      likes: data['likes'] as int? ?? 0,
      dislikes: data['dislikes'] as int? ?? 0,
    );
  }

  // 記録のいいね/低評価を更新（重複押しを防ぐ）
  //
  // ポイント: likedBy/dislikedBy という「押したユーザーIDの配列」を記録側に持たせることで、
  // 同じユーザーが多重にいいねを押せないようにしている。
  // また、いいねを押した際に既に低評価が付いていれば自動的に取り消す(相互排他)ことで、
  // 1ユーザーにつき「いいね」か「低評価」のどちらか一方だけが有効な状態を保証している。
  Future<void> updateRecordReaction(String recordId, {bool? like, bool? dislike}) async {
    final userId = currentUser?.uid;
    if (userId == null) return;

    final recordRef = _firestore.collection('records').doc(recordId);
    final recordDoc = await recordRef.get();

    if (!recordDoc.exists) return;

    final data = recordDoc.data() as Map<String, dynamic>;
    final likedBy = List<String>.from(data['likedBy'] as List? ?? []);
    final dislikedBy = List<String>.from(data['dislikedBy'] as List? ?? []);

    if (like != null && like) {
      // いいねを押す
      if (!likedBy.contains(userId)) {
        // まだ押していない場合
        if (dislikedBy.contains(userId)) {
          // 低評価を押していた場合は削除
          dislikedBy.remove(userId);
          await recordRef.update({
            'dislikes': FieldValue.increment(-1),
            'dislikedBy': dislikedBy,
          });
        }
        // いいねを追加
        likedBy.add(userId);
        await recordRef.update({
          'likes': FieldValue.increment(1),
          'likedBy': likedBy,
        });
      }
    } else if (like != null && !like) {
      // いいねを解除
      if (likedBy.contains(userId)) {
        likedBy.remove(userId);
        await recordRef.update({
          'likes': FieldValue.increment(-1),
          'likedBy': likedBy,
        });
      }
    }

    if (dislike != null && dislike) {
      // 低評価を押す
      if (!dislikedBy.contains(userId)) {
        // まだ押していない場合
        if (likedBy.contains(userId)) {
          // いいねを押していた場合は削除
          likedBy.remove(userId);
          await recordRef.update({
            'likes': FieldValue.increment(-1),
            'likedBy': likedBy,
          });
        }
        // 低評価を追加
        dislikedBy.add(userId);
        await recordRef.update({
          'dislikes': FieldValue.increment(1),
          'dislikedBy': dislikedBy,
        });
      }
    } else if (dislike != null && !dislike) {
      // 低評価を解除
      if (dislikedBy.contains(userId)) {
        dislikedBy.remove(userId);
        await recordRef.update({
          'dislikes': FieldValue.increment(-1),
          'dislikedBy': dislikedBy,
        });
      }
    }
  }

  // ユーザーが既にいいね/低評価を押したかどうかを確認
  Future<Map<String, bool>> checkUserReaction(String recordId) async {
    final userId = currentUser?.uid;
    if (userId == null) return {'liked': false, 'disliked': false};

    try {
      final recordDoc = await _firestore.collection('records').doc(recordId).get();
      if (!recordDoc.exists) return {'liked': false, 'disliked': false};

      final data = recordDoc.data() as Map<String, dynamic>;
      final likedBy = List<String>.from(data['likedBy'] as List? ?? []);
      final dislikedBy = List<String>.from(data['dislikedBy'] as List? ?? []);

      return {
        'liked': likedBy.contains(userId),
        'disliked': dislikedBy.contains(userId),
      };
    } catch (e) {
      return {'liked': false, 'disliked': false};
    }
  }

  // ユーザーを名前で検索
  //
  // 注意: Firestoreは文字列の「部分一致」検索に対応していないため、
  // まず前方一致のクエリ(isGreaterThanOrEqualTo / isLessThanOrEqualTo + '\uf8ff')で候補を絞り込み、
  // 取得できた結果に対してさらにDart側で部分一致フィルタをかける、という2段階の実装にしている。
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      if (query.trim().isEmpty) {
        return [];
      }

      // Firestoreのクエリで名前を検索
      // 注意: Firestoreは部分一致検索ができないため、前方一致で検索
      final querySnapshot = await _firestore
          .collection('users')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: query + '\uf8ff')
          .limit(20)
          .get();

      final results = <Map<String, dynamic>>[];
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        // 部分一致チェック（大文字小文字を区別しない）
        final name = (data['name'] as String? ?? '').toLowerCase();
        if (name.contains(query.toLowerCase())) {
          results.add({
            'userId': doc.id,
            'name': data['name'] ?? '匿名ユーザー',
            'status': data['status'] ?? '',
            'iconUrl': data['iconUrl'],
          });
        }
      }

      return results;
    } catch (e) {
      print('ユーザー検索エラー: $e');
      return [];
    }
  }

  // 特定ユーザーの投稿を取得
  Future<List<Map<String, dynamic>>> getUserRecords(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('records')
          .where('userId', isEqualTo: userId)
          .where('isPublic', isEqualTo: true)
          .orderBy('date', descending: true)
          .limit(50)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'recordId': doc.id,
          'data': data,
        };
      }).toList();
    } catch (e) {
      print('ユーザー投稿取得エラー: $e');
      return [];
    }
  }

  // 現在のユーザーが高評価した投稿を取得
  Future<List<Map<String, dynamic>>> getLikedRecords(String userId) async {
    try {
      // Firestoreでは配列に含まれる要素を直接検索できないため、
      // 公開されているすべての投稿を取得してフィルタリング
      final querySnapshot = await _firestore
          .collection('records')
          .where('isPublic', isEqualTo: true)
          .orderBy('date', descending: true)
          .limit(100)
          .get();

      final likedRecords = <Map<String, dynamic>>[];
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final likedBy = List<String>.from(data['likedBy'] as List? ?? []);
        if (likedBy.contains(userId)) {
          likedRecords.add({
            'recordId': doc.id,
            'data': data,
          });
        }
      }

      return likedRecords;
    } catch (e) {
      print('高評価投稿取得エラー: $e');
      return [];
    }
  }
}

