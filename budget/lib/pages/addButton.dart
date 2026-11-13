import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/openContainerNavigation.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';

class AddButton extends StatelessWidget {
  const AddButton({
    Key? key,
    required this.onTap,
    this.margin = EdgeInsetsDirectional.zero,
    this.padding = EdgeInsetsDirectional.zero,
    this.width = 110,
    this.height = 52,
    this.openPage,
    this.borderRadius = 15,
    this.icon,
    this.afterOpenPage,
    this.onOpenPage,
    this.labelUnder,
  }) : super(key: key);

  final VoidCallback onTap;
  final EdgeInsetsDirectional margin;
  final EdgeInsetsDirectional padding;
  final double? width;
  final double? height;
  final double borderRadius;
  final Widget? openPage;
  final IconData? icon;
  final Function? afterOpenPage;
  final Function? onOpenPage;
  final String? labelUnder;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final Color color = e.mu;
    // Placeholder alto (lista vazia) vira linha compacta: sem caixa vazia grande.
    final bool compacto = (height ?? 0) > 80;
    final Widget? rotulo = labelUnder == null
        ? null
        : TextFont(text: labelUnder!, fontSize: 14, textColor: color);
    final Widget icone = Icon(
      icon ??
          (appStateSettings["outlinedIcons"]
              ? Icons.add_outlined
              : Icons.add_rounded),
      size: 22,
      color: color,
    );
    Widget getButton(onTap) {
      return Tappable(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            border: Border.all(width: 1, color: e.line),
            borderRadius: BorderRadiusDirectional.circular(borderRadius),
          ),
          width: width,
          height: compacto ? 56 : height,
          child: compacto
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    icone,
                    if (rotulo != null) ...[
                      const SizedBox(width: 6),
                      Flexible(child: rotulo),
                    ],
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(child: icone),
                    if (rotulo != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(top: 2),
                        child: rotulo,
                      ),
                  ],
                ),
        ),
        onTap: () {
          onTap();
        },
      );
    }

    if (openPage != null) {
      return Padding(
        padding: margin,
        child: OpenContainerNavigation(
          openPage: openPage!,
          button: (openPage) {
            return getButton(openPage);
          },
          borderRadius: borderRadius,
          onClosed: () {
            if (afterOpenPage != null) afterOpenPage!();
          },
          onOpen: () {
            if (onOpenPage != null) onOpenPage!();
          },
        ),
      );
    }
    Widget button = getButton(onTap);
    return Padding(
      padding: margin,
      child: button,
    );
  }
}
