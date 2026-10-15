import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// Taesan(DSK-05): 어드민 기기 이름을 최근접속목록·즐겨찾기·LAN 카드에도 보인다.
///
/// 권한 범위 전체 기기의 이름을 서버의 예약 주소록 guid `all` 로 한 번에 받아(id → 이름) 두고, 피어 목록을
/// 디코드할 때(`Peers._decodePeers`) alias 를 바꿔 끼운다. 로컬 피어 파일은 쓰지 않는다 — 파일 수정 시각이
/// 최근접속목록 순서를 정하기 때문이다. 오프라인에서도 마지막 이름이 보이도록 로컬 옵션에 저장하고,
/// 로그아웃·토큰 폐기(`UserModel.reset`) 때 지운다.
///
/// 브랜드·디바이스 이름도 함께 둬서 카드 부제(`taesanPeerSubtitle`)를 주소록과 같게 보인다(DSK-05, 부록 A-16).
class TaesanPeerNames {
  TaesanPeerNames._();
  static final instance = TaesanPeerNames._();
  static const _kOption = 'taesan-peer-names';

  // id → [이름, 브랜드, 디바이스]. 브랜드·디바이스는 서버가 줄 때만 있다('' = 미지정).
  Map<String, List<String>>? _peers;

  Map<String, List<String>> get _map => _peers ??= _load();

  Map<String, List<String>> _load() {
    try {
      if (bind.mainGetLocalOption(key: 'access_token').isEmpty) return {};
      final s = bind.mainGetLocalOption(key: _kOption);
      if (s.isEmpty) return {};
      // 옛 형식(id → 이름)도 읽는다 — 다음 새로고침 전까지 이름만 바꿔 끼운다.
      return (jsonDecode(s) as Map).map((k, v) => MapEntry(k as String,
          v is List ? List<String>.from(v) : <String>[v as String]));
    } catch (e) {
      debugPrint('taesan peer names load: $e');
      return {};
    }
  }

  void _save() {
    bind.mainSetLocalOption(key: _kOption, value: jsonEncode(_map));
  }

  void _reloadLists() {
    bind.mainLoadRecentPeers();
    bind.mainLoadFavPeers();
  }

  /// 어드민 이름이 있으면 카드 제목·검색에 쓰이는 alias 를, 브랜드·디바이스가 있으면 카드 부제 값을 바꿔 끼운다.
  Peer apply(Peer peer) {
    final p = _map[peer.id];
    if (p == null) return peer;
    if (p[0].isNotEmpty) {
      peer.alias = p[0];
    }
    if (p.length >= 3) {
      peer.taesanBrand = p[1];
      peer.taesanDevice = p[2];
    }
    return peer;
  }

  bool contains(String id) => _map.containsKey(id);

  /// 주소록에서 이름을 바꾼 뒤 바로 반영한다.
  void set(String id, String name) {
    final p = _map[id];
    if (p == null) {
      _map[id] = [name];
    } else {
      p[0] = name;
    }
    _save();
    _reloadLists();
  }

  /// 로그인·시작·새로고침 때(`AbModel.pullAb`) 전체 기기 이름·브랜드·디바이스를 다시 받는다. 실패하면 기존 값을 둔다.
  Future<void> refresh() async {
    if (!gFFI.userModel.isLogin) return;
    final ab =
        Ab(AbProfile('all', 'all', '', '', ShareRule.read.value, null), false);
    if (!await ab.pullAbImpl(quiet: true)) return;
    _peers = {
      for (final p in ab.peers)
        p.id: [
          p.alias,
          if (p.taesanBrand != null) ...[p.taesanBrand!, p.taesanDevice ?? ''],
        ]
    };
    _save();
    _reloadLists();
  }

  void clear() {
    _peers = {};
    bind.mainSetLocalOption(key: _kOption, value: '');
  }
}
