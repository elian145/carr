import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import '../widgets/in_app_video_screen.dart';
import '../widgets/network_video_thumbnail.dart';

/// Full-screen: swipe through **images** (pinch zoom) and **videos** (inline
/// player) on one page — same order as the gallery grid (images, then videos).

part 'listing_media_viewer_page.dart';
part 'listing_image_gallery_grid_page.dart';
part 'listing_preview_media_grid_page.dart';
part 'listing_preview_media_viewer_page.dart';
part 'listing_gallery_widgets.dart';
