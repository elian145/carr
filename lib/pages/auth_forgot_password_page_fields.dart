part of 'auth_pages.dart';

abstract class _ForgotPasswordPageFields extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  /// `'email'` or `'phone'` — controls which identifier is sent to `/auth/forgot-password`.
  String _recoveryMethod = 'email';

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
