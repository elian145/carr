part of 'production_account_pages.dart';

mixin _ProfilePageBodyGuest on _ProfilePageWidgets {
  List<Widget> _buildProfileGuestSection(BuildContext context) {
    return [
      Container(
        width: double.infinity,
        padding: EdgeInsets.all(18),
        decoration: _profileCardDecoration(context),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(0xFFFF6B00).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_outline,
                color: Color(0xFFFF6B00),
                size: 26,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Guest',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _profilePrimaryInk(context),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Sign in to access your profile features.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _profileSecondaryInk(context),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 1,
              ),
              child: Text(AppLocalizations.of(context)!.loginAction),
            ),
          ],
        ),
      ),
      SizedBox(height: 16),
    ];
  }
}
