part of 'forgot_password_page.dart';

abstract class _ForgotPasswordPageFields extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _phoneFocus = FocusNode();
  bool _isLoading = false;
  bool _codeSent = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }
}
