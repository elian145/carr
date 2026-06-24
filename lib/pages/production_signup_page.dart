part of 'production_auth_pages.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends _SignupPageFields
    with _SignupPageActions, _SignupPageBuild {}
