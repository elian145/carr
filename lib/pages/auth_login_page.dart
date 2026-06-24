part of 'auth_pages.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends _LoginPageFields
    with _LoginPageActions, _LoginPageBuild {}
