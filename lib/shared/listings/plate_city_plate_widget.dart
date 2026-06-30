import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'plate_city_assets.dart';

/// Realistic Iraqi plate tile: blank template + crisp governorate code overlay.
class PlateCityPlateWidget extends StatelessWidget {
  const PlateCityPlateWidget({
    super.key,
    required this.cityCode,
    required this.showKrBand,
    this.width,
    this.height,
  });

  final String cityCode;
  final bool showKrBand;
  final double? width;
  final double? height;

  static const String _baseKr = 'assets/plate_types/private_blank_code.png';
  static const String _baseFederal =
      'assets/plate_types/private_blank_code_federal.png';

  // Measured on private.png (260×52); must match CODE_ERASE in generate script.
  static const double _codeLeft = 50 / 260;
  static const double _codeTop = 3 / 52;
  static const double _codeWidth = 26 / 260;
  static const double _codeHeight = 48 / 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Image.asset(
                showKrBand ? _baseKr : _baseFederal,
                width: w,
                height: h,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              Positioned(
                left: w * _codeLeft,
                top: h * _codeTop,
                width: w * _codeWidth,
                height: h * _codeHeight,
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Text(
                        cityCode,
                        maxLines: 1,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w900,
                          fontSize: 40,
                          height: 1,
                          letterSpacing: -0.8,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

bool plateCityShowsKrBand(String? city) {
  final code = plateCityCode(city);
  return code != null && kKrPlateCityCodes.contains(code);
}

Widget? plateCityPlateGraphic(String city, {double? width, double? height}) {
  if (city == 'Any') return null;
  final code = plateCityCode(city);
  if (code == null) return null;
  return PlateCityPlateWidget(
    cityCode: code,
    showKrBand: plateCityShowsKrBand(city),
    width: width,
    height: height,
  );
}
