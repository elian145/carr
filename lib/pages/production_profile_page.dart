part of 'production_account_pages.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.embedInShell = false});

  /// When true, [MainShell] owns the bottom nav — omit it here.
  final bool embedInShell;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends _ProfilePageFields
    with
        _ProfilePageStyle,
        _ProfilePageLoad,
        _ProfilePageWidgets,
        _ProfilePageBodyGuest,
        _ProfilePageBodyAccount,
        _ProfilePageBodyActions,
        _ProfilePageBody,
        _ProfilePageCore {}
