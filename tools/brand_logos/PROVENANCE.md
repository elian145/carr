# Brand logo provenance

Every file in `source/` is an unmodified original. `build_brand_logos.py` only
crops, removes a flat matte, scales and pads these originals; it never redraws,
recolours or invents artwork. Output goes to `kk/static/images/brands/<slug>.png`
and `assets/brand_logos/<slug>.png` (byte-identical copies).

All logos are trademarks of their respective owners. None of the sources below
publishes an explicit reuse licence; they are used here only to identify the
brand in a vehicle-listing picker (nominative use), as the existing logos in
`kk/static/images/brands/` already are. Confirm this is acceptable before release.

Verified 2026-10-23.

| Slug | Source file | Origin / evidence | Processing |
|---|---|---|---|
| karry | `karry.png` (240x124 RGBA) | Official Chery Commercial Vehicle site, https://www.cherycvglobal.com/images/header/Karrylogo.png (header of https://www.cherycvglobal.com/brand). The previously used orange-K-with-briefcase image was a different brand and is removed. | None beyond tight crop + padding (emblem; silver oval badge with K, kept as supplied) |
| vanderhall | `vanderhall.webp` | SHA-256 identical to the official file https://vanderhallusa.com/assets/brand/vanderhall-logo.webp | Crop to shield/V emblem (0,0,142,162) |
| poer | `poer.png` | SHA-256 identical to the official GWM Jordan POER logo file (re-downloaded and compared byte for byte) | Crop to stylised-P emblem (0,0,84,141) |
| hyptec | `hyptec.png` | Black-on-white HYPTEC lock-up. The arrowhead-and-diamond emblem matches the official white logo at https://www.hyptec.com/web/pc/images/change-logo-img/hd-logo.png | Luminance-to-alpha, crop to emblem (0,0,76,88) |
| forthing | `forthing.png` | Dongfeng Forthing lion-shield lock-up from the scraper's `requested` set; emblem matches the shield shown on forthingmotor.com. The cdn.globalso.com original rejects hot-linking, so no byte comparison was possible. | Crop to emblem (0,0,40,51) |
| ineos | `ineos.png` | https://carbrandlogos.com/logos/ineos.png | Tight crop, wordmark |
| baw | `baw.svg` | Scraper `requested` set (vector) | SVG rasterised, tight crop, wordmark |
| jaecoo | `jaecoo.svg` | Scraper `requested` set (vector) | SVG rasterised, tight crop, wordmark |
| kawasaki | `kawasaki.svg` | Scraper `requested` set (vector) | SVG rasterised, tight crop, wordmark |
| jonway | `jonway.gif` | Scraper `requested` set | White matte removed by flood fill from the border (interior whites kept) |
| polaris | `polaris.png` | Scraper `requested` set; already the file served on production | Tight crop, wordmark |
| huanghai | `huanghai.png` (751x616, transparent) | https://carbrandnames.com/images/logos/huanghai.png: the grey chrome oval ring with two wave bands, in use since ~2002. The same emblem is the mark in the header of the brand's official site, https://huanghai-auto.com/upload/3358/logo/logo.jpg (300x44 JPG on white, too small to use directly). Huanghai previously had NO file (generic car icon). The scraper's `requested/huanghai.png` is the SG Automotive PARENT-group mark (red sun / blue waves with Chinese company name) and is deliberately not used. | None beyond tight crop + padding (emblem) |
| kawei | `kawei.jpg` | Scraper `requested` set (JPEG on an opaque white rectangle); no independent source check was possible | Outer white removed by flood fill (inner whites kept), tight crop |
| polarsun | `polarsun.gif` | Scraper `requested` set (GIF on an opaque white rectangle); no independent source check was possible | Outer white removed by flood fill, tight crop |
| zimmer | `zimmer.jpg` | Scraper `requested` set (JPEG on an opaque white rectangle); no independent source check was possible | Outer white removed by flood fill, tight crop |
| xev | `xev.svg` (viewBox 145x40) | XEV's own website, https://www.xevcars.it/images/logos/logo-xev.svg (the light-background lock-up: blue X + grey EV, no tagline; the same page that serves `logo-xev-white.svg` for dark headers). Its Wikimedia Commons description page https://commons.wikimedia.org/wiki/File:XEV_logo_2023.svg (credit: xevcars.it, trademarked) shows the same wordmark in its white-for-dark variant. Replaces the scraper's `carbrandlogos` file, which had white "EV" lettering that vanished on the white coin. Rights: trademark of XEV; used only to identify the brand. | Rasterised unchanged (full lock-up, no crop or recolour) |
| zyle-daewoo-commercial-vehicle | not rebuilt | The existing production PNG (transparent, tightly cropped) is unchanged; only its size in the circle changes (fill table) | none |

Notes

* "Scraper `requested` set" = `D:\car logos scraper\logos`; the scraper did not
  record per-file URLs, so only the file itself is preserved here.
* Round 2 (huanghai, kawei, polarsun, xev, zimmer) came from the review of the
  Search Cars picker on a physical Samsung A17.
* The crop rectangles for forthing, hyptec, poer and vanderhall are in
  `RECIPES` in `build_brand_logos.py`; they only select the emblem part of an
  official lock-up.
* `python tools/brand_logos/build_brand_logos.py --check` fails if the committed
  PNGs differ from what the sources would produce.

* Round 2b: XEV replaced by XEV's own published light-background SVG so the whole mark (X + EV) is shown instead of the X-only crop.
