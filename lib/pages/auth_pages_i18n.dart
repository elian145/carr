part of 'auth_pages.dart';

String _lang(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  // Normalize Central Kurdish code to the same branch used by existing `ku` strings.
  if (code == 'ckb') return 'ku';
  return code;
}
String _forgotPasswordTitle(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'نسيت كلمة المرور';
  if (c == 'ku') return 'وشەی نهێنیم لەبیر چووە';
  return 'Forgot Password';
}

String _welcomeBackText(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'مرحبًا بعودتك';
  if (c == 'ku') return 'بەخێربێیتەوە';
  return 'Welcome Back';
}

String _usernameOrEmailLabel(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return '${loc.usernameLabel} / ${loc.emailLabel}';
}

String _pleaseEnterUsernameOrEmail(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال اسم المستخدم أو البريد الإلكتروني';
  if (c == 'ku') return 'تکایە ناوی بەکارهێنەر یان ئیمەیڵ بنووسە';
  return 'Please enter your username or email';
}

String _pleaseEnterPassword(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال كلمة المرور';
  if (c == 'ku') return 'تکایە وشەی نهێنی بنووسە';
  return 'Please enter your password';
}

/// User-facing message for login failure (no server/exception details).
String _loginFailedMessage(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'فشل تسجيل الدخول. تحقق من بياناتك وحاول مرة أخرى.';
  if (c == 'ku') return 'هەڵە لە چوونەژوورەوە. تکایە دووبارە هەوڵ بدەرەوە.';
  return 'Login failed. Please check your credentials and try again.';
}

String _forgotPasswordQuestion(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'هل نسيت كلمة المرور؟';
  if (c == 'ku') return 'وشەی نهێنیت بیرچووە؟';
  return 'Forgot Password?';
}

String _dontHaveAccount(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'ليس لديك حساب؟ ';
  if (c == 'ku') return 'هەژمارت نیە؟ ';
  return "Don't have an account? ";
}

String _alreadyHaveAccount(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'لديك حساب؟ ';
  if (c == 'ku') return 'هەژمارت هەیە؟ ';
  return 'Already have an account? ';
}

// Removed unused helper _createAccountTitle
String _firstNameLabel(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'الاسم الأول';
  if (c == 'ku') return 'ناوی یەکەم';
  return 'First Name';
}

String _lastNameLabel(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'اسم العائلة';
  if (c == 'ku') return 'ناوی دووەم';
  return 'Last Name';
}

String _pleaseEnterFirstName(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال الاسم الأول';
  if (c == 'ku') return 'تکایە ناوی یەکەم بنووسە';
  return 'Please enter your first name';
}

String _pleaseEnterLastName(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال اسم العائلة';
  if (c == 'ku') return 'تکایە ناوی دووەم بنووسە';
  return 'Please enter your last name';
}

String _usernameMustBeAtLeast3(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يجب أن يكون اسم المستخدم 3 أحرف على الأقل';
  if (c == 'ku') return 'ناوی بەکارهێنەر پێویستە کەمەترین ٣ پیت بێت';
  return 'Username must be at least 3 characters';
}

String _pleaseEnterValidEmail(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال بريد إلكتروني صالح';
  if (c == 'ku') return 'تکایە ئیمەیلێکی دروست بنووسە';
  return 'Please enter a valid email';
}

String _phoneOptionalLabel(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  final c = _lang(context);
  if (c == 'ar') return '${loc.phoneLabel} (اختياري)';
  if (c == 'ku') return '${loc.phoneLabel} (هەلبژاردە)';
  return 'Phone Number (Optional)';
}

String _confirmPasswordLabel(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'تأكيد كلمة المرور';
  if (c == 'ku') return 'دووبارە کردنەوەی وشەی نهێنی';
  return 'Confirm Password';
}

String _pleaseConfirmPassword(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى تأكيد كلمة المرور';
  if (c == 'ku') return 'تکایە وشەی نهێنی دووبارە بنووسە';
  return 'Please confirm your password';
}

String _passwordsDoNotMatch(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'كلمتا المرور غير متطابقتين';
  if (c == 'ku') return 'پاسۆردەکان یەک ناگرن';
  return 'Passwords do not match';
}

String _sendResetLink(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'إرسال رابط إعادة التعيين';
  if (c == 'ku') return 'ناردنی بەستەری ڕێکخستنەوە';
  return 'Send Reset Link';
}

String _sendSmsResetCode(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'إرسال رمز إعادة التعيين';
  if (c == 'ku') return 'ناردنی کۆدی ڕێکخستنەوە';
  return 'Send reset code (SMS)';
}

String _forgotPasswordIntroEmail(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'أدخل البريد الإلكتروني المرتبط بحسابك. سنرسل رمز إعادة التعيين.';
  }
  if (c == 'ku') {
    return 'ئیمەیڵی هەژمارەکەت بنووسە. کۆدی ڕێکخستنەوە دەنێردرێت.';
  }
  return 'Enter the email address for your account. We will send a reset code.';
}

String _forgotPasswordIntroPhone(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'أدخل رقم الهاتف المرتبط بحسابك. سنرسل رمز إعادة التعيين عبر رسالة نصية.';
  }
  if (c == 'ku') {
    return 'ژمارەی تەلەفۆنەکەت بنووسە. کۆدەکە بە SMS دەنێردرێت.';
  }
  return 'Enter the phone number for your account. We will send a reset code by SMS.';
}

String _pleaseEnterValidPhone(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال رقم هاتف صالح (8 أرقام على الأقل)';
  if (c == 'ku') {
    return 'تکایە ژمارەی تەلەفۆنێکی دروست بنووسە (کەمترین ٨ ژمارە)';
  }
  return 'Please enter a valid phone number (at least 8 digits)';
}

String _backToLogin(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'العودة إلى تسجيل الدخول';
  if (c == 'ku') return 'گەڕانەوە بۆ چوونەژوورەوە';
  return 'Back to Login';
}

String _enterResetCode(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'أدخل رمز إعادة التعيين';
  if (c == 'ku') return 'کۆدی ڕێکخستنەوە بنووسە';
  return 'I have the code – set new password';
}

String _backText(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'رجوع';
  if (c == 'ku') return 'گەڕانەوە';
  return 'Back';
}

String _checkYourEmailTitle(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'تحقق من بريدك الإلكتروني';
  if (c == 'ku') return 'پشکنینی ئیمەیڵەکەت بکە';
  return 'Check Your Email';
}

String _checkYourPhoneTitle(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'تحقق من رسائلك النصية';
  if (c == 'ku') return 'پەیامەکانی SMS بپشکنە';
  return 'Check your messages';
}

String _resetPasswordTitle(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'إعادة تعيين كلمة المرور';
  if (c == 'ku') return 'ڕێکخستنی وشەی نهێنی';
  return 'Reset Password';
}

String _resetEmailSent(BuildContext context, String email) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'أرسلنا رابط إعادة تعيين إلى $email. يرجى التحقق من بريدك.';
  }
  if (c == 'ku') {
    return 'بەستەری ڕێکخستنەوە نێردرا بۆ $email . تکایە ئیمەیلەکەت بپشکنە.';
  }
  return "We've sent a password reset link to $email. Please check your email and follow the instructions.";
}

String _resetSmsSent(BuildContext context, String phone) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'إذا وُجد حساب لـ $phone، فقد أرسلنا رمز إعادة التعيين عبر رسالة نصية.';
  }
  if (c == 'ku') {
    return 'ئەگەر هەژمارێک هەبێت بۆ $phone، کۆدی ڕێکخستنەوە بە SMS نێردرا.';
  }
  return 'If an account exists for $phone, we sent a password reset code by SMS.';
}

String _checkSpamHint(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'إن لم تجد الرسالة، تحقق من مجلد البريد العشوائي. يُرسل الرابط فقط إذا وُجد حساب لهذا البريد.';
  }
  if (c == 'ku') {
    return 'ئەگەر نەت بینی، پشکنینی سپام بکە. بەستەرەکە تەنها ئەگەر هەژمارێک بۆ ئەم ئیمەیڵە هەبێت نێردرێت.';
  }
  return "If you don't see it, check your spam or junk folder. The link is only sent if an account exists for this email.";
}

String _smsResetHint(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'قد يستغرق وصول الرسالة دقيقة أو دقيقتين. يُرسل الرمز فقط إذا وُجد حساب لهذا الرقم.';
  }
  if (c == 'ku') {
    return 'ڕەنگە SMS کەمێک دوابکەوێت. کۆدەکە تەنها ئەگەر هەژمارێک بۆ ئەم ژمارەیە هەبێت دەنێردرێت.';
  }
  return 'SMS may take a minute or two. A code is only sent if an account exists for this number.';
}

/// User-facing message for registration failure (no server/exception details).
String _registrationFailedMessage(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'فشل التسجيل. تحقق من البيانات وحاول مرة أخرى.';
  if (c == 'ku') return 'هەڵە لە خۆتۆمارکردن. تکایە دووبارە هەوڵ بدەرەوە.';
  return 'Registration failed. Please check your details and try again.';
}

/// User-facing message when reset email fails (no server/exception details).
String _failedToSendResetEmailMessage(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'فشل إرسال رابط إعادة التعيين. تحقق من البريد وحاول لاحقاً.';
  }
  if (c == 'ku') {
    return 'نەتوانرا ئیمەییلی ڕێکخستنەوە بنێردرێت. دووبارە هەوڵ بدەرەوە.';
  }
  return 'Failed to send reset link. Check your email and try again later.';
}

String _failedToSendSmsResetMessage(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'تعذر إرسال الرسالة النصية. تحقق من الرقم وحاول لاحقاً.';
  }
  if (c == 'ku') {
    return 'نەتوانرا SMS بنێردرێت. ژمارەکە بپشکنە و دووبارە هەوڵ بدەرەوە.';
  }
  return 'Failed to send SMS. Check the number and try again later.';
}

String _resetRateLimitedMessage(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'تم إرسال طلبات كثيرة جدًا. يرجى الانتظار قليلاً ثم المحاولة مرة أخرى.';
  }
  if (c == 'ku') {
    return 'زۆر داواکاری نێردراوە. تکایە چەند خولەکێک چاوەڕێ بکە و دووبارە هەوڵبدە.';
  }
  return 'Too many reset attempts. Please wait a little and try again.';
}
