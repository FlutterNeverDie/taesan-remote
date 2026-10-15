// Taesan(DSK-07): 데스크탑에서 Android 기기를 제어할 때 뜨는 모바일 제어 막대(부록 A-10).
//
// - 업스트림 막대(common/widgets/overlay.dart `DraggableMobileActions`)는 원격 화면 배율 × 2 로
//   커져(100% 보기면 400×90) 화면을 크게 가리고, 반투명 파랑에 이름이 없었다.
// - 이 막대는 배율과 상관없는 고정 크기다. 툴바와 같은 어두운 톤에 Lucide 아이콘 + 이름을 둔다.
// - 끌기·위치 저장·창 안 맞춤은 업스트림 `Draggable`·`draggablePositions.mobileActions` 를 그대로 쓴다.
// - 모바일 앱(제어측이 휴대폰)은 업스트림 막대를 그대로 쓴다(common.dart `makeMobileActionsOverlayEntry`).
import 'package:flutter/material.dart' hide Draggable;
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/overlay.dart';

const double kTaesanMobileActionsWidth = 212;
const double kTaesanMobileActionsHeight = 52;

class TaesanMobileActionsBar extends StatelessWidget {
  const TaesanMobileActionsBar({
    Key? key,
    required this.position,
    this.onBackPressed,
    this.onHomePressed,
    this.onRecentPressed,
    this.onHidePressed,
  }) : super(key: key);

  final DraggableKeyPosition position;
  final VoidCallback? onBackPressed;
  final VoidCallback? onHomePressed;
  final VoidCallback? onRecentPressed;
  final VoidCallback? onHidePressed;

  @override
  Widget build(BuildContext context) {
    return Draggable(
      position: position,
      width: kTaesanMobileActionsWidth,
      height: kTaesanMobileActionsHeight,
      builder: (_, onPanUpdate) => GestureDetector(
        onPanUpdate: onPanUpdate,
        child: Container(
          decoration: BoxDecoration(
            color: TaesanPalette.neutral800.withOpacity(0.92),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.move,
                child: SizedBox(
                  width: 18,
                  height: kTaesanMobileActionsHeight,
                  child: Icon(taesanIcon(Icons.drag_indicator),
                      size: TaesanSize.iconSm, color: Colors.white54),
                ),
              ),
              _button(Icons.arrow_back, 'Back', onBackPressed),
              _button(Icons.home, 'Home', onHomePressed),
              _button(Icons.crop_square, 'Recent apps', onRecentPressed),
              Container(
                width: 1,
                height: 28,
                color: Colors.white24,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),
              Tooltip(
                message: translate('Hide'),
                child: _hover(
                  onHidePressed,
                  SizedBox(
                    width: 32,
                    height: 44,
                    child: Icon(taesanIcon(Icons.keyboard_arrow_down_rounded),
                        size: TaesanSize.iconLg, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(IconData icon, String label, VoidCallback? onPressed) {
    return _hover(
      onPressed,
      SizedBox(
        width: 48,
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(taesanIcon(icon), size: TaesanSize.icon, color: Colors.white),
            const SizedBox(height: 2),
            Text(
              translate(label),
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                  fontSize: 10, height: 1.2, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hover(VoidCallback? onPressed, Widget child) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.white.withOpacity(0.1),
        splashColor: Colors.transparent,
        highlightColor: Colors.white.withOpacity(0.14),
        child: child,
      ),
    );
  }
}
