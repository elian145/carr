part of 'edit_profile_page.dart';

mixin _EditProfilePageWidgets on _EditProfilePageLoad {
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
                    light ? Colors.grey[200]! : Colors.white.withValues(alpha: 0.12),
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
}
