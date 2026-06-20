import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../chat_ui_theme_controller.dart';
import '../features/comparison/state/car_comparison_store.dart';
import '../services/auth_service.dart';
import '../theme_provider.dart';

List<SingleChildWidget> buildAppProviders() {
  return [
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ChangeNotifierProvider(create: (_) => ChatUiThemeController()),
    ChangeNotifierProvider(create: (_) => CarComparisonStore()),
    ChangeNotifierProvider(create: (_) => AuthService()),
  ];
}
