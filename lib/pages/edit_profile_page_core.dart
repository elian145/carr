part of 'edit_profile_page.dart';

mixin _EditProfilePageCore on _EditProfilePageWidgets {
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
                                : Colors.red.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isLightShell
                                  ? Colors.red[200]!
                                  : Colors.red.withValues(alpha: 0.45),
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
                                : Colors.green.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isLightShell
                                  ? Colors.green[200]!
                                  : Colors.green.withValues(alpha: 0.45),
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
