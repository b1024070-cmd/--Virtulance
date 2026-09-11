// =============================================================
// search_page.dart
// ユーザー検索画面。
// 担当: Hayato
//
// ポイント:
//   - 入力のたびにFirestoreへ問い合わせないよう、Timerでデバウンス処理を入れている
//   - Firestoreは部分一致検索に非対応のため、前方一致クエリ+クライアント側フィルタで対応
//   - 表示名はユーザーの一意な識別子になっていないため、同名ユーザーが複数ヒットしうる
//     (既知の未解決課題。詳細はポートフォリオのProblems & Improvements参照)
// =============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

/// 検索タブ用の画面
/// Untitled-1 の SearchScreen のロジックを、下タブは main.dart に任せる形で移植したものです。
class SearchPage extends StatefulWidget {
  final FirebaseService firebaseService;
  const SearchPage({super.key, required this.firebaseService});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();

  bool _isSearching = false;
  String _searchQuery = '';

  final List<String> _searchHistory = [];

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _suggestions = []; // 予測変換用
  bool _isLoading = false;
  bool _isLoadingSuggestions = false;

  // デバウンス用のタイマー
  Timer? _debounceTimer;

  void _addToHistory(String query) {
    if (query.trim().isEmpty) return;
    setState(() {
      _searchHistory.remove(query);
      _searchHistory.insert(0, query);
    });
  }

  // 予測変換用の検索（リアルタイム）
  Future<void> _searchSuggestions(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoadingSuggestions = false;
      });
      return;
    }

    setState(() {
      _isLoadingSuggestions = true;
    });

    try {
      final results = await widget.firebaseService.searchUsers(query);
      if (mounted) {
        setState(() {
          _suggestions = results.take(5).toList(); // 最大5件まで表示
          _isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSuggestions = false;
        });
      }
    }
  }

  Future<void> _handleSearch(String query) async {
    if (query.trim().isEmpty) return;
    _addToHistory(query);
    setState(() {
      _searchQuery = query;
      _isSearching = true;
      _isLoading = true;
      _searchResults = [];
      _suggestions = []; // 予測変換を非表示
    });

    // Firebaseからユーザーを検索
    try {
      final results = await widget.firebaseService.searchUsers(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('検索エラー: $e')),
        );
      }
    }
  }

  Future<void> _resetToDefault() async {
    _debounceTimer?.cancel();
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {
      _searchController.clear();
      _isSearching = false;
      _searchResults = [];
      _suggestions = [];
      _isLoading = false;
      _isLoadingSuggestions = false;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            '履歴の削除',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text('検索履歴をすべて削除してもよろしいですか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'キャンセル',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                _deleteAllHistory();
                Navigator.pop(context);
              },
              child: const Text(
                '削除する',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _deleteAllHistory() {
    setState(() {
      _searchHistory.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
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
                child: TextField(
                  controller: _searchController,
                  onSubmitted: _handleSearch,
                  decoration: InputDecoration(
                    hintText: '検索ワードを入力',
                    prefixIcon: _isSearching
                        ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _resetToDefault,
                    )
                        : const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        if (_searchController.text.isNotEmpty) {
                          _addToHistory(_searchController.text);
                        }
                        _resetToDefault();
                      },
                    )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {});
                    // デバウンス処理: 入力の度に検索せず、入力が500ms止まってから検索を実行する。
                    // 既存のタイマーが動いていれば先にキャンセルしてから新しいタイマーを仕込むことで、
                    // 「最後の入力から500ms後」だけ検索が走るようにし、無駄な通信・処理を防いでいる。
                    _debounceTimer?.cancel();
                    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                      if (!_isSearching && value.trim().isNotEmpty) {
                        _searchSuggestions(value);
                      } else if (value.trim().isEmpty) {
                        setState(() {
                          _suggestions = [];
                        });
                      }
                    });
                  },
                ),
              ),
            ),
            // 予測変換リストを表示（検索中でない場合のみ）
            if (!_isSearching && _suggestions.isNotEmpty)
              _buildSuggestionsList(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _resetToDefault,
                child:
                _isSearching ? _buildResultsView() : _buildDefaultView(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (_searchHistory.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 0, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '検索履歴',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: _showDeleteConfirmDialog,
                  child: const Text(
                    'すべて削除',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._searchHistory.map(
                (h) => ListTile(
              leading: const Icon(Icons.history, color: Colors.grey),
              title: Text(h),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    setState(() => _searchHistory.remove(h)),
              ),
              onTap: () {
                _searchController.text = h;
                _handleSearch(h);
              },
            ),
          ),
        ],
      ],
    );
  }


  Widget _buildResultsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            '「$_searchQuery」の検索結果: ${_searchResults.length}件',
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _searchResults.isEmpty
              ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 100),
              Center(child: Text('結果が見つかりませんでした')),
            ],
          )
              : ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final user = _searchResults[index];
              final userId = user['userId'] as String;
              final userName = user['name'] as String;
              final userStatus = user['status'] as String? ?? '';
              final iconUrl = user['iconUrl'] as String?;

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: ListTile(
                  leading: iconUrl != null
                      ? CircleAvatar(
                    backgroundImage: NetworkImage(iconUrl),
                    onBackgroundImageError: (_, __) {},
                  )
                      : const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: Text(
                    userName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: userStatus.isNotEmpty
                      ? Text(userStatus)
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showUserProfile(userId, userName, iconUrl, userStatus),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // 予測変換リストを構築
  Widget _buildSuggestionsList() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoadingSuggestions)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ..._suggestions.map((user) {
              final userId = user['userId'] as String;
              final userName = user['name'] as String;
              final userStatus = user['status'] as String? ?? '';
              final iconUrl = user['iconUrl'] as String?;

              return ListTile(
                leading: iconUrl != null
                    ? CircleAvatar(
                  backgroundImage: NetworkImage(iconUrl),
                  onBackgroundImageError: (_, __) {},
                )
                    : const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                title: Text(
                  userName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: userStatus.isNotEmpty ? Text(userStatus) : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _searchController.text = userName;
                  _showUserProfile(userId, userName, iconUrl, userStatus);
                },
              );
            }).toList(),
        ],
      ),
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

                        if (snapshot.hasData) {
                          final records = snapshot.data ?? [];
                          postCount = records.length;
                          // 高評価数の合計を計算
                          totalLikes = records.fold(0, (sum, record) {
                            final data = record['data'] as Map<String, dynamic>;
                            final likes = data['likes'] as int? ?? 0;
                            return sum + likes;
                          });
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
