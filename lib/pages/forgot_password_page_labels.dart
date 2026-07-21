part of 'forgot_password_page.dart';

mixin _ForgotPasswordPageLabels on _ForgotPasswordPageFields {
  String _forgotPasswordTitle(BuildContext context) {
    return AppLocalizations.of(context)!.forgotPassword;
  }

  String _resetPasswordTitle(BuildContext context) {
    return AppLocalizations.of(context)!.resetPassword;
  }

  String _checkYourEmailTitle(BuildContext context) {
    return AppLocalizations.of(context)!.checkYourEmail;
  }

  String _checkYourPhoneTitle(BuildContext context) {
    return AppLocalizations.of(context)!.checkYourMessages;
  }

  String _forgotPasswordIntroEmail(BuildContext context) {
    return AppLocalizations.of(context)!.enterTheEmailAddressForYourAccountWeWillSendAResetCode;
  }

  String _forgotPasswordIntroPhone(BuildContext context) {
    return AppLocalizations.of(context)!.enterThePhoneNumberForYourAccountWeWillSendAResetCodeBySMS;
  }

  String _resetEmailSent(BuildContext context, String email) {
    return AppLocalizations.of(context)!.weVeSentAPasswordResetLinkToEmailPleaseCheckYourEmailAndFollowTheInstruc(email);
  }

  String _resetSmsSent(BuildContext context, String phone) {
    return AppLocalizations.of(context)!.ifAnAccountExistsForPhoneWeSentAPasswordResetCodeBySMS(phone);
  }

  String _checkSpamHint(BuildContext context) {
    return AppLocalizations.of(context)!.ifYouDonTSeeItCheckYourSpamOrJunkFolderTheLinkIsOnlySentIfAnAccountExist;
  }

  String _smsResetHint(BuildContext context) {
    return AppLocalizations.of(context)!.smsMayTakeAMinuteOrTwoACodeIsOnlySentIfAnAccountExistsForThisNumber;
  }

  String _pleaseEnterValidEmail(BuildContext context) {
    return AppLocalizations.of(context)!.pleaseEnterAValidEmail;
  }

  String _pleaseEnterValidPhone(BuildContext context) {
    return AppLocalizations.of(context)!.pleaseEnterAValidPhoneNumberAtLeast8Digits;
  }

  String _sendResetLink(BuildContext context) {
    return AppLocalizations.of(context)!.sendResetLink;
  }

  String _sendSmsResetCode(BuildContext context) {
    return AppLocalizations.of(context)!.sendResetCodeSMS;
  }

  String _enterResetCode(BuildContext context) {
    return AppLocalizations.of(context)!.iHaveTheCodeSetNewPassword;
  }

  String _backToLogin(BuildContext context) {
    return AppLocalizations.of(context)!.backToLogin;
  }

  String _backText(BuildContext context) {
    return AppLocalizations.of(context)!.commonBack;
  }

  String _resetRateLimitedMessage(BuildContext context) {
    return AppLocalizations.of(context)!.tooManyResetAttemptsPleaseWaitALittleAndTryAgain;
  }

  String _failedToSendResetEmailMessage(BuildContext context) {
    return AppLocalizations.of(context)!.failedToSendResetLinkCheckYourEmailAndTryAgainLater;
  }

  String _failedToSendSmsResetMessage(BuildContext context) {
    return AppLocalizations.of(context)!.failedToSendSMSCheckTheNumberAndTryAgainLater;
  }
}
