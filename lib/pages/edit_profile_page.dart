import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/config.dart';
import '../shared/errors/user_error_text.dart';
import '../theme_provider.dart';
import 'package:provider/provider.dart';

String getApiBase() {
  return apiBase();
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  XFile? _profileImage;
  String? _currentProfilePicture;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  bool _shellLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  Color _cardFill(BuildContext context) {
    if (_shellLight(context)) return Colors.white;
    return Color.alphaBlend(
      Colors.white.withOpacity(0.085),
      AppThemes.darkHomeShellBackground,
    );
  }

  Color _cardBorderColor(BuildContext context) {
    if (_shellLight(context)) return const Color(0xFFE0E0E0);
    return Colors.white.withOpacity(0.12);
  }

  Color _primaryInk(BuildContext context) {
    if (_shellLight(context)) return Colors.grey[800]!;
    return const Color(0xFFECECEC);
  }

  Color _secondaryInk(BuildContext context) {
    if (_shellLight(context)) return Colors.grey[600]!;
    return Colors.white70;
  }

  Color _fieldFill(BuildContext context) {
    if (_shellLight(context)) return Colors.grey[50]!;
    return Colors.white.withOpacity(0.06);
  }

  Color _fieldBorder(BuildContext context) {
    if (_shellLight(context)) return Colors.grey[300]!;
    return Colors.white.withOpacity(0.14);
  }

  BoxDecoration _cardDecoration(BuildContext context, {double radius = 16}) {
    final light = _shellLight(context);
    return BoxDecoration(
      color: _cardFill(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _cardBorderColor(context), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(light ? 0.05 : 0.45),
          blurRadius: light ? 10 : 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
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

  Widget _buildProfileImageSection(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final light = _shellLight(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: _cardDecoration(context),
      child: Column(
        children: [
          Text(
            loc.profilePictureTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _primaryInk(context),
            ),
          ),
          SizedBox(height: 20),
          Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor:
                    light ? Colors.grey[200]! : Colors.white.withOpacity(0.12),
                backgroundImage: _profileImage != null
                    ? FileImage(File(_profileImage!.path))
                    : (_currentProfilePicture != null &&
                          _currentProfilePicture!.isNotEmpty)
                    ? NetworkImage(
                        '${getApiBase()}/static/${_currentProfilePicture!}',
                      )
                    : null,
                child:
                    (_profileImage == null &&
                        (_currentProfilePicture == null ||
                            _currentProfilePicture!.isEmpty))
                    ? Icon(
                        Icons.person,
                        size: 60,
                        color: light ? Colors.grey[400]! : Colors.white38,
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Color(0xFFFF6B00),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: light ? Colors.white : const Color(0xFF1E222A),
                      width: 3,
                    ),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    onPressed: _pickImage,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            loc.tapCameraToChangeProfile,
            style: TextStyle(
              fontSize: 14,
              color: _secondaryInk(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFormField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    bool enabled = true,
    String? prefixText,
  }) {
    final borderColor = _fieldBorder(context);
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _shellLight(context)
                  ? Colors.grey[700]!
                  : _secondaryInk(context),
            ),
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            validator: validator,
            enabled: enabled,
            style: TextStyle(
              color: _primaryInk(context),
              fontSize: 16,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Color(0xFFFF6B00)),
              prefixText: prefixText,
              prefixStyle: TextStyle(
                color: Color(0xFFFF6B00),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Color(0xFFFF6B00), width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red, width: 2),
              ),
              filled: true,
              fillColor: _fieldFill(context),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      appBar: AppBar(
        title: Text(loc.editProfileTitle),
        backgroundColor: Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isSaving)
            Container(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveProfile,
              child: Text(
                loc.save,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Container(
              decoration: isLightShell
                  ? const BoxDecoration(color: Colors.white)
                  : AppThemes.shellBackgroundDecoration(
                      Theme.of(context).brightness,
                    ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile Image Section
                      _buildProfileImageSection(context),
                      SizedBox(height: 24),

                      // Error Message
                      if (_errorMessage != null)
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(16),
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: isLightShell
                                ? Colors.red[50]!
                                : Colors.red.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isLightShell
                                  ? Colors.red[200]!
                                  : Colors.red.withOpacity(0.45),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade300),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: isLightShell
                                        ? Colors.red[700]!
                                        : Colors.red.shade200,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Success Message
                      if (_successMessage != null)
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(16),
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: isLightShell
                                ? Colors.green[50]!
                                : Colors.green.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isLightShell
                                  ? Colors.green[200]!
                                  : Colors.green.withOpacity(0.45),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: isLightShell
                                    ? Colors.green
                                    : Colors.green.shade300,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _successMessage!,
                                  style: TextStyle(
                                    color: isLightShell
                                        ? Colors.green[700]!
                                        : Colors.green.shade200,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Form Fields
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(20),
                        decoration: _cardDecoration(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.personalInformationTitle,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _primaryInk(context),
                              ),
                            ),
                            SizedBox(height: 20),

                            // First Name
                            _buildFormField(
                              context,
                              label: loc.firstNameLabel,
                              controller: _firstNameController,
                              icon: Icons.person_outline,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return loc.firstNameRequired;
                                }
                                return null;
                              },
                            ),

                            // Last Name
                            _buildFormField(
                              context,
                              label: loc.lastNameLabel,
                              controller: _lastNameController,
                              icon: Icons.person_outline,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return loc.lastNameRequired;
                                }
                                return null;
                              },
                            ),

                            // Username
                            _buildFormField(
                              context,
                              label: loc.usernameLabel,
                              controller: _usernameController,
                              icon: Icons.alternate_email,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return loc.usernameRequired;
                                }
                                if (value.trim().length < 3) {
                                  return loc.usernameMin3;
                                }
                                return null;
                              },
                            ),

                            // Email
                            _buildFormField(
                              context,
                              label: loc.emailLabel,
                              controller: _emailController,
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                // Email is optional on edit profile. Only validate format if provided.
                                final trimmed = value?.trim() ?? '';
                                if (trimmed.isEmpty) {
                                  return null;
                                }
                                if (!RegExp(
                                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                ).hasMatch(trimmed)) {
                                  return loc.emailInvalid;
                                }
                                return null;
                              },
                            ),

                            // Phone Number
                            _buildFormField(
                              context,
                              label: loc.phoneNumberLabel,
                              controller: _phoneController,
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              prefixText: '+964 ',
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9]'),
                                ),
                                LengthLimitingTextInputFormatter(10),
                              ],
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return loc.phoneRequired;
                                }
                                if (value.trim().length < 10) {
                                  return loc.phoneInvalid;
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF6B00),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isSaving
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(loc.savingLabel),
                                  ],
                                )
                              : Text(
                                  loc.saveChangesButton,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
