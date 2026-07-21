part of 'forgot_password_page.dart';

abstract class _ForgotPasswordPageFields extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  bool _isLoading = false;
  bool _emailSent = false;

  /// `'email'` or `'phone'`.
  String _recoveryMethod = 'email';

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }
}
