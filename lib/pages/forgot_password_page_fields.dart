part of 'forgot_password_page.dart';

abstract class _ForgotPasswordPageFields extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  /// `'email'` or `'phone'`.
  String _recoveryMethod = 'email';

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
