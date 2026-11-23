import 'package:home_widget_generator/home_widget_generator.dart';

/// Widgets natifs de navigation Strasse : 2×2 et 4×2 sur iOS et Android.
@HomeWidget(
  name: 'StrasseNavigationWidget',
  description: 'Recherche rapide et aperçu de la carte, avec informations de navigation',
  widgetUrl: 'strasse://widget/search',
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
          'RECHERCHE RAPIDE',
          style: HWRoleTextStyle(
            role: HWTextStyleRole.caption,
            fontWeight: HWFontWeight.bold,
          ),
        ),
        HWText(
          HWString('destination', defaultValue: 'Où souhaitez-vous aller ?'),
          style: HWRoleTextStyle(
            role: HWTextStyleRole.headline,
            fontWeight: HWFontWeight.bold,
          ),
        ),
        HWText.fixed(
          'Touchez pour rechercher dans Strasse',
          style: HWRoleTextStyle(role: HWTextStyleRole.caption),
        ),
        HWText(
          HWString('status', defaultValue: 'Aucune navigation active'),
          style: HWRoleTextStyle(role: HWTextStyleRole.caption),
        ),
      ],
    ),
    medium: HWRow(
      children: [
        HWDataExists(
          data: HWImageData('mapPreview'),
          whenPresent: HWImage(
            HWImageData('mapPreview'),
            width: 112,
            height: 88,
            fit: HWImageFit.cover,
            semanticLabel: 'Aperçu de la carte Strasse',
          ),
          whenAbsent: HWColoredBox(
            color: HWColor.fixed(0xFFE7EFEA),
            child: HWText.fixed(
              'Ouvrez Strasse pour charger la carte',
              style: HWRoleTextStyle(role: HWTextStyleRole.caption),
            ),
          ),
        ),
        HWColumn(
          children: [
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
            HWText(
              HWString('mapAttribution', defaultValue: '© OpenStreetMap contributors'),
              style: HWRoleTextStyle(role: HWTextStyleRole.caption),
            ),
          ],
        ),
      ],
    ),
  ),
)
class StrasseNavigation {}


class StrasseNavigation {}
