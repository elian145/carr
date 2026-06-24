part of 'forgot_password_page.dart';

mixin _ForgotPasswordPageLabels on _ForgotPasswordPageFields {
  String _forgotPasswordTitle(BuildContext context) {
    return trLegacyText(
      context,
      'Forgot Password',
      ar: 'نسيت كلمة المرور',
      ku: 'وشەی نهێنیم لەبیر چووە',
    );
  }

  String _resetPasswordTitle(BuildContext context) {
    return trLegacyText(
      context,
      'Reset Password',
      ar: 'إعادة تعيين كلمة المرور',
      ku: 'ڕێکخستنی وشەی نهێنی',
    );
  }

  String _checkYourEmailTitle(BuildContext context) {
    return trLegacyText(
      context,
      'Check Your Email',
      ar: 'تحقق من بريدك الإلكتروني',
      ku: 'پشکنینی ئیمەیڵەکەت بکە',
    );
  }

  String _checkYourPhoneTitle(BuildContext context) {
    return trLegacyText(
      context,
      'Check your messages',
      ar: 'تحقق من رسائلك النصية',
      ku: 'پەیامەکانی SMS بپشکنە',
    );
  }

  String _forgotPasswordIntroEmail(BuildContext context) {
    return trLegacyText(
      context,
      'Enter the email address for your account. We will send a reset code.',
      ar: 'أدخل البريد الإلكتروني المرتبط بحسابك. سنرسل رمز إعادة التعيين.',
      ku: 'ئیمەیڵی هەژمارەکەت بنووسە. کۆدی ڕێکخستنەوە دەنێردرێت.',
    );
  }

  String _forgotPasswordIntroPhone(BuildContext context) {
    return trLegacyText(
      context,
      'Enter the phone number for your account. We will send a reset code by SMS.',
      ar: 'أدخل رقم الهاتف المرتبط بحسابك. سنرسل رمز إعادة التعيين عبر رسالة نصية.',
      ku: 'ژمارەی تەلەفۆنەکەت بنووسە. کۆدەکە بە SMS دەنێردرێت.',
    );
  }

  String _resetEmailSent(BuildContext context, String email) {
    return trLegacyText(
      context,
      "We've sent a password reset link to $email. Please check your email and follow the instructions.",
      ar: 'أرسلنا رابط إعادة تعيين إلى $email. يرجى التحقق من بريدك.',
      ku: 'بەستەری ڕێکخستنەوە نێردرا بۆ $email . تکایە ئیمەیلەکەت بپشکنە.',
    );
  }

  String _resetSmsSent(BuildContext context, String phone) {
    return trLegacyText(
      context,
      'If an account exists for $phone, we sent a password reset code by SMS.',
      ar: 'إذا وُجد حساب لـ $phone، فقد أرسلنا رمز إعادة التعيين عبر رسالة نصية.',
      ku: 'ئەگەر هەژمارێک هەبێت بۆ $phone، کۆدی ڕێکخستنەوە بە SMS نێردرا.',
    );
  }

  String _checkSpamHint(BuildContext context) {
    return trLegacyText(
      context,
      "If you don't see it, check your spam or junk folder. The link is only sent if an account exists for this email.",
      ar: 'إن لم تجد الرسالة، تحقق من مجلد البريد العشوائي. يُرسل الرابط فقط إذا وُجد حساب لهذا البريد.',
      ku: 'ئەگەر نەت بینی، پشکنینی سپام بکە. بەستەرەکە تەنها ئەگەر هەژمارێک بۆ ئەم ئیمەیڵە هەبێت نێردرێت.',
    );
  }

  String _smsResetHint(BuildContext context) {
    return trLegacyText(
      context,
      'SMS may take a minute or two. A code is only sent if an account exists for this number.',
      ar: 'قد يستغرق وصول الرسالة دقيقة أو دقيقتين. يُرسل الرمز فقط إذا وُجد حساب لهذا الرقم.',
      ku: 'ڕەنگە SMS کەمێک دوابکەوێت. کۆدەکە تەنها ئەگەر هەژمارێک بۆ ئەم ژمارەیە هەبێت دەنێردرێت.',
    );
  }

  String _pleaseEnterValidEmail(BuildContext context) {
    return trLegacyText(
      context,
      'Please enter a valid email',
      ar: 'يرجى إدخال بريد إلكتروني صالح',
      ku: 'تکایە ئیمەیلێکی دروست بنووسە',
    );
  }

  String _pleaseEnterValidPhone(BuildContext context) {
    return trLegacyText(
      context,
      'Please enter a valid phone number (at least 8 digits)',
      ar: 'يرجى إدخال رقم هاتف صالح (8 أرقام على الأقل)',
      ku: 'تکایە ژمارەی تەلەفۆنێکی دروست بنووسە (کەمترین ٨ ژمارە)',
    );
  }

  String _sendResetLink(BuildContext context) {
    return trLegacyText(
      context,
      'Send Reset Link',
      ar: 'إرسال رابط إعادة التعيين',
      ku: 'ناردنی بەستەری ڕێکخستنەوە',
    );
  }

  String _sendSmsResetCode(BuildContext context) {
    return trLegacyText(
      context,
      'Send reset code (SMS)',
      ar: 'إرسال رمز إعادة التعيين',
      ku: 'ناردنی کۆدی ڕێکخستنەوە',
    );
  }

  String _enterResetCode(BuildContext context) {
    return trLegacyText(
      context,
      'I have the code – set new password',
      ar: 'أدخل رمز إعادة التعيين',
      ku: 'کۆدی ڕێکخستنەوە بنووسە',
    );
  }

  String _backToLogin(BuildContext context) {
    return trLegacyText(
      context,
      'Back to Login',
      ar: 'العودة إلى تسجيل الدخول',
      ku: 'گەڕانەوە بۆ چوونەژوورەوە',
    );
  }

  String _backText(BuildContext context) {
    return trLegacyText(
      context,
      'Back',
      ar: 'رجوع',
      ku: 'گەڕانەوە',
    );
  }

  String _resetRateLimitedMessage(BuildContext context) {
    return trLegacyText(
      context,
      'Too many reset attempts. Please wait a little and try again.',
      ar: 'تم إرسال طلبات كثيرة جدًا. يرجى الانتظار قليلاً ثم المحاولة مرة أخرى.',
      ku: 'زۆر داواکاری نێردراوە. تکایە چەند خولەکێک چاوەڕێ بکە و دووبارە هەوڵبدە.',
    );
  }

  String _failedToSendResetEmailMessage(BuildContext context) {
    return trLegacyText(
      context,
      'Failed to send reset link. Check your email and try again later.',
      ar: 'فشل إرسال رابط إعادة التعيين. تحقق من البريد وحاول لاحقاً.',
      ku: 'نەتوانرا ئیمەییلی ڕێکخستنەوە بنێردرێت. دووبارە هەوڵ بدەرەوە.',
    );
  }

  String _failedToSendSmsResetMessage(BuildContext context) {
    return trLegacyText(
      context,
      'Failed to send SMS. Check the number and try again later.',
      ar: 'تعذر إرسال الرسالة النصية. تحقق من الرقم وحاول لاحقاً.',
      ku: 'نەتوانرا SMS بنێردرێت. ژمارەکە بپشکنە و دووبارە هەوڵ بدەرەوە.',
    );
  }
}
