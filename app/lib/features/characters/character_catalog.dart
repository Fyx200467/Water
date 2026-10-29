import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/character_sync.dart';
import 'character_data.dart';

/// 角色素材目录 + 后台管理预留接口（PRD §3 后台管理 / M5 数据同步）
///
/// 分层设计：
/// - [CharacterAsset]：素材领域模型（内置/上传统一）
/// - [CharacterAdminRepository]：后台管理 API 契约 —— 上传、上架/下架、列表。
///   M5 接入 NestJS 后台时，用 HTTP 实现（dio）替换 [LocalCharacterAdminRepository]
///   即可，UI 与 provider 层无需改动。
/// - [characterCatalogProvider]：合并内置分类 + 上传素材 + 上下架状态，
///   输出「当前可见」的分类列表，供角色选择页渲染。
///
/// 后台管理端（React Admin，admin/ 目录）对应的 REST 约定：
/// - GET    /admin/character-assets?categoryId=  → listAssets
/// - POST   /admin/character-assets              → uploadAsset（multipart: svg 文件 + 元数据）
/// - PATCH  /admin/character-assets/:id/enabled  → setEnabled（上架/下架）
/// - DELETE /admin/character-assets/:id          → removeAsset
class CharacterAsset {
  const CharacterAsset({
    required this.id,
    required this.displayName,
    required this.categoryId,
    required this.enabled,
    required this.source,
    this.svgFilePath,
    this.createdAt,
  });

  /// 素材唯一 ID（同时是 SVG 文件名：{id}.svg）
  final String id;
  final String displayName;
  final String categoryId;

  /// 上架状态：false = 已下架（客户端不展示）
  final bool enabled;

  /// 来源：builtin = 内置资产；uploaded = 后台上传
  final CharacterAssetSource source;

  /// 上传素材的本地 SVG 文件路径（内置素材为 null，走 assets）
  final String? svgFilePath;

  final DateTime? createdAt;

  CharacterAsset copyWith({bool? enabled}) => CharacterAsset(
        id: id,
        displayName: displayName,
        categoryId: categoryId,
        enabled: enabled ?? this.enabled,
        source: source,
        svgFilePath: svgFilePath,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'categoryId': categoryId,
        'enabled': enabled,
        'source': source.name,
        'svgFilePath': svgFilePath,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory CharacterAsset.fromJson(Map<String, dynamic> json) => CharacterAsset(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        categoryId: json['categoryId'] as String,
        enabled: json['enabled'] as bool? ?? true,
        source: CharacterAssetSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => CharacterAssetSource.uploaded,
        ),
        svgFilePath: json['svgFilePath'] as String?,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.parse(json['createdAt'] as String),
      );
}

enum CharacterAssetSource { builtin, uploaded }

/// 后台管理仓库接口（M5 用 HTTP 实现替换本抽象的本地实现）
abstract class CharacterAdminRepository {
  /// 全部素材（含下架），后台素材管理列表用
  Future<List<CharacterAsset>> listAssets();

  /// 上传角色素材：SVG 文件落盘 + 元数据注册，默认上架
  Future<CharacterAsset> uploadAsset({
    required String id,
    required String displayName,
    required String categoryId,
    required String svgFilePath,
  });

  /// 上架/下架（对内置与上传素材均生效）
  Future<void> setEnabled(String id, bool enabled);

  /// 删除上传素材（内置素材不可删除，仅可下架）
  Future<void> removeAsset(String id);
}

const _kDisabledKey = 'character_disabled_ids';
const _kUploadedKey = 'character_uploaded_assets';
const _kUploadDirName = 'character_uploads';

/// 本地默认实现：
/// - 下架状态 → SharedPreferences `character_disabled_ids`（JSON 数组）
/// - 上传素材 → 文档目录 `character_uploads/{id}.svg` + 元数据 JSON
///   存 SharedPreferences `character_uploaded_assets`
class LocalCharacterAdminRepository implements CharacterAdminRepository {
  LocalCharacterAdminRepository(this.ref);

  final Ref ref;

  Future<_LocalStore> _load() async {
    final storage = await ref.read(localStorageProvider.future);
    final prefs = storage.prefs;
    final disabledList =
        (jsonDecode(prefs.getString(_kDisabledKey) ?? '[]') as List? ?? [])
            .cast<String>();
    final uploadedList =
        (jsonDecode(prefs.getString(_kUploadedKey) ?? '[]') as List? ?? [])
            .map((e) => CharacterAsset.fromJson(e as Map<String, dynamic>))
            .toList();
    return _LocalStore(prefs, disabledList.toSet(), uploadedList);
  }

  @override
  Future<List<CharacterAsset>> listAssets() async {
    final store = await _load();
    return [
      // 内置素材：全分类全角色，enabled 由下架集合决定
      for (final cat in characterCategories)
        for (final id in cat.characterIds)
          CharacterAsset(
            id: id,
            displayName: characters[id]?.displayName ?? id,
            categoryId: cat.id,
            enabled: !store.disabled.contains(id),
            source: CharacterAssetSource.builtin,
          ),
      ...store.uploaded,
    ];
  }

  @override
  Future<CharacterAsset> uploadAsset({
    required String id,
    required String displayName,
    required String categoryId,
    required String svgFilePath,
  }) async {
    final store = await _load();
    final docs = await getApplicationDocumentsDirectory();
    final uploadDir = Directory('${docs.path}/$_kUploadDirName');
    if (!uploadDir.existsSync()) uploadDir.createSync(recursive: true);
    final destPath = '${uploadDir.path}/$id.svg';
    File(svgFilePath).copySync(destPath);

    final asset = CharacterAsset(
      id: id,
      displayName: displayName,
      categoryId: categoryId,
      enabled: true,
      source: CharacterAssetSource.uploaded,
      svgFilePath: destPath,
      createdAt: DateTime.now(),
    );
    store.uploaded
      ..removeWhere((a) => a.id == id)
      ..add(asset);
    await store.persist();
    return asset;
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    final store = await _load();
    if (enabled) {
      store.disabled.remove(id);
    } else {
      store.disabled.add(id);
    }
    for (var i = 0; i < store.uploaded.length; i++) {
      if (store.uploaded[i].id == id) {
        store.uploaded[i] = store.uploaded[i].copyWith(enabled: enabled);
      }
    }
    await store.persist();
  }

  @override
  Future<void> removeAsset(String id) async {
    final store = await _load();
    CharacterAsset? asset;
    for (final a in store.uploaded) {
      if (a.id == id) {
        asset = a;
        break;
      }
    }
    if (asset == null) {
      throw StateError('内置素材不可删除，仅可下架：$id');
    }
    final f = File(asset.svgFilePath!);
    if (f.existsSync()) f.deleteSync();
    store.uploaded.removeWhere((a) => a.id == id);
    store.disabled.remove(id);
    await store.persist();
  }
}

class _LocalStore {
  _LocalStore(this.prefs, this.disabled, this.uploaded);

  final SharedPreferences prefs;
  final Set<String> disabled;
  final List<CharacterAsset> uploaded;

  Future<void> persist() async {
    await prefs.setString(_kDisabledKey, jsonEncode(disabled.toList()));
    await prefs.setString(
        _kUploadedKey, jsonEncode([for (final a in uploaded) a.toJson()]));
  }
}

/// 角色目录状态：过滤下架 + 合并上传素材后的可见分类
class CharacterCatalogState {
  const CharacterCatalogState({
    required this.categories,
    required this.uploadedFilePaths,
    required this.displayNames,
    this.memberOnlyIds = const {},
  });

  /// 当前可见分类（每个分类的 characterIds 已过滤下架、追加可见的上传素材）
  final List<CharacterCategory> categories;

  /// 上传/下载素材 id → 本地 SVG 文件路径（渲染用 SvgPicture.file）
  final Map<String, String> uploadedFilePaths;

  /// 角色 id → 显示名称（含后台新增/改名的角色）
  final Map<String, String> displayNames;

  /// 后台标记为「会员专属」的单个角色 id（分类整组会员由 category.memberOnly 表达）
  final Set<String> memberOnlyIds;

  /// 全部可见角色 id
  Set<String> get allIds => {
        for (final c in categories) ...c.characterIds,
      };

  /// 全部可见角色总数
  int get totalCount =>
      categories.fold(0, (sum, c) => sum + c.characterIds.length);

  /// 角色是否属于会员专属（单角色标记或整组会员）
  bool isMemberOnly(String id) {
    if (memberOnlyIds.contains(id)) return true;
    for (final c in categories) {
      if (c.memberOnly && c.characterIds.contains(id)) return true;
    }
    return false;
  }
}

/// 分类色：内置分类沿用客户端配色，后台新增分类按 code 稳定取色
const _builtinCategoryColors = <String, Color>{
  'daily': Color(0xFF5AC8FA),
  'cute': Color(0xFF5AC8FA),
  'people': Color(0xFFE0528C),
  'home': Color(0xFF34C759),
  'fruits': Color(0xFFFF9500),
  'plants': Color(0xFF34C759),
};

const _fallbackCategoryColors = <Color>[
  Color(0xFF5AC8FA),
  Color(0xFFE0528C),
  Color(0xFF34C759),
  Color(0xFFFF9500),
  Color(0xFFAF52DE),
  Color(0xFF5856D6),
];

Color _categoryColor(String code) {
  final builtin = _builtinCategoryColors[code];
  if (builtin != null) return builtin;
  var sum = 0;
  for (final c in code.codeUnits) {
    sum += c;
  }
  return _fallbackCategoryColors[sum % _fallbackCategoryColors.length];
}

/// 角色目录 provider：监听 admin 仓库，输出可见分类
final characterCatalogProvider = StateNotifierProvider<
    CharacterCatalogNotifier, AsyncValue<CharacterCatalogState>>((ref) {
  return CharacterCatalogNotifier(ref);
});

class CharacterCatalogNotifier
    extends StateNotifier<AsyncValue<CharacterCatalogState>> {
  CharacterCatalogNotifier(this.ref) : super(const AsyncValue.loading()) {
    _reload();
  }

  final Ref ref;

  Future<void> _reload() async {
    try {
      final repo = ref.read(characterAdminRepositoryProvider);
      final localAssets = await repo.listAssets();
      final localUploaded = localAssets
          .where((a) => a.source == CharacterAssetSource.uploaded)
          .toList();

      final names = <String, String>{
        for (final e in characters.entries) e.key: e.value.displayName,
      };
      final paths = <String, String>{
        for (final a in localUploaded)
          if (a.svgFilePath != null) a.id: a.svgFilePath!,
      };

      final serverItems = CharacterStore.items;
      final useServer = CharacterStore.hasRemoteList && serverItems.isNotEmpty;

      String text(Map<String, dynamic> m, String key) =>
          (m[key] ?? '').toString();
      bool flag(Map<String, dynamic> m, String key) {
        final v = m[key];
        return v == true || v == 1 || v == '1' || v == 'true';
      }

      String idOf(Map<String, dynamic> m) {
        final id = text(m, 'id');
        return id.isEmpty ? text(m, 'code') : id;
      }

      final visibleCategories = <CharacterCategory>[];
      // 后台按角色单独标记的会员专属（整组权益看分类上的 memberOnly）
      final memberOnlyIds = <String>{};

      if (useServer) {
        // 服务端列表为准：分类、名称、排序、素材全部来自后台
        for (final item in serverItems) {
          final id = idOf(item);
          if (id.isEmpty) continue;
          final name = text(item, 'name');
          if (name.isNotEmpty) names[id] = name;
          if (flag(item, 'memberOnly')) memberOnlyIds.add(id);
          final cached = CharacterStore.filePathSync(id);
          if (cached != null) paths[id] = cached;
        }

        for (final raw in CharacterStore.categories) {
          final code = text(raw, 'code');
          if (code.isEmpty) continue;
          final ids = <String>[
            for (final item in serverItems)
              if ((text(item, 'categoryCode').isEmpty
                      ? 'daily'
                      : text(item, 'categoryCode')) ==
                  code)
                // 每日随机池：后台标记 inDailyPool=false 的角色不进「每日」分类
                if (code != 'daily' || item['inDailyPool'] != false) idOf(item),
          ].where((id) => id.isNotEmpty).toList();
          // 本地后台上传的素材仍可追加进同名分类
          for (final a in localUploaded) {
            if (a.categoryId == code && a.enabled && !ids.contains(a.id)) {
              ids.add(a.id);
            }
          }
          if (ids.isEmpty) continue;

          final name = text(raw, 'name');
          visibleCategories.add(CharacterCategory(
            id: code,
            name: name.isEmpty ? code : name,
            color: _categoryColor(code),
            characterIds: ids,
            memberOnly: flag(raw, 'memberOnly'),
          ));
        }
      } else {
        // 内置分类：不在下架集合即可见，再追加本地上传素材
        final enabledById = {for (final a in localAssets) a.id: a};
        for (final cat in characterCategories) {
          final ids = <String>[];
          for (final id in cat.characterIds) {
            final asset = enabledById[id];
            if (asset == null || asset.enabled) ids.add(id);
          }
          for (final a in localUploaded) {
            if (a.categoryId == cat.id && a.enabled) ids.add(a.id);
          }
          visibleCategories.add(CharacterCategory(
            id: cat.id,
            name: cat.name,
            color: cat.color,
            subtitle: cat.subtitle,
            characterIds: ids,
            memberOnly: cat.memberOnly,
          ));
        }
      }

      state = AsyncValue.data(CharacterCatalogState(
        categories: visibleCategories,
        uploadedFilePaths: paths,
        displayNames: names,
        memberOnlyIds: memberOnlyIds,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 后台管理操作入口：上下架后刷新目录
  Future<void> setEnabled(String id, bool enabled) async {
    await ref.read(characterAdminRepositoryProvider).setEnabled(id, enabled);
    await _reload();
  }

  /// 后台管理操作入口：上传后刷新目录
  Future<void> upload({
    required String id,
    required String displayName,
    required String categoryId,
    required String svgFilePath,
  }) async {
    await ref.read(characterAdminRepositoryProvider).uploadAsset(
          id: id,
          displayName: displayName,
          categoryId: categoryId,
          svgFilePath: svgFilePath,
        );
    await _reload();
  }

  Future<void> remove(String id) async {
    await ref.read(characterAdminRepositoryProvider).removeAsset(id);
    await _reload();
  }
}

final characterAdminRepositoryProvider =
    Provider<CharacterAdminRepository>((ref) {
  return LocalCharacterAdminRepository(ref);
});
