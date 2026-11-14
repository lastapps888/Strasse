// Génère les PNG d'icônes Strasse (Android, iOS, splash) à partir des SVG de assets/logo.
// Usage : node tool/render_icons.js   (nécessite le paquet « playwright » et Chromium)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const logo = (n) => fs.readFileSync(path.join(root, 'assets/logo', n), 'utf8');

const ANDROID = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

// Tailles iOS (points × échelle), idiom, nom de fichier.
const IOS = [
  [20, 2, 'iphone'], [20, 3, 'iphone'], [29, 2, 'iphone'], [29, 3, 'iphone'],
  [40, 2, 'iphone'], [40, 3, 'iphone'], [60, 2, 'iphone'], [60, 3, 'iphone'],
  [20, 1, 'ipad'], [20, 2, 'ipad'], [29, 1, 'ipad'], [29, 2, 'ipad'],
  [40, 1, 'ipad'], [40, 2, 'ipad'], [76, 1, 'ipad'], [76, 2, 'ipad'],
  [83.5, 2, 'ipad'], [1024, 1, 'ios-marketing'],
];

function fmt(n) { return Number.isInteger(n) ? String(n) : String(n); }

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();

  async function render(svg, size, out, { transparent = false } = {}) {
    const s = svg.replace(/width="1024" height="1024"/, `width="${size}" height="${size}"`);
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(
      `<body style="margin:0;background:transparent">${s}</body>`,
    );
    fs.mkdirSync(path.dirname(out), { recursive: true });
    await page.screenshot({ path: out, omitBackground: transparent });
  }

  // --- Android : icônes classiques (carré arrondi) + rondes + adaptatives ---
  const res = path.join(root, 'android/app/src/main/res');
  for (const [dpi, k] of Object.entries(ANDROID)) {
    const legacy = Math.round(48 * k);
    await render(logo('strasse_logo.svg'), legacy, path.join(res, `mipmap-${dpi}/ic_launcher.png`), { transparent: true });
    await render(logo('strasse_logo.svg'), legacy, path.join(res, `mipmap-${dpi}/ic_launcher_round.png`), { transparent: true });
    const adaptive = Math.round(108 * k);
    await render(logo('strasse_adaptive_foreground.svg'), adaptive, path.join(res, `drawable-${dpi}/ic_launcher_foreground.png`), { transparent: true });
    await render(logo('strasse_adaptive_background.svg'), adaptive, path.join(res, `drawable-${dpi}/ic_launcher_background.png`));
    await render(logo('strasse_monochrome.svg'), adaptive, path.join(res, `drawable-${dpi}/ic_launcher_monochrome.png`), { transparent: true });
  }
  await render(logo('strasse_logo.svg'), 512, path.join(root, 'assets/logo/png/play_store_512.png'), { transparent: true });

  // --- iOS : icônes sans transparence, plein cadre (iOS applique le masque) ---
  const set = path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
  const images = [];
  for (const [pt, scale, idiom] of IOS) {
    const px = Math.round(pt * scale);
    const name = `Icon-App-${fmt(pt)}x${fmt(pt)}@${scale}x.png`;
    await render(logo('strasse_icon_full_bleed.svg'), px, path.join(set, name));
    images.push({ size: `${fmt(pt)}x${fmt(pt)}`, idiom, filename: name, scale: `${scale}x` });
  }
  fs.writeFileSync(
    path.join(set, 'Contents.json'),
    JSON.stringify({ images, info: { version: 1, author: 'xcode' } }, null, 2),
  );

  // --- Assets Flutter (PNG haute résolution + écran de démarrage) ---
  const png = path.join(root, 'assets/logo/png');
  await render(logo('strasse_logo.svg'), 1024, path.join(png, 'strasse_logo_1024.png'), { transparent: true });
  await render(logo('strasse_logo_dark.svg'), 1024, path.join(png, 'strasse_logo_dark_1024.png'), { transparent: true });
  await render(logo('strasse_splash.svg'), 512, path.join(png, 'strasse_splash.png'), { transparent: true });
  await render(logo('strasse_splash_dark.svg'), 512, path.join(png, 'strasse_splash_dark.png'), { transparent: true });

  // Écran de démarrage iOS (LaunchImage utilisé par LaunchScreen.storyboard).
  const launch = path.join(root, 'ios/Runner/Assets.xcassets/LaunchImage.imageset');
  for (const [s, name] of [[1, 'LaunchImage.png'], [2, 'LaunchImage@2x.png'], [3, 'LaunchImage@3x.png']]) {
    await render(logo('strasse_splash.svg'), 128 * s, path.join(launch, name), { transparent: true });
  }
  fs.writeFileSync(
    path.join(launch, 'Contents.json'),
    JSON.stringify({
      images: [
        { idiom: 'universal', filename: 'LaunchImage.png', scale: '1x' },
        { idiom: 'universal', filename: 'LaunchImage@2x.png', scale: '2x' },
        { idiom: 'universal', filename: 'LaunchImage@3x.png', scale: '3x' },
      ],
      info: { version: 1, author: 'xcode' },
    }, null, 2),
  );

  await browser.close();
  console.log('icônes générées');
})();
