import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/taesan_peer_names.dart';
import 'package:get/get.dart';

/// Taesan(DSK-06): 주소록 기기 이름 편집.
///
/// 브랜드 주소록은 서버가 읽기 전용(rule 1)으로 줘서 업스트림이 태그·메모·삭제 같은 쓰기 메뉴를 스스로 숨긴다.
/// 이름 변경만 서버가 `AbProfile.info.taesan_rename` 으로 허용한다. 이름의 정본은 어드민이다.
bool taesanCanRename(BaseAb ab) {
  final info = ab.sharedProfile()?.info;
  return info is Map && info['taesan_rename'] == true;
}

/// [ab] 가 없으면 현재 주소록에서, 있으면 그 주소록(최근 세션·즐겨찾기 카드의 '전체')에서 바꾼다.
void taesanRenameAbPeer(Peer peer, {BaseAb? ab}) {
  final oldName = peer.alias;
  renameDialog(
      oldName: oldName,
      onSubmit: (String newName) async {
        if (newName == oldName) return;
        // 업스트림 _renameAction 과 달리 로컬 피어 파일(alias)은 쓰지 않는다 — 저장에 실패해도 로컬 값이 바뀌고,
        // 파일 수정 시각이 최근접속목록 순서를 바꾸기 때문이다. 실패하면 changeAlias 가 오류 토스트를 띄운다.
        final ok = ab == null
            ? await gFFI.abModel.changeAlias(id: peer.id, alias: newName)
            : await ab.changeAlias(id: peer.id, alias: newName);
        if (ok) {
          TaesanPeerNames.instance.set(peer.id, newName);
          // 다른 주소록에서 바꿨으면 주소록 탭의 현재 목록도 새 이름을 보이게 다시 받는다.
          if (ab != null) {
            gFFI.abModel.pullAb(force: ForcePullAb.current, quiet: true);
          }
        }
      });
}

MenuEntryButton<String> taesanRenameMenuEntry(Peer peer, EdgeInsets? padding) {
  return MenuEntryButton<String>(
    childBuilder: (TextStyle? style) => Text(
      translate('Rename'),
      style: style,
    ),
    proc: () => taesanRenameAbPeer(peer),
    padding: padding,
    dismissOnClicked: true,
  );
}

/// 주소록 카드의 수정 버튼(명세 Q-31 기본값: 버튼 + 다이얼로그).
Widget taesanEditButton(Peer peer, {BaseAb? ab}) {
  return _taesanCardButton(Icons.edit_outlined, translate('Rename'),
      () => taesanRenameAbPeer(peer, ab: ab));
}

/// Taesan(DSK-04): 주소록·최근 세션·즐겨찾기 카드 오른쪽 버튼 — 연결, 파일 전송, (권한이 있으면) 이름 편집,
/// 그다음 업스트림 더보기 메뉴. 그리드 카드는 이름과 한 줄을 나눠 쓰므로 버튼을 작게 둔다.
/// 최근 세션·즐겨찾기(부록 A-17)의 이름 편집은 어드민 기기만, '전체' 주소록의 권한으로 한다(DSK-06).
Widget taesanAbCardActions(
    BuildContext context, Peer peer, PeerTabIndex tab, Widget more) {
  Widget? edit;
  if (tab == PeerTabIndex.ab) {
    if (taesanCanRename(gFFI.abModel.current)) edit = taesanEditButton(peer);
  } else {
    final all = gFFI.abModel.addressbooks.values
        .where((e) => e.sharedProfile()?.guid == _kAllAbGuid)
        .firstOrNull;
    if (all != null &&
        taesanCanRename(all) &&
        TaesanPeerNames.instance.contains(peer.id)) {
      edit = taesanEditButton(peer, ab: all);
    }
  }
  return Row(mainAxisSize: MainAxisSize.min, children: [
    _taesanCardButton(Icons.screen_share_outlined, translate('Connect'),
        () => connectInPeerTab(context, peer, tab)),
    _taesanCardButton(
        Icons.folder_outlined,
        translate('Transfer file'),
        () => connectInPeerTab(context, peer, tab, isFileTransfer: true)),
    if (edit != null) edit,
    more,
  ]);
}

Widget _taesanCardButton(IconData icon, String tooltip, VoidCallback onTap) {
  return Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: TaesanSize.iconLg), // 부록 A-17: 18 → 20
      ),
    ),
  );
}

/// Taesan(DSK-05, 부록 A-16~A-18): 카드 부제 = 디바이스 · ID(A-17 에서 맨 앞 브랜드를, A-18 에서 끝의 호스트네임을 뺐다).
/// 디바이스가 없으면 '미지정'. 어드민 정보가 없는 기기(로그아웃, 권한 밖 — taesanBrand 가 null)는 null → 업스트림
/// 부제(username@hostname). 최근접속목록·즐겨찾기는 `TaesanPeerNames.apply` 가 값을 채운다.
String? taesanPeerSubtitle(Peer peer) {
  if (peer.taesanBrand == null) return null;
  final device = peer.taesanDevice;
  return [
    device == null || device.isEmpty ? translate('Unassigned') : device,
    formatID(peer.id),
  ].join(' · ');
}

/// Taesan(DSK-04): 주소록 왼쪽 패널에 선택 드롭다운·태그 대신 브랜드 목록을 둔다(`address_book.dart`).
/// const 가 아닌 것은 업스트림 패널 코드가 죽은 코드로 표시되지 않게 하려는 것이다.
final taesanAbBrandPanel = true;

const _kAllAbGuid = 'all'; // 서버의 '전체' 주소록(권한 범위 전체 기기)

/// Taesan(DSK-04, 부록 A-18): 주소록 기기 목록 위에 한 줄 — 전체·활성·비활성 수.
/// 2026-10-15(부록 A-27): 브랜드명과 '클라이언트'는 뺐다(왼쪽 목록에서 고른 브랜드가 보인다).
/// 활성은 카드 점과 같은 기준(hbbs 온라인 조회 → `Peer.online`)이고, 조회 결과가 오면 목록 모델이 알린다.
Widget taesanAbCountBar(Widget list) {
  if (!taesanAbBrandPanel) return list;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [const _TaesanAbCountBar(), Expanded(child: list)],
  );
}

class _TaesanAbCountBar extends StatelessWidget {
  const _TaesanAbCountBar();

  @override
  Widget build(BuildContext context) {
    final model = gFFI.abModel.peersModel;
    final style = TextStyle(
        fontSize: 13,
        color: Theme.of(context).textTheme.titleLarge?.color?.withOpacity(0.6));
    // 색은 카드 점(peer_card.dart getOnline)과 같다.
    Widget count(Color color, String label, int n) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 3, backgroundColor: color).marginOnly(right: 5),
            Text('${translate(label)} $n', style: style),
          ],
        ).marginOnly(left: 14);
    // 주소록을 바꾸면 목록 모델이 다시 채워지며 알린다 — 브랜드명을 읽지 않으므로 Obx 는 두지 않는다.
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final total = model.peers.length;
        final online = model.peers.where((p) => p.online).length;
        return Row(children: [
          Text('${translate('Total')} $total', style: style),
          count(Colors.green, 'Active', online),
          count(TaesanPalette.red600, 'Inactive', total - online),
        ]);
      },
    ).marginOnly(left: 2, bottom: 8);
  }
}

/// 브랜드(공유 주소록) 목록. 맨 위는 '전체', 나머지는 드롭다운과 같은 이름순. 고르면 오른쪽에 그 기기 목록이 보인다.
class TaesanAbBrandList extends StatelessWidget {
  final bool isPortrait;
  const TaesanAbBrandList({Key? key, required this.isPortrait}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final abModel = gFFI.abModel;
      final names = abModel.addressBookNames()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final allIndex = names.indexWhere((e) =>
          abModel.addressbooks[e]?.sharedProfile()?.guid == _kAllAbGuid);
      if (allIndex > 0) names.insert(0, names.removeAt(allIndex));
      final current = abModel.currentName.value;
      final list = ListView.builder(
          shrinkWrap: isPortrait,
          itemCount: names.length,
          itemBuilder: (context, index) => _buildItem(context, names[index],
              isAll: index == 0 && allIndex >= 0,
              selected: names[index] == current));
      if (isPortrait) {
        return LimitedBox(
            maxHeight: max(MediaQuery.of(context).size.height / 6, 100.0),
            child: list);
      }
      return list.marginOnly(top: 8);
    });
  }

  Widget _buildItem(BuildContext context, String name,
      {required bool isAll, required bool selected}) {
    // 부록 A-18: 선택은 어드민 주소록 화면과 같게 검정 바탕·흰 글자(다크는 밝은 회색·검정 글자), 둥근 모서리, 구분선 없음.
    final taesan = TaesanColors.of(context);
    final radius = BorderRadius.circular(TaesanSize.radius);
    final fg = selected ? taesan.primaryFg : null;
    return InkWell(
      borderRadius: radius,
      onTap: () async {
        // 업스트림은 이미 받은 주소록을 다시 받지 않는다. 다른 주소록에서 바꾼 이름이 늦게 보이지 않게 다시 받는다.
        final pulled = gFFI.abModel.addressbooks[name]?.initialized == true;
        await gFFI.abModel.setCurrentName(name);
        if (pulled) {
          gFFI.abModel.pullAb(force: ForcePullAb.current, quiet: true);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: selected ? taesan.primaryBg : null,
          borderRadius: radius,
        ),
        child: Row(
          children: [
            // 부록 A-27: 브랜드 줄의 가게 모양 아이콘은 뺐다('전체'의 격자 아이콘만 둔다).
            if (isAll)
              Icon(Icons.apps_rounded, color: fg ?? MyTheme.accent, size: 19)
                  .marginOnly(right: 6),
            Expanded(
                child: Text(gFFI.abModel.translatedName(name),
                    style: TextStyle(color: fg),
                    overflow: TextOverflow.ellipsis)),
          ],
        ).paddingSymmetric(horizontal: 10, vertical: 8),
      ),
    ).marginSymmetric(horizontal: 8).marginOnly(bottom: 2);
  }
}
