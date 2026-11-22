import 'package:home_widget_generator/home_widget_generator.dart';

/// Widgets natifs de navigation Strasse : 2×2 et 4×2 sur iOS et Android.
@HomeWidget(
  name: 'StrasseNavigationWidget',
  description: 'Guidage en cours, prochaine manœuvre et heure d’arrivée',
  iOS: HomeWidgetIOSConfiguration(
    groupId: 'group.fr.strasse.strasse',
    supportedFamilies: [
      HWWidgetFamily.systemSmall,
      HWWidgetFamily.systemMedium,
    ],
  ),
  android: HomeWidgetAndroidConfiguration(
    minWidth: 110,
    minHeight: 110,
    minResizeWidth: 110,
    minResizeHeight: 110,
    maxResizeWidth: 250,
    maxResizeHeight: 110,
    targetCellWidth: 2,
    targetCellHeight: 2,
    resizeMode: HWAndroidResizeMode.horizontal,
    widgetCategory: HWAndroidWidgetCategory.homeScreen,
    updatePeriodMillis: 1800000,
  ),
  widget: HWSizeAdaptive(
    small: HWColumn(
      children: [
        HWText.fixed(
          'STRASSE',
          style: HWRoleTextStyle(
            role: HWTextStyleRole.caption,
            fontWeight: HWFontWeight.bold,
          ),
        ),
        HWText(
          HWString('status', defaultValue: 'Aucune navigation active'),
          style: HWRoleTextStyle(role: HWTextStyleRole.callout),
        ),
        HWText(
          HWString('destination', defaultValue: 'Lancez un trajet'),
          style: HWRoleTextStyle(
            role: HWTextStyleRole.headline,
            fontWeight: HWFontWeight.bold,
          ),
        ),
        HWText(
          HWString('eta', defaultValue: '—'),
          style: HWRoleTextStyle(
            role: HWTextStyleRole.title,
            fontWeight: HWFontWeight.bold,
          ),
        ),
      ],
    ),
    medium: HWColumn(
      children: [
        HWRow(
          mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
          children: [
            HWText.fixed(
              'STRASSE',
              style: HWRoleTextStyle(
                role: HWTextStyleRole.caption,
                fontWeight: HWFontWeight.bold,
              ),
            ),
            HWText(
              HWString('status', defaultValue: 'Aucune navigation active'),
              style: HWRoleTextStyle(role: HWTextStyleRole.caption),
            ),
          ],
        ),
        HWText(
          HWString('destination', defaultValue: 'Lancez un trajet'),
          style: HWRoleTextStyle(
            role: HWTextStyleRole.headline,
            fontWeight: HWFontWeight.bold,
          ),
        ),
        HWText(
          HWString('nextTurn', defaultValue: 'Votre prochaine manœuvre apparaîtra ici'),
          style: HWRoleTextStyle(role: HWTextStyleRole.body),
        ),
        HWRow(
          mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
          children: [
            HWText(
              HWString('distanceToTurn', defaultValue: '—'),
              style: HWRoleTextStyle(role: HWTextStyleRole.callout),
            ),
            HWText(
              HWString('remainingDistance', defaultValue: '—'),
              style: HWRoleTextStyle(role: HWTextStyleRole.callout),
            ),
            HWText(
              HWString('eta', defaultValue: '—'),
              style: HWRoleTextStyle(
                role: HWTextStyleRole.title,
                fontWeight: HWFontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    ),
  ),
)
class StrasseNavigation {}
