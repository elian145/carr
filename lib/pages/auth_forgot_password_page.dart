part of 'auth_pages.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends _ForgotPasswordPageFields
    with _ForgotPasswordPageActions, _ForgotPasswordPageBuild {}
