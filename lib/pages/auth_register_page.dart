part of 'auth_pages.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends _RegisterPageFields
    with _RegisterPageActions, _RegisterPageBuild {}
