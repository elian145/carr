part of 'edit_profile_page.dart';

mixin _EditProfilePageLoad on _EditProfilePageStyle {
  /// Email as loaded from the server, used to detect real changes so we only
  /// prompt for OTP confirmation when the value actually changed (S7).
  String _originalEmail = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser != null) {
        _firstNameController.text = currentUser['first_name'] ?? '';
        _lastNameController.text = currentUser['last_name'] ?? '';
        _originalEmail = (currentUser['email'] ?? '').toString();
        _emailController.text = _originalEmail;
        // Remove +964 prefix when loading phone number for editing
        String phoneNumber = currentUser['phone_number'] ?? '';
        if (phoneNumber.startsWith('+964')) {
          phoneNumber = phoneNumber.substring(4);
        }
        _phoneController.text = phoneNumber;
        _usernameController.text = currentUser['username'] ?? '';
        _currentProfilePicture = currentUser['profile_picture'];
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = userErrorText(
            context,
            e,
            fallback: AppLocalizations.of(context)!.failedToLoadUserData,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final localizations = AppLocalizations.of(context)!;
      final image = await pickCircularImage(
        context,
        title: localizations.profilePictureTitle,
        doneLabel: localizations.save,
        cancelLabel: localizations.cancelAction,
      );

      if (image != null && mounted) {
        setState(() {
          _profileImage = image;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = userErrorText(
            context,
            e,
            fallback: AppLocalizations.of(context)!.failedToPickImage,
          );
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      final newEmail = _emailController.text.trim();
      // A genuinely new, non-blank email can't be saved directly: the server
      // requires proof of ownership first (S7). Clearing it to blank, or
      // resubmitting the unchanged value, is still a plain profile update.
      final emailNeedsVerification =
          newEmail.isNotEmpty && newEmail != _originalEmail;

      // Prepare profile data (omit 'email' when it needs separate OTP proof
      // so this call can't be rejected because of it).
      final profileData = {
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        if (!emailNeedsVerification) 'email': newEmail,
        'phone_number': '+964${_phoneController.text.trim()}',
        'username': _usernameController.text.trim(),
      };

      // Update profile
      await authService.updateProfile(profileData);

      if (emailNeedsVerification) {
        if (!mounted) return;
        final verified = await showEmailChangeConfirmDialog(
          context,
          auth: authService,
          newEmail: newEmail,
        );
        if (verified && mounted) {
          _originalEmail = newEmail;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.emailUpdatedSuccess),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }

      // Upload profile picture if selected
      if (_profileImage != null) {
        final uploadResponse = await authService.uploadProfilePicture(
          _profileImage!,
        );
        if (uploadResponse['profile_picture'] != null) {
          setState(() {
            _currentProfilePicture = uploadResponse['profile_picture'];
            _profileImage =
                null; // Clear the local image since it's now uploaded
          });
        }
      }

      if (mounted) {
        setState(() {
          _successMessage = AppLocalizations.of(context)!.profileUpdatedSuccess;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_successMessage!),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Navigate back immediately after successful update
        Navigator.pop(
          context,
          true,
        ); // Return true to indicate successful update
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = userErrorText(
            context,
            e,
            fallback: AppLocalizations.of(context)!.failedToUpdateProfile,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
