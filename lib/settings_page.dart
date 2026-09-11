// =============================================================
// settings_page.dart
// マイページ画面(プロフィール表示・編集)。
// 元担当: しゅんたろう → 途中からHayatoが引き継ぎ
//
// ポイント:
//   - ローカルに保存された名前が空なら初回向けの「ようこそ」画面を、
//     設定済みなら通常のプロフィール画面を出し分けている
//   - プロフィール画像のアップロード(image_picker + Firebase Storage)は、
//     Storageの利用に課金プランへの変更が必要になる場面があり、
//     ハッカソンの制約上、費用面から完全には解決できていない
//   - UIはX(旧Twitter)やInstagramなど既存SNSアプリを参考に改良した
// =============================================================

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'firebase_service.dart';
import 'main.dart';

/// マイページ（設定）画面
/// Untitled-1 の SettingsScreen を、単独画面用の Widget として切り出したものです。
class SettingsScreen extends StatefulWidget {
  final FirebaseService firebaseService;
  final List<RecordItem> records;
  const SettingsScreen({super.key, required this.firebaseService, required this.records});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _userName = '';
  String _userStatus = '';
  String? _userIconPath;
  bool _isLoading = true;
  bool _publicRangeEnabled = false;
  bool _reminderNotificationEnabled = false;

  // 編集用のコントローラー
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _statusController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? '';
      _userStatus = prefs.getString('user_status') ?? '';
      _userIconPath = prefs.getString('user_icon_path');
      _nameController.text = _userName;
      _statusController.text = _userStatus;
      _publicRangeEnabled = prefs.getBool('public_range_enabled') ?? false;
      _reminderNotificationEnabled = prefs.getBool('reminder_notification_enabled') ?? false;
      _isLoading = false;
    });
  }

  // --- プロフィール編集ポップアップ ---
  void _showEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // キーボード表示に対応
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder( // モーダル内でsetStateを反映させる
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, // キーボード分上げる
            top: 20, left: 24, right: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("プロフィール設定", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                // アイコン変更
                GestureDetector(
                  onTap: () async {
                    await _pickImage();
                    setModalState(() {}); // モーダル内の再描画
                  },
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: (_userIconPath != null && File(_userIconPath!).existsSync())
                            ? FileImage(File(_userIconPath!)) : null,
                        child: _userIconPath == null ? const Icon(Icons.person, size: 50) : null,
                      ),
                      const Positioned(bottom: 0, right: 0, child: CircleAvatar(radius: 15, child: Icon(Icons.camera_alt, size: 15))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: "名前", filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _statusController,
                  maxLength: 50,
                  decoration: InputDecoration(labelText: "ひとこと", filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      await _saveSettings();
                      Navigator.pop(context); // 閉じる
                      _loadProfile(); // 親画面を更新
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text("設定を完了する"),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ギャラリーから画像を選択し、まず端末内(アプリのドキュメントディレクトリ)に保存する。
  // ここで保存したパスは、firebase_service.dartのsaveUserProfile内でFirebase Storageへの
  // アップロードにも使われる想定だが、Storageの利用には課金プランへの変更が必要になる場面があり、
  // ハッカソンの制約(費用面)から、アップロードが安定して動作するところまでは解決できていない。
  Future<void> _pickImage() async {
    final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'user_icon_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedImage = await File(image.path).copy('${appDir.path}/$fileName');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_icon_path', savedImage.path);
      setState(() => _userIconPath = savedImage.path);
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text);
    await prefs.setString('user_status', _statusController.text);
    await prefs.setBool('public_range_enabled', _publicRangeEnabled);
    await prefs.setBool('reminder_notification_enabled', _reminderNotificationEnabled);

    if (_userIconPath != null) {
      await prefs.setString('user_icon_path', _userIconPath!);
    }

    // Firestoreにもユーザー情報を保存
    final userId = widget.firebaseService.currentUser?.uid;
    if (userId != null) {
      await widget.firebaseService.saveUserProfile(
        userId: userId,
        name: _nameController.text,
        email: '', // メールアドレスは削除（Untitled-1のUIにはない）
        status: _statusController.text,
        iconPath: _userIconPath,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // 初回起動時の体験を考慮したUI分岐。
    // 初めての人（名前が空）なら、PDFのウェルカム画面を表示
    if (_userName.isEmpty) {
      return _buildWelcomeView();
    }

    // すでに設定済みの人のプロフィール表示画面
    return _buildProfileView();
  }

  // --- 初回用：ウェルカム表示 ---
  Widget _buildWelcomeView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Virtulance", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("ようこそ！", style: TextStyle(fontSize: 18, color: Colors.grey)),
            const Text("プロフィールを設定しましょう！", style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _showEditSheet,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
              child: const Text("プロフィールを設定する"),
            ),
          ],
        ),
      ),
    );
  }

  // --- 通常用：プロフィール表示画面 ---
  Widget _buildProfileView() {
    // 現在のユーザーIDを取得
    final currentUserId = widget.firebaseService.currentUser?.uid ?? '';

    // ローカルの公開記録を取得
    final localPublicRecords = widget.records.where((r) => r.isPublic).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.settings, color: Colors.black), onPressed: _showEditSheet)],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // StreamBuilderが自動的に再読み込みするので、少し待つ
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: StreamBuilder<QuerySnapshot>(
          stream: currentUserId.isNotEmpty
              ? widget.firebaseService.getPublicRecordsStream()
              : null,
          builder: (context, snapshot) {
            // ローカルの統計を計算
            int localPostsCount = localPublicRecords.length;
            int localTotalLikes = localPublicRecords.fold(0, (sum, item) => sum + item.likes);

            // Firestoreの統計を計算
            int firestorePostsCount = 0;
            int firestoreTotalLikes = 0;

            if (snapshot.hasData && currentUserId.isNotEmpty) {
              final firestoreRecords = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['userId'] == currentUserId;
              }).toList();

              firestorePostsCount = firestoreRecords.length;
              firestoreTotalLikes = firestoreRecords.fold(0, (sum, doc) {
                final data = doc.data() as Map<String, dynamic>;
                return sum + (data['likes'] as int? ?? 0);
              });
            }

            // 合計を計算
            final totalPostsCount = localPostsCount + firestorePostsCount;
            final totalLikes = localTotalLikes + firestoreTotalLikes;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: CircleAvatar(
                      radius: 55, backgroundColor: Colors.grey.shade200,
                      backgroundImage: (_userIconPath != null && File(_userIconPath!).existsSync()) ? FileImage(File(_userIconPath!)) : null,
                      child: _userIconPath == null ? const Icon(Icons.person, size: 60, color: Colors.white) : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(_userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(_userStatus, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade600))),
                  const SizedBox(height: 40),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24), padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatItem("高評価", totalLikes.toString(), onTap: null),
                        Container(width: 1, height: 30, color: Colors.grey.shade300),
                        _buildStatItem("投稿", totalPostsCount.toString(), onTap: () => _showMyPosts(currentUserId, localPublicRecords, snapshot)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // 高評価した投稿セクション
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '高評価した投稿',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildLikedPostsSection(currentUserId),
                      ],
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                  const Padding(padding: EdgeInsets.only(bottom: 40), child: Text("Virtulance", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFE0E0E0), letterSpacing: 2))),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // 高評価した投稿セクションを構築
  Widget _buildLikedPostsSection(String currentUserId) {
    if (currentUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.firebaseService.getLikedRecords(currentUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(20.0),
            child: CircularProgressIndicator(),
          ));
        }

        if (snapshot.hasError) {
          return Center(child: Text('エラー: ${snapshot.error}'));
        }

        final likedRecords = snapshot.data ?? [];
        if (likedRecords.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'まだ高評価した投稿がありません',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: likedRecords.length > 10 ? 10 : likedRecords.length,
            itemBuilder: (context, index) {
              final record = likedRecords[index];
              final data = record['data'] as Map<String, dynamic>;
              final type = data['type'] as String;
              final comment = data['comment'] as String;
              final value = data['value'] as int;
              final date = data['date'];
              final userId = data['userId'] as String? ?? '';
              DateTime? dateTime;
              if (date != null && date is Timestamp) {
                dateTime = date.toDate();
              }

              // ユーザー情報を取得
              return FutureBuilder<Map<String, dynamic>?>(
                future: widget.firebaseService.getUserProfile(userId),
                builder: (context, profileSnapshot) {
                  final userName = profileSnapshot.hasData
                      ? (profileSnapshot.data?['name'] as String? ?? '匿名ユーザー')
                      : '匿名ユーザー';
                  final iconUrl = profileSnapshot.hasData
                      ? (profileSnapshot.data?['iconUrl'] as String?)
                      : null;

                  return Container(
                    width: 280,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          dense: true,
                          leading: iconUrl != null
                              ? CircleAvatar(
                            radius: 18,
                            backgroundImage: NetworkImage(iconUrl),
                            onBackgroundImageError: (_, __) {},
                          )
                              : const CircleAvatar(
                            radius: 18,
                            child: Icon(Icons.person, size: 18),
                          ),
                          title: Text(
                            userName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: dateTime != null
                              ? Text(
                            '${dateTime.year}/${dateTime.month}/${dateTime.day}',
                            style: const TextStyle(fontSize: 10),
                          )
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            comment,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    type == '徳'
                                        ? Icons.auto_awesome
                                        : Icons.currency_yen,
                                    size: 16,
                                    color: type == '徳'
                                        ? Colors.amber[700]
                                        : Colors.blueGrey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$value${type == '徳' ? 'Pt' : '円'}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: value >= 0 ? Colors.black : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const Icon(
                                Icons.thumb_up,
                                size: 16,
                                color: Colors.blue,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, {VoidCallback? onTap}) {
    final widget = Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: widget,
      );
    }
    return widget;
  }

  // 自分の投稿一覧を表示
  void _showMyPosts(String currentUserId, List<RecordItem> localPublicRecords, AsyncSnapshot<QuerySnapshot> snapshot) {
    // ローカルの公開記録を取得
    final localRecords = localPublicRecords.map((record) {
      return {
        'recordId': null,
        'data': {
          'type': record.type,
          'comment': record.comment,
          'value': record.value,
          'date': Timestamp.fromDate(record.date),
          'likes': record.likes,
          'dislikes': record.dislikes,
        },
        'isLocal': true,
      };
    }).toList();

    // Firestoreの記録を取得
    List<Map<String, dynamic>> firestoreRecords = [];
    if (snapshot.hasData && currentUserId.isNotEmpty) {
      firestoreRecords = snapshot.data!.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['userId'] == currentUserId;
      }).map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'recordId': doc.id,
          'data': data,
          'isLocal': false,
        };
      }).toList();
    }

    // すべての記録を統合
    final allRecords = <Map<String, dynamic>>[];
    allRecords.addAll(localRecords);
    allRecords.addAll(firestoreRecords);

    // 日付でソート
    allRecords.sort((a, b) {
      final aDate = (a['data'] as Map<String, dynamic>)['date'] as Timestamp;
      final bDate = (b['data'] as Map<String, dynamic>)['date'] as Timestamp;
      return bDate.compareTo(aDate);
    });

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ヘッダー
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '投稿一覧',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // 投稿リスト
              Expanded(
                child: allRecords.isEmpty
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('まだ投稿がありません'),
                  ),
                )
                    : ListView.builder(
                  shrinkWrap: true,
                  itemCount: allRecords.length,
                  itemBuilder: (context, index) {
                    final record = allRecords[index];
                    final data = record['data'] as Map<String, dynamic>;
                    final type = data['type'] as String;
                    final comment = data['comment'] as String;
                    final value = data['value'] as int;
                    final likes = data['likes'] as int? ?? 0;
                    final date = data['date'];
                    DateTime? dateTime;
                    if (date != null) {
                      if (date is Timestamp) {
                        dateTime = date.toDate();
                      }
                    }
                    return ListTile(
                      leading: Icon(
                        type == '徳'
                            ? Icons.auto_awesome
                            : Icons.currency_yen,
                        color: type == '徳'
                            ? Colors.amber[700]
                            : Colors.blueGrey,
                      ),
                      title: Text(
                        comment,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: dateTime != null
                          ? Text(
                        '${dateTime.year}/${dateTime.month}/${dateTime.day} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      )
                          : null,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$value${type == '徳' ? 'Pt' : '円'}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: value >= 0 ? Colors.black : Colors.red,
                            ),
                          ),
                          if (likes > 0)
                            Text(
                              '👍 $likes',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _statusController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
