// =============================================================
// global_page.dart
// 「最新投稿」タブと「ランキング」タブを持つグローバル画面。
// 担当: Hayato
//
// この画面は4画面の中でも特に実装に苦労した画面で、以下すべてで難しさがあった:
//   - StreamBuilderによるリアルタイム更新の仕組み
//   - いいね/低評価の相互排他処理(実体はfirebase_service.dart側)
//   - 初回ロード時、ローカルの公開記録を先に表示するオフライン配慮
//   - ランキングの集計方法
//
// 既知の未解決課題(開発中から認識):
//   - _rankingPeriod(日間/月間/全期間)の値はUI上で切り替えられるが、
//     実際の集計クエリではこの値を参照しておらず、常に全期間のデータが出る
//   - ランキングは「ユーザーごとの合計」ではなく「個々の投稿レコード」を
//     値の降順で並べているだけなので、同じユーザーが複数回ランクインしうる
//   詳細はポートフォリオのProblems & Improvements参照。
// =============================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'firebase_service.dart';

class GlobalPage extends StatefulWidget {
  final List<RecordItem> records;
  final Function(RecordItem) onUpdate;
  final FirebaseService firebaseService;
  const GlobalPage({
    super.key,
    required this.records,
    required this.onUpdate,
    required this.firebaseService,
  });

  @override
  State<GlobalPage> createState() => _GlobalPageState();
}

class _GlobalPageState extends State<GlobalPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _rankingType = '徳';      // '徳' or '収支'
  String _rankingPeriod = '全期間'; // '日間', '月間', '全期間'
  String _latestFilter = 'すべて'; // 'すべて', '徳', '収支'
  Map<String, Map<String, dynamic>> _userProfiles = {}; // userId -> ユーザー情報
  final Set<String> _loadingUserIds = {}; // 読み込み中のユーザーID
  Map<String, Map<String, bool>> _userReactions = {}; // recordId -> {liked: bool, disliked: bool}

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ユーザー情報を一括取得（キャッシュがあれば使用）
  Future<void> _loadUserProfiles(Set<String> userIds) async {
    final missingIds = userIds.where((id) =>
    !_userProfiles.containsKey(id) && !_loadingUserIds.contains(id)
    ).toSet();

    if (missingIds.isEmpty) return;

    _loadingUserIds.addAll(missingIds);

    // 並列でユーザー情報を取得
    final futures = missingIds.map((userId) async {
      try {
        final profile = await widget.firebaseService.getUserProfile(userId);
        if (profile != null && mounted) {
          setState(() {
            _userProfiles[userId] = profile;
          });
        }
      } catch (e) {
        print('ユーザー情報取得エラー ($userId): $e');
      } finally {
        _loadingUserIds.remove(userId);
      }
    });

    await Future.wait(futures);
  }

  // ユーザー情報を取得（キャッシュから）
  Map<String, dynamic>? _getUserProfileSync(String userId) {
    return _userProfiles[userId];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF), // 薄い青みのある背景
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.transparent, // 下線なし
          tabs: const [Tab(text: '最新'), Tab(text: 'ランキング')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLatestTimeline(),
          _buildRankingSection(),
        ],
      ),
    );
  }

  // --- 最新タブ (Firebaseリアルタイム取得 + ローカル記録) ---
  Widget _buildLatestTimeline() {
    return Column(
      children: [
        // フィルターボタン
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ['すべて', '徳', '収支'].map((filter) {
              bool isSelected = _latestFilter == filter;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _latestFilter = filter;
                      });
                    }
                  },
                  selectedColor: Colors.blue,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // 投稿リスト
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              // ユーザープロフィールキャッシュをクリアして再読み込み
              setState(() {
                _userProfiles.clear();
              });
              // StreamBuilderが自動的に再読み込みするので、少し待つ
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: StreamBuilder<QuerySnapshot>(
              // Firestoreの公開記録をリアルタイムで購読する。
              // 通信が遅い/オフラインの間は snapshot.data が null のままになるため、
              // その間は端末内のローカル公開記録を先に表示し、投稿がゼロに見えないようにしている。
              stream: widget.firebaseService.getPublicRecordsStream(),
              builder: (context, snapshot) {
                // エラー時のデバッグ情報
                if (snapshot.hasError) {
                  print('StreamBuilderエラー: ${snapshot.error}');
                }
                // ローカルの公開記録も取得
                final localPublicRecords = widget.records.where((r) => r.isPublic).toList();
                localPublicRecords.sort((a, b) => b.date.compareTo(a.date));
                print('ローカルの公開記録: ${localPublicRecords.length} 件');

                if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
                  // 初回ロード時のみローカル記録を表示
                  if (localPublicRecords.isNotEmpty) {
                    return _buildRecordsList(localPublicRecords, isLocal: true);
                  }
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  // エラー時もローカル記録を表示
                  if (localPublicRecords.isNotEmpty) {
                    return _buildRecordsList(localPublicRecords, isLocal: true);
                  }
                  return Center(child: Text('エラー: ${snapshot.error}'));
                }

                // Firestoreの記録を取得
                List<Map<String, dynamic>> firestoreRecords = [];
                if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                  print('Firestoreから ${snapshot.data!.docs.length} 件の記録を取得');
                  final currentUserId = widget.firebaseService.currentUser?.uid ?? '';

                  firestoreRecords = snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final recordId = doc.id;

                    // ユーザーが既にいいね/低評価を押したかどうかを確認
                    final likedBy = List<String>.from(data['likedBy'] as List? ?? []);
                    final dislikedBy = List<String>.from(data['dislikedBy'] as List? ?? []);

                    // 状態を更新
                    if (recordId.isNotEmpty && currentUserId.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _userReactions[recordId] = {
                              'liked': likedBy.contains(currentUserId),
                              'disliked': dislikedBy.contains(currentUserId),
                            };
                          });
                        }
                      });
                    }

                    return {
                      'recordId': recordId,
                      'userId': data['userId'] as String? ?? '',
                      'data': data,
                    };
                  }).toList();
                } else {
                  print('Firestoreから記録が取得できませんでした');
                }

                // ローカル記録とFirestore記録を統合
                final allRecords = <Map<String, dynamic>>[];

                // ローカル記録を追加（Firestoreに保存されていないもの）
                final currentUserId = widget.firebaseService.currentUser?.uid ?? '';
                for (var record in localPublicRecords) {
                  allRecords.add({
                    'recordId': null, // ローカル記録はIDがない
                    'userId': currentUserId,
                    'data': {
                      'type': record.type,
                      'comment': record.comment,
                      'value': record.value,
                      'date': Timestamp.fromDate(record.date),
                      'isPublic': record.isPublic,
                      'likes': record.likes,
                      'dislikes': record.dislikes,
                    },
                    'isLocal': true,
                  });
                }

                // Firestore記録を追加
                allRecords.addAll(firestoreRecords);

                // 日付でソート
                allRecords.sort((a, b) {
                  final aDate = (a['data'] as Map<String, dynamic>)['date'] as Timestamp;
                  final bDate = (b['data'] as Map<String, dynamic>)['date'] as Timestamp;
                  return bDate.compareTo(aDate);
                });

                // フィルター適用
                List<Map<String, dynamic>> filteredRecords = allRecords;
                if (_latestFilter != 'すべて') {
                  filteredRecords = allRecords.where((record) {
                    final data = record['data'] as Map<String, dynamic>;
                    final type = data['type'] as String;
                    return type == _latestFilter;
                  }).toList();
                }

                if (filteredRecords.isEmpty) {
                  return const Center(child: Text('まだ投稿がありません'));
                }

                // 必要なユーザーIDを収集
                final userIds = filteredRecords.map((r) => r['userId'] as String).where((id) => id.isNotEmpty).toSet();
                _loadUserProfiles(userIds);

                return _buildRecordsList(filteredRecords);
              },
            ),
          ),
        ),
      ],
    );
  }

  // 記録リストを構築
  Widget _buildRecordsList(List<dynamic> records, {bool isLocal = false}) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        final data = record['data'] as Map<String, dynamic>;
        final userId = record['userId'] as String? ?? '';
        final recordId = record['recordId'] as String?;
        final isLocalRecord = record['isLocal'] as bool? ?? false;

        // ユーザー情報を取得（キャッシュから）
        final profile = _getUserProfileSync(userId);
        final userName = profile?['name'] as String? ??
            (userId == widget.firebaseService.currentUser?.uid ? 'あなた' : '匿名ユーザー');
        final iconUrl = profile?['iconUrl'] as String?;

        return _buildRecordCard(
          data: data,
          recordId: recordId,
          userId: userId,
          userName: userName,
          iconUrl: iconUrl,
          isLocal: isLocalRecord,
        );
      },
    );
  }

  // 記録カードを構築
  Widget _buildRecordCard({
    required Map<String, dynamic> data,
    String? recordId,
    required String userId,
    required String userName,
    String? iconUrl,
    bool isLocal = false,
  }) {
    final likes = data['likes'] as int? ?? 0;
    final dislikes = data['dislikes'] as int? ?? 0;
    final type = data['type'] as String;
    final comment = data['comment'] as String;
    final value = data['value'] as int;
    final date = data['date'] is Timestamp
        ? (data['date'] as Timestamp).toDate()
        : DateTime.now();

    // 記録がFirestoreから来た場合、likedBy/dislikedByを確認
    final likedBy = data['likedBy'] as List?;
    final dislikedBy = data['dislikedBy'] as List?;
    final currentUserId = widget.firebaseService.currentUser?.uid ?? '';

    // ユーザーが既にいいね/低評価を押したかどうかを確認
    bool userHasLiked = false;
    bool userHasDisliked = false;

    if (recordId != null && currentUserId.isNotEmpty) {
      // まず、_userReactionsから確認
      final reaction = _userReactions[recordId];
      if (reaction != null) {
        userHasLiked = reaction['liked'] ?? false;
        userHasDisliked = reaction['disliked'] ?? false;
      } else if (likedBy != null || dislikedBy != null) {
        // _userReactionsにない場合は、dataから確認
        userHasLiked = likedBy != null && likedBy.contains(currentUserId);
        userHasDisliked = dislikedBy != null && dislikedBy.contains(currentUserId);
        // 状態を保存
        _userReactions[recordId] = {
          'liked': userHasLiked,
          'disliked': userHasDisliked,
        };
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          ListTile(
            leading: GestureDetector(
              onTap: () => _showUserProfile(userId, userName, iconUrl, _getUserProfileSync(userId)?['status'] as String?),
              child: iconUrl != null
                  ? CircleAvatar(
                backgroundImage: NetworkImage(iconUrl),
                onBackgroundImageError: (_, __) {},
              )
                  : const CircleAvatar(child: Icon(Icons.person)),
            ),
            title: GestureDetector(
              onTap: () => _showUserProfile(userId, userName, iconUrl, _getUserProfileSync(userId)?['status'] as String?),
              child: Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            subtitle: Text(comment),
            trailing: Text(
              '$value${type == '徳' ? 'Pt' : '円'}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: value < 0
                    ? Colors.red
                    : (type == '徳' ? Colors.blue : Colors.green[700]!),
              ),
            ),
          ),
          // 高評価・低評価ボタン
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    userHasLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                    size: 20,
                    color: userHasLiked ? Colors.blue : Colors.grey,
                  ),
                  onPressed: isLocal || recordId == null
                      ? null // ローカル記録は無効
                      : () async {
                    // 既に押している場合は取り消し、押していない場合は追加
                    if (userHasLiked) {
                      // 取り消し
                      await widget.firebaseService.updateRecordReaction(recordId, like: false);
                      setState(() {
                        _userReactions[recordId] = {'liked': false, 'disliked': false};
                      });
                    } else {
                      // 追加（低評価を押していた場合は自動的に取り消される）
                      await widget.firebaseService.updateRecordReaction(recordId, like: true);
                      setState(() {
                        _userReactions[recordId] = {'liked': true, 'disliked': false};
                      });
                    }
                  },
                ),
                Text('$likes'),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(
                    userHasDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                    size: 20,
                    color: userHasDisliked ? Colors.red : Colors.grey,
                  ),
                  onPressed: isLocal || recordId == null
                      ? null // ローカル記録は無効
                      : () async {
                    // 既に押している場合は取り消し、押していない場合は追加
                    if (userHasDisliked) {
                      // 取り消し
                      await widget.firebaseService.updateRecordReaction(recordId, dislike: false);
                      setState(() {
                        _userReactions[recordId] = {'liked': false, 'disliked': false};
                      });
                    } else {
                      // 追加（高評価を押していた場合は自動的に取り消される）
                      await widget.firebaseService.updateRecordReaction(recordId, dislike: true);
                      setState(() {
                        _userReactions[recordId] = {'liked': false, 'disliked': true};
                      });
                    }
                  },
                ),
                Text('$dislikes'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- ランキングタブ ---
  Widget _buildRankingSection() {
    return Column(
      children: [
        const SizedBox(height: 16),
        // 1. 徳・収支の切り替えスイッチ
        _buildTypeSwitcher(),
        const SizedBox(height: 16),
        // 2. 日間・月間・全期間の切り替え
        _buildPeriodSelector(),
        const SizedBox(height: 16),
        // 3. ランキングリスト
        Expanded(child: _buildRankingList()),
      ],
    );
  }

  Widget _buildTypeSwitcher() {
    return Container(
      width: 250,
      height: 45,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          _buildTypeBtn('徳'),
          _buildTypeBtn('収支'),
        ],
      ),
    );
  }

  Widget _buildTypeBtn(String type) {
    bool isSelected = _rankingType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _rankingType = type),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
          ),
          alignment: Alignment.center,
          child: Text(type, style: TextStyle(color: isSelected ? Colors.white : Colors.blue, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: ['日間', '月間', '全期間'].map((p) {
        bool isSelected = _rankingPeriod == p;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: isSelected ? Colors.blue.withOpacity(0.1) : Colors.white,
              side: BorderSide(color: isSelected ? Colors.blue : Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => setState(() => _rankingPeriod = p),
            child: Row(
              children: [
                if (isSelected) const Icon(Icons.check, size: 16, color: Colors.blue),
                Text(p, style: TextStyle(color: isSelected ? Colors.blue : Colors.grey)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRankingList() {
    return RefreshIndicator(
      onRefresh: () async {
        // ユーザープロフィールキャッシュをクリアして再読み込み
        setState(() {
          _userProfiles.clear();
        });
        // StreamBuilderが自動的に再読み込みするので、少し待つ
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: StreamBuilder<QuerySnapshot>(
        stream: widget.firebaseService.getPublicRecordsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('ランキングデータがありません'));
          }

          // フィルタリングとソート
          //
          // 【既知の課題】ここでは「ユーザーごとの合計」ではなく「個々の投稿レコード」を
          // そのまま値の降順に並べている。そのため、同じユーザーが複数回投稿していれば
          // 複数回ランクインしうる(「累計データ」という表示ラベルと実際の挙動が一致していない)。
          // また _rankingPeriod(日間/月間/全期間)の値もここでは参照しておらず、常に全期間で集計している。
          // 本来はuserIdごとにvalueを合計してから並び替える集計処理が必要。
          final filtered = snapshot.data!.docs
              .where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['type'] == _rankingType;
          })
              .toList();

          filtered.sort((a, b) {
            final aValue = (a.data() as Map<String, dynamic>)['value'] as int;
            final bValue = (b.data() as Map<String, dynamic>)['value'] as int;
            return bValue.compareTo(aValue);
          });

          // 必要なユーザーIDを収集
          final userIds = filtered.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['userId'] as String? ?? '';
          }).where((id) => id.isNotEmpty).toSet();
          _loadUserProfiles(userIds);

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length > 20 ? 20 : filtered.length,
            itemBuilder: (context, index) {
              final doc = filtered[index];
              final data = doc.data() as Map<String, dynamic>;
              final userId = data['userId'] as String? ?? '';
              final value = data['value'] as int;

              final profile = _getUserProfileSync(userId);
              final userName = profile?['name'] as String? ?? 'ランク王者 ${index + 1}';
              final iconUrl = profile?['iconUrl'] as String?;
              final status = profile?['status'] as String?;

              return GestureDetector(
                onTap: () => _showUserProfile(userId, userName, iconUrl, status),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)],
                  ),
                  child: Row(
                    children: [
                      _buildRankIcon(index + 1),
                      const SizedBox(width: 12),
                      if (iconUrl != null) ...[
                        CircleAvatar(
                          radius: 20,
                          backgroundImage: NetworkImage(iconUrl),
                          onBackgroundImageError: (_, __) {},
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const Text('累計データ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text(
                        '$value ${_rankingType == '徳' ? 'Pt' : '円'}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: value < 0
                              ? Colors.red
                              : (_rankingType == '徳' ? Colors.blue : Colors.green[700]!),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRankIcon(int rank) {
    if (rank == 1) {
      return Stack(
        alignment: Alignment.center,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFFFD700), // 金色
            radius: 25,
            child: Icon(Icons.person, color: Colors.white, size: 30),
          ),
          Positioned(
            top: -5,
            child: Icon(
              Icons.workspace_premium,
              color: Colors.amber[800],
              size: 30,
            ),
          ),
        ],
      );
    } else if (rank == 2) {
      return Stack(
        alignment: Alignment.center,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFC0C0C0), // 銀色
            radius: 25,
            child: Icon(Icons.person, color: Colors.white, size: 30),
          ),
          Positioned(
            top: -5,
            child: Icon(
              Icons.workspace_premium,
              color: Colors.grey[700],
              size: 30,
            ),
          ),
        ],
      );
    } else if (rank == 3) {
      return Stack(
        alignment: Alignment.center,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFCD7F32), // 銅色
            radius: 25,
            child: Icon(Icons.person, color: Colors.white, size: 30),
          ),
          Positioned(
            top: -5,
            child: Icon(
              Icons.workspace_premium,
              color: Colors.brown[800],
              size: 30,
            ),
          ),
        ],
      );
    }
    return CircleAvatar(
      backgroundColor: Colors.grey.shade300,
      child: Text('$rank', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
    );
  }

  // ユーザープロフィールを表示
  void _showUserProfile(String userId, String userName, String? iconUrl, String? status) async {
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
              // プロフィールヘッダー
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
                      child: iconUrl == null ? const Icon(Icons.person, size: 50) : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (status != null && status.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 20),
                    // 統計情報（投稿数と高評価数）
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: widget.firebaseService.getUserRecords(userId),
                      builder: (context, snapshot) {
                        int postCount = 0;
                        int totalLikes = 0;

                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (snapshot.hasData) {
                          final records = snapshot.data ?? [];
                          postCount = records.length;
                          // 高評価数の合計を計算
                          totalLikes = records.fold(0, (sum, record) {
                            try {
                              final data = record['data'] as Map<String, dynamic>?;
                              if (data != null) {
                                final likes = data['likes'] as int? ?? 0;
                                return sum + likes;
                              }
                            } catch (e) {
                              print('高評価数計算エラー: $e, record: $record');
                            }
                            return sum;
                          });
                          print('プロフィール統計 - 投稿数: $postCount, 高評価数: $totalLikes');
                        } else if (snapshot.hasError) {
                          print('プロフィール統計取得エラー: ${snapshot.error}');
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatItem('投稿', postCount.toString()),
                              Container(
                                width: 1,
                                height: 30,
                                color: Colors.grey[300],
                              ),
                              _buildStatItem('高評価', totalLikes.toString()),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // 投稿一覧
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: widget.firebaseService.getUserRecords(userId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('エラー: ${snapshot.error}'));
                    }
                    final records = snapshot.data ?? [];
                    if (records.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text('まだ投稿がありません'),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            '投稿 (${records.length}件)',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: records.length,
                            itemBuilder: (context, index) {
                              final record = records[index];
                              final data = record['data'] as Map<String, dynamic>;
                              final type = data['type'] as String;
                              final comment = data['comment'] as String;
                              final value = data['value'] as int;
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
                                  '${dateTime.year}/${dateTime.month}/${dateTime.day}',
                                  style: const TextStyle(fontSize: 12),
                                )
                                    : null,
                                trailing: Text(
                                  '$value${type == '徳' ? 'Pt' : '円'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: value >= 0 ? Colors.black : Colors.red,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // 閉じるボタン
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('閉じる'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
