part of 'edit_profile_page.dart';

mixin _EditProfilePageLoad on _EditProfilePageStyle {
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
        _emailController.text = currentUser['email'] ?? '';
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
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
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

      // Prepare profile data
      final profileData = {
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone_number': '+964${_phoneController.text.trim()}',
        'username': _usernameController.text.trim(),
      };

      // Update profile
      await authService.updateProfile(profileData);

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
