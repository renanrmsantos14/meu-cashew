import 'package:budget/functions.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class HomePageWelcomeBannerSmall extends StatelessWidget {
  const HomePageWelcomeBannerSmall(
      {required this.showUsername,
      required this.showGreeting,
      required this.username,
      super.key});
  final bool showUsername;
  final bool showGreeting;
  final String username;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 17, end: 5),
      child: PartyHat(
        child: TextFont(
          text: !showUsername
              ? "home".tr()
              : showGreeting
                  ? getWelcomeMessage()
                  : username,
          fontWeight: FontWeight.w600,
          fontSize: 24,
          textColor: Theme.of(context).colorScheme.onSurface,
          //textColor: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class PartyHat extends StatelessWidget {
  const PartyHat(
      {required this.child, this.enabled = true, this.size = 25, super.key});
  final Widget child;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (enabled == false) return child;
    String? hatIcon;
    if (DateTime.now().month == 12 && DateTime.now().day == 31) {
      hatIcon = "party-hat.png";
    } else if (DateTime.now().month == 1 && DateTime.now().day == 1) {
      hatIcon = "party-hat.png";
    } else if (DateTime.now().month == 12 && DateTime.now().day >= 15) {
      hatIcon = "santa-hat.png";
    }
    if (hatIcon == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          start: -7,
          top: -16.6,
          child: Transform.rotate(
            angle: -0.24,
            child: Image.asset(
              "assets/icons/fun/" + hatIcon,
              width: size,
            ),
          ),
        ),
      ],
    );
  }
}
