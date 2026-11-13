import 'package:auto_size_text/auto_size_text.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SlidingSelectorIncomeExpense extends StatelessWidget {
  const SlidingSelectorIncomeExpense({
    Key? key,
    required this.onSelected,
    this.alternateTheme = false,
    this.useHorizontalPaddingConstrained = true,
    this.customPadding,
    this.options,
    this.initialIndex,
  }) : super(key: key);

  final Function(int) onSelected;
  final bool alternateTheme;
  final bool useHorizontalPaddingConstrained;
  final EdgeInsetsDirectional? customPadding;
  final List<String>? options;
  final int? initialIndex;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
          horizontal: useHorizontalPaddingConstrained == false
              ? 0
              : getHorizontalPaddingConstrained(context)),
      child: Padding(
        padding: customPadding ??
            (alternateTheme
                ? const EdgeInsetsDirectional.symmetric(horizontal: 20)
                : const EdgeInsetsDirectional.symmetric(horizontal: 13)),
        child: DefaultTabController(
          length: options != null ? options!.length : 3,
          initialIndex: initialIndex ?? 0,
          child: SizedBox(
            height: alternateTheme ? 40 : 45,
            child: Material(
              borderRadius: BorderRadius.circular(14),
              color: e.surf,
              child: TabBar(
                padding: const EdgeInsets.all(4),
                splashFactory: getPlatform() == PlatformOS.isIOS
                    ? NoSplash.splashFactory
                    : null,
                splashBorderRadius: BorderRadius.circular(10),
                onTap: (value) {
                  onSelected(value + 1);
                },
                dividerColor: Colors.transparent,
                indicatorColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: indicadorSegmento(e),
                labelColor: e.tx,
                unselectedLabelColor: e.mu,
                tabs: options == null
                    ? [
                        Tab(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(top: 5.0),
                            child: AutoSizeText(
                              minFontSize: 11,
                              maxLines: 1,
                              "all".tr(),
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: appStateSettings["font"],
                                fontFamilyFallback: ['Inter'],
                              ),
                            ),
                          ),
                        ),
                        Tab(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(top: 5.0),
                            child: AutoSizeText(
                              minFontSize: 11,
                              maxLines: 1,
                              "expense".tr(),
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: appStateSettings["font"],
                                fontFamilyFallback: ['Inter'],
                              ),
                            ),
                          ),
                        ),
                        Tab(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(top: 5.0),
                            child: AutoSizeText(
                              minFontSize: 11,
                              maxLines: 1,
                              "income".tr(),
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: appStateSettings["font"],
                                fontFamilyFallback: ['Inter'],
                              ),
                            ),
                          ),
                        ),
                      ]
                    : [
                        for (String option in options!)
                          Tab(
                            child: Padding(
                              padding:
                                  const EdgeInsetsDirectional.only(top: 5.0),
                              child: AutoSizeText(
                                minFontSize: 11,
                                maxLines: 1,
                                option.tr(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFamily: appStateSettings["font"],
                                  fontFamilyFallback: ['Inter'],
                                ),
                              ),
                            ),
                          ),
                      ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
