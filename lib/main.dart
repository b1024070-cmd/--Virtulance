// =============================================================
// main.dart
// アプリのエントリーポイントと画面全体の土台(RootShell)。
// 担当: すけすけ
//
// 役割:
//   - Firebase(匿名認証)の初期化
//   - 全記録(RecordItem)を一括管理し、5つの画面(タブ)に配布する
//   - 記録は常にローカル(SharedPreferences)へ保存し、
//     isPublic=trueの記録だけ追加でFirestoreにも保存する
//     (ローカル優先 + 選択的クラウド同期の起点となっている)
// =============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:convert';
import 'my_page_screen.dart';
import 'search_page.dart';
import 'record_page.dart';
import 'global_page.dart';
import 'settings_page.dart';
import 'firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

/// 「徳」または「収支」の1件の記録を表すデータモデル。
/// ローカル保存用にJSONへの変換(toJson/fromJson)を持つ。
class RecordItem {
  String type;
  String comment;
  int value;
  DateTime date;
  bool isPublic; // 世界に公開するかどうかのフラグ
  int likes = 0;    // 追加
  int dislikes = 0; // 追加

  RecordItem({
    required this.type,
    required this.comment,
    required this.value,
    required this.date,
    this.isPublic = false, // デフォルトは非公開
    this.likes = 0,
    this.dislikes = 0,
  });

  // JSONに変換
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'comment': comment,
      'value': value,
      'date': date.toIso8601String(),
      'isPublic': isPublic,
      'likes': likes,
      'dislikes': dislikes,
    };
  }

  // JSONから復元
  factory RecordItem.fromJson(Map<String, dynamic> json) {
    return RecordItem(
      type: json['type'] as String,
      comment: json['comment'] as String,
      value: json['value'] as int,
      date: DateTime.parse(json['date'] as String),
      isPublic: json['isPublic'] as bool? ?? false, // 後方互換性のためデフォルト値
      likes: json['likes'] as int? ?? 0,
      dislikes: json['dislikes'] as int? ?? 0,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '記録',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FED)),
        useMaterial3: true,
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

/// アプリ全体の土台となるウィジェット。
/// ボトムナビゲーションで5画面(グラフ/検索/記録/グローバル/マイページ)を
/// IndexedStackで切り替える。全記録(_allRecords)をここで一括管理し、
/// 各画面には必要なデータとコールバックだけを渡す(単方向のデータフロー)。
class _RootShellState extends State<RootShell> {
  int _index = 0; // アプリ起動時に一番左のタブ（ホーム）を表示

  // --- 1. ここでデータを一括管理 ---
  List<RecordItem> _allRecords = [];
  bool _isLoading = true;
  final FirebaseService _firebaseService = FirebaseService();

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _loadRecords();
  }

  // Firebaseの初期化と匿名認証
  Future<void> _initializeFirebase() async {
    try {
      await _firebaseService.signInAnonymously();
      final userId = _firebaseService.currentUser?.uid;
      if (userId != null) {
        // 既存のユーザー情報をFirestoreに保存
        final prefs = await SharedPreferences.getInstance();
        final name = prefs.getString('user_name') ?? '匿名ユーザー';
        final email = prefs.getString('user_email') ?? '';
        final status = prefs.getString('user_status');
        final iconPath = prefs.getString('user_icon_path');

        if (name.isNotEmpty) {
          await _firebaseService.saveUserProfile(
            userId: userId,
            name: name,
            email: email,
            status: status,
            iconPath: iconPath,
          );
        }
      }
    } catch (e) {
      print('Firebase認証エラー: $e');
    }
  }

  // データを読み込む
  Future<void> _loadRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recordsJson = prefs.getString('all_records');

      if (recordsJson != null) {
        final List<dynamic> recordsList = json.decode(recordsJson);
        setState(() {
          _allRecords = recordsList
              .map((json) => RecordItem.fromJson(json as Map<String, dynamic>))
              .toList();
          // 日付の新しい順に並び替え
          _allRecords.sort((a, b) => b.date.compareTo(a.date));
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // データを保存する
  Future<void> _saveRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recordsJson = json.encode(
        _allRecords.map((record) => record.toJson()).toList(),
      );
      await prefs.setString('all_records', recordsJson);
    } catch (e) {
      // エラー処理（必要に応じて）
    }
  }

  // --- 2. データを追加するための関数 ---
  // ポイント: ローカル保存は常に行い、Firestoreへの保存はisPublicの時だけ行う。
  // これにより「非公開の記録は端末内だけに残る」という仕様を実現している。
  void _addNewRecord(RecordItem item) async {
    setState(() {
      _allRecords.add(item);
      // 日付の新しい順に並び替え
      _allRecords.sort((a, b) => b.date.compareTo(a.date));
    });
    _saveRecords();

    // Firestoreにも保存（公開設定の場合）
    if (item.isPublic) {
      final userId = _firebaseService.currentUser?.uid;
      if (userId != null) {
        try {
          await _firebaseService.saveRecord(item, userId);
          print('Firestoreに記録を保存しました: ${item.comment}');
        } catch (e) {
          print('Firestore保存エラー: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('投稿の保存に失敗しました: $e')),
            );
          }
        }
      } else {
        print('ユーザーIDが取得できませんでした');
      }
    }
  }

  // データを更新する（編集時）
  void _updateRecord(RecordItem updatedItem) {
    setState(() {
      // 日時とタイプで一致するアイテムを見つけて更新
      final index = _allRecords.indexWhere((r) =>
      r.date == updatedItem.date &&
          r.type == updatedItem.type &&
          r.comment == updatedItem.comment);
      if (index != -1) {
        // 元のアイテムを削除して新しいアイテムを追加
        _allRecords.removeAt(index);
        _allRecords.add(updatedItem);
        _allRecords.sort((a, b) => b.date.compareTo(a.date));
      }
    });
    _saveRecords();
  }

  // データを削除する
  void _deleteRecord(RecordItem item) {
    setState(() {
      _allRecords.remove(item);
    });
    _saveRecords();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // UIを変えず、データだけを渡すように配線を変更
    final pages = <Widget>[
      MyPageScreen(records: _allRecords), // 引数を追加
      SearchPage(firebaseService: _firebaseService),
      RecordPage(
        records: _allRecords,
        onSave: _addNewRecord,
        onUpdate: _updateRecord,
        onDelete: _deleteRecord,
      ), // 引数を追加
      GlobalPage(
        records: _allRecords,
        onUpdate: _updateRecord,
        firebaseService: _firebaseService,
      ), // records、onUpdate、firebaseServiceを追加
      SettingsScreen(
        firebaseService: _firebaseService,
        records: _allRecords,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: '検索'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), label: '記録'),
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'グローバル'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'マイページ'),
        ],
      ),
    );
  }
}