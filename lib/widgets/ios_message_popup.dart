import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

class IosMessageAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const IosMessageAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });
}

class IosMessagePopupRoute extends PageRoute<void> {
  final Rect messageRect;
  final Widget messageBubble;
  final bool isMe;
  final List<IosMessageAction> row1Actions;
  final List<IosMessageAction> row2Actions;

  IosMessagePopupRoute({
    required this.messageRect,
    required this.messageBubble,
    required this.isMe,
    required this.row1Actions,
    required this.row2Actions,
  });

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _IosMessagePopupScreen(
      animation: animation,
      messageRect: messageRect,
      messageBubble: messageBubble,
      isMe: isMe,
      row1Actions: row1Actions,
      row2Actions: row2Actions,
    );
  }
}

class _IosMessagePopupScreen extends StatefulWidget {
  final Animation<double> animation;
  final Rect messageRect;
  final Widget messageBubble;
  final bool isMe;
  final List<IosMessageAction> row1Actions;
  final List<IosMessageAction> row2Actions;

  const _IosMessagePopupScreen({
    Key? key,
    required this.animation,
    required this.messageRect,
    required this.messageBubble,
    required this.isMe,
    required this.row1Actions,
    required this.row2Actions,
  }) : super(key: key);

  @override
  State<_IosMessagePopupScreen> createState() => _IosMessagePopupScreenState();
}

class _IosMessagePopupScreenState extends State<_IosMessagePopupScreen> {
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Estimasi tinggi menu popup: 2 baris x ~60px + divider + padding = ~155px
    const double menuHeight = 155.0;
    const double arrowSize = 10.0;

    // Tentukan posisi menu: di bawah bubble atau di atas bubble jika ruang bawah sempit
    final bool fitsBelow = widget.messageRect.bottom + menuHeight + arrowSize + 20 < screenSize.height - bottomPadding;
    final double menuTop = fitsBelow
        ? widget.messageRect.bottom + arrowSize + 4
        : widget.messageRect.top - menuHeight - arrowSize - 4;

    // Posisi horizontal menu: dipusatkan atau dibatasi margin layar
    final double menuWidth = math.min(screenSize.width - 24, 380.0);
    final double menuLeft = (screenSize.width - menuWidth) / 2;

    // Pastikan posisi horizontal bubble pesan aman tidak pernah terpotong tepi layar
    final double safeBubbleLeft = widget.messageRect.left.clamp(
      10.0,
      math.max(10.0, screenSize.width - widget.messageRect.width - 10.0),
    );

    // Hitung posisi panah (arrow) agar menunjuk ke tengah bubble pesan
    final double bubbleCenterX = safeBubbleLeft + (widget.messageRect.width / 2);
    final double arrowLeft = (bubbleCenterX - menuLeft - (arrowSize / 2))
        .clamp(20.0, menuWidth - 20.0 - arrowSize);

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Blurred and darkened backdrop
          GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
              animation: widget.animation,
              builder: (context, child) {
                final opacity = CurvedAnimation(
                  parent: widget.animation,
                  curve: Curves.easeOut,
                ).value;
                return BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 10 * opacity,
                    sigmaY: 10 * opacity,
                  ),
                  child: Container(
                    color: Colors.black.withOpacity(0.55 * opacity),
                  ),
                );
              },
            ),
          ),

          // 2. Floating message bubble (diangkat mengambang persis di atas posisi aslinya)
          Positioned(
            left: safeBubbleLeft,
            top: widget.messageRect.top,
            width: widget.messageRect.width,
            child: AnimatedBuilder(
              animation: widget.animation,
              builder: (context, child) {
                final scale = 1.0 + (0.015 * widget.animation.value);
                return Transform.scale(
                  scale: scale,
                  alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35 * widget.animation.value),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: IgnorePointer(
                      child: widget.messageBubble,
                    ),
                  ),
                );
              },
            ),
          ),

          // 3. Animated Popup Menu (animasi melebar ke kanan dan kiri)
          Positioned(
            top: menuTop.clamp(topPadding + 10, screenSize.height - bottomPadding - menuHeight - 10),
            left: menuLeft,
            width: menuWidth,
            child: AnimatedBuilder(
              animation: widget.animation,
              builder: (context, child) {
                // Animasi stretch/expand horizontal (melebar ke kiri dan kanan)
                final curvedVal = CurvedAnimation(
                  parent: widget.animation,
                  curve: Curves.easeOutBack,
                ).value;

                final scaleX = curvedVal.clamp(0.0, 1.05);
                final scaleY = CurvedAnimation(
                  parent: widget.animation,
                  curve: Curves.easeOutCubic,
                ).value.clamp(0.0, 1.0);

                final opacity = CurvedAnimation(
                  parent: widget.animation,
                  curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
                ).value;

                return Transform(
                  transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
                  alignment: fitsBelow ? Alignment.topCenter : Alignment.bottomCenter,
                  child: Opacity(
                    opacity: opacity,
                    child: child,
                  ),
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Triangle pointer (panah mengarah ke bubble)
                  Positioned(
                    top: fitsBelow ? -arrowSize + 2 : null,
                    bottom: !fitsBelow ? -arrowSize + 2 : null,
                    left: arrowLeft,
                    child: Transform.rotate(
                      angle: math.pi / 4,
                      child: Container(
                        width: arrowSize * 1.4,
                        height: arrowSize * 1.4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),

                  // Menu card container
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.45),
                          blurRadius: 24,
                          spreadRadius: 2,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Baris 1
                        _buildActionRow(widget.row1Actions),
                        if (widget.row2Actions.isNotEmpty) ...[
                          // Garis pembatas halus
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            height: 0.6,
                            color: Colors.white.withOpacity(0.14),
                          ),
                          // Baris 2
                          _buildActionRow(widget.row2Actions),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(List<IosMessageAction> actions) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: actions.map((act) {
        return Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.pop(context);
                act.onTap();
              },
              borderRadius: BorderRadius.circular(10),
              splashColor: Colors.white12,
              highlightColor: Colors.white10,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      act.icon,
                      size: 22,
                      color: act.isDestructive ? const Color(0xFFFF5252) : Colors.white,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      act.label,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: act.isDestructive ? const Color(0xFFFF5252) : Colors.white,
                        fontWeight: FontWeight.w400,
                        height: 1.15,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
