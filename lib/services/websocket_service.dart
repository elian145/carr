import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';
import 'config.dart';
import '../shared/debug/app_log.dart';

// Sideload build flag to allow LAN HTTP Socket.IO on iOS release builds.

part 'websocket_service_common.dart';
part 'websocket_service_impl.dart';
part 'websocket_service_models.dart';
