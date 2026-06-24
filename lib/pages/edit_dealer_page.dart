import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/maps/dealer_map_coords.dart';
import '../shared/maps/open_google_maps.dart';
import '../shared/media/media_url.dart';
import '../theme_provider.dart';
import '../widgets/dealer_location_map_preview.dart';
import 'dealer_location_picker_page.dart';
import '../shared/debug/app_log.dart';

part 'edit_dealer_page_fields.dart';
part 'edit_dealer_page_style.dart';
part 'edit_dealer_page_hours.dart';
part 'edit_dealer_page_profile.dart';
part 'edit_dealer_page_location.dart';
part 'edit_dealer_page_media.dart';
part 'edit_dealer_page_save.dart';
part 'edit_dealer_page_build_body_upper.dart';
part 'edit_dealer_page_build_body_lower.dart';
part 'edit_dealer_page_build_body.dart';
part 'edit_dealer_page_build.dart';

class EditDealerPage extends StatefulWidget {
  const EditDealerPage({super.key});

  @override
  State<EditDealerPage> createState() => _EditDealerPageState();
}

class _EditDealerPageState extends _EditDealerPageFields
    with
        _EditDealerPageStyle,
        _EditDealerPageHours,
        _EditDealerPageProfile,
        _EditDealerPageLocation,
        _EditDealerPageMedia,
        _EditDealerPageSave,
        _EditDealerPageBuildBodyUpper,
        _EditDealerPageBuildBodyLower,
        _EditDealerPageBuildBody,
        _EditDealerPageBuild {}
