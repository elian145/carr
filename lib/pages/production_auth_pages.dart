part of '../app/carzo_shared.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;
  String? _error;
  bool _loginRequired = false;

  int _favoritedAtMs(Map<String, dynamic> m) {
    final raw = (m['favorited_at'] ?? m['favoritedAt'])?.toString().trim();
    if (raw == null || raw.isEmpty) return -1;
    try {
      return DateTime.parse(raw).millisecondsSinceEpoch;
    } catch (e, st) { logNonFatal(e, st); 
      return -1;
    }
  }

  @override
  void initState() {
    super.initState();
    ListingLayoutPrefs.load();
    // Delay loading until after first frame so that inherited widgets
    // like Localizations are available when _loadFavorites runs.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFavorites());
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _loading = true;
      _error = null;
      _loginRequired = false;
    });
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) {
        setState(() {
          _loginRequired = true;
          _loading = false;
        });
        return;
      }
      final sp = await SharedPreferences.getInstance();
      final cacheKey = 'cache_favorites';
      final cached = sp.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final data = json.decode(cached);
          if (data is List) {
            setState(() {
              _favorites = listingMapsFromApiList(data);
              _favorites.sort(
                (a, b) => _favoritedAtMs(b).compareTo(_favoritedAtMs(a)),
              );
              _loading = false;
            });
          }
        } catch (e, st) { logNonFatal(e, st); }
      }
      final decoded = await ApiService.getFavorites();
      final parsed = listingMapsFromFavoritesResponse(decoded);
      setState(() {
        _favorites = parsed;
        _favorites.sort(
          (a, b) => _favoritedAtMs(b).compareTo(_favoritedAtMs(a)),
        );
      });
      unawaited(sp.setString(cacheKey, json.encode(_favorites)));
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        setState(() {
          _loginRequired = true;
        });
      } else {
        setState(() {
          _error = AppLocalizations.of(context)!.failedToLoadListings;
        });
      }
    } catch (e) {
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)!.error,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(String carId) async {
    try {
      final tok = ApiService.accessToken;
      if (tok == null || tok.isEmpty) return;
      // Use API service so endpoint + auth stays consistent.
      final res = await ApiService.toggleFavorite(carId);
      final bool favorited =
          (res['is_favorited'] == true) || (res['favorited'] == true);
      if (!favorited) {
        setState(() {
          _favorites.removeWhere((c) {
            final cid = (c['public_id'] ?? c['id'] ?? '').toString();
            return cid == carId;
          });
        });
      } else {
        unawaited(AnalyticsService.trackFavorite(carId));
      }
    } catch (e, st) { logNonFatal(e, st); }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.favoritesTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          if (_loading)
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
              ),
            )
          else if (_loginRequired)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.notLoggedIn,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      child: Text(AppLocalizations.of(context)!.loginAction),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Center(
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            )
          else if (_favorites.isEmpty)
            Center(
              child: Text(
                AppLocalizations.of(context)!.noFavoritesYet,
                style: TextStyle(color: muted),
              ),
            )
          else
            RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: _loadFavorites,
              child: ValueListenableBuilder<int>(
                valueListenable: ListingLayoutPrefs.columns,
                builder: (context, cols, _) {
                  final listingColumns = (cols == 1) ? 1 : 2;
                  return GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 110),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: listingColumns,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: listingColumns == 2
                          ? (Platform.isIOS ? 0.66 : 0.61)
                          : 2.78,
                    ),
                    itemCount: _favorites.length,
                    itemBuilder: (context, index) {
                      final carMap = Map<String, dynamic>.from(_favorites[index]);
                      final card = buildGlobalCarCard(
                        context,
                        mapListingToGlobalCarCardData(context, carMap),
                        listLayout: listingColumns == 1,
                      );
                      final String carId =
                          (carMap['public_id'] ?? carMap['id'] ?? '').toString();
                      if (carId.isEmpty) return card;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          card,
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _toggleFavorite(carId),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.favorite,
                                    color: Color(0xFFFF6B00),
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 1,
        onTap: (idx) {
          switch (idx) {
            case 0:
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              // Already on favorites
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              _switchMainTabNoAnimation(context, '/profile');
              break;
          }
        },
      ),
    );
  }
}

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  @override
  Widget build(BuildContext context) {
    return const carzo_chat.ChatListPage();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'LoginPage');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)!.error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.loginTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.emailOrPhoneLabel,
                  hintText: AppLocalizations.of(context)!.enterEmailOrPhoneHint,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? AppLocalizations.of(context)!.emailOrPhoneRequired
                    : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.passwordLabel,
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? AppLocalizations.of(context)!.requiredField
                    : null,
              ),
              SizedBox(height: 20),
              Semantics(
                button: true,
                label: AppLocalizations.of(context)!.navLogin,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(AppLocalizations.of(context)!.navLogin),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/forgot-password'),
                child: Text(AppLocalizations.of(context)!.forgotPasswordLink),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/signup'),
                child: Text(AppLocalizations.of(context)!.createAccount),
              ),
            ],
          ),
        ),
      ),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              // Already on login
              break;
          }
        },
      ),
    );
  }
}

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _dealershipNameController = TextEditingController();
  final _dealershipPhoneController = TextEditingController();
  final _dealershipLocationController = TextEditingController();
  bool _loading = false;
  bool _otpSent = false;
  String _authType = 'email'; // 'email' or 'phone'
  bool _isDealer = false;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _dealershipNameController.dispose();
    _dealershipPhoneController.dispose();
    _dealershipLocationController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_isDealer) {
      final dn = _dealershipNameController.text.trim();
      final dp = _dealershipPhoneController.text.trim();
      final dl = _dealershipLocationController.text.trim();
      if (dn.isEmpty || dp.isEmpty || dl.isEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.errorTitle),
            content: const Text(
              'Please fill dealership name, phone, and location before sending the code.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
        return;
      }
    }
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(AppLocalizations.of(context)!.enterPhoneNumber),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final data = await ApiService.sendOtpLegacy(
        phone: '+964$phone',
        isDealer: _isDealer,
        dealershipName: _dealershipNameController.text.trim(),
        dealershipPhone: _dealershipPhoneController.text.trim(),
        dealershipLocation: _dealershipLocationController.text.trim(),
      );
      if (!mounted) return;
      final bool sent = data['sent'] == true;
      setState(() {
        _otpSent = true;
      });
      if (sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.verificationCodeSent),
          ),
        );
      } else if (data['dev_code'] != null && kDebugMode) {
        final String code = data['dev_code'].toString();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.devCodeTitle),
            content: Text(
              AppLocalizations.of(context)!.useCodeToVerify(code),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
      } else {
        final String err =
            data['error']?.toString() ??
            AppLocalizations.of(context)!.couldNotSubmitListing;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.errorTitle),
            content: Text(err),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      String msg = e.message;
      if (e.statusCode == 429) {
        final retryAfter = e.body?['retry_after'];
        final seconds = retryAfter is int
            ? retryAfter
            : (retryAfter is num ? retryAfter.toInt() : null);
        if (seconds != null && seconds > 0) {
          final minutes = (seconds / 60).ceil();
          msg =
              '$msg Try again in $minutes minute${minutes == 1 ? '' : 's'}.';
        }
      }
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)!.error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _signup() async {
    if (!_acceptedTerms) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(acceptTermsRequiredText(context)),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final username = _usernameController.text.trim();
    if (!_isDealer && username.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(
            '${AppLocalizations.of(context)!.usernameLabel} is required',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (_authType == 'email') {
        await authService.registerEmailWithVerification(
          username: _isDealer ? null : username,
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: _isDealer
              ? _dealershipNameController.text.trim()
              : username,
          lastName: _isDealer ? '' : '',
          phoneNumber: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          isDealer: _isDealer,
          dealershipName: _dealershipNameController.text.trim(),
          dealershipPhone: _dealershipPhoneController.text.trim(),
          dealershipLocation: _dealershipLocationController.text.trim(),
        );
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Success'),
            content: const Text(
              'We sent a confirmation link to your email. '
              'Please verify your email to finish creating your account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
        return;
      }
      // Phone path: keep existing API calls for send_otp/signup, then persist tokens via ApiService
      final Map<String, dynamic> requestBody = <String, dynamic>{
        'password': _passwordController.text,
        'auth_type': _authType,
        if (!_isDealer) 'username': username,
        'phone': '+964${_phoneController.text.trim()}',
        'otp_code': _otpController.text.trim(),
        'is_dealer': _isDealer,
        if (_isDealer) ...<String, dynamic>{
          'dealership_name': _dealershipNameController.text.trim(),
          'dealership_phone': _dealershipPhoneController.text.trim(),
          'dealership_location': _dealershipLocationController.text.trim(),
        },
      };
      final data = await ApiService.signupLegacy(requestBody);
      final String? legacyToken = (data['token'] as String?)?.trim();
      final String? access = (data['access_token'] as String?)?.trim();
      final String? refresh = (data['refresh_token'] as String?)?.trim();
      final String? token = (legacyToken != null && legacyToken.isNotEmpty)
          ? legacyToken
          : access;
      if (token != null && token.isNotEmpty) {
        await ApiService.setAccessToken(token);
        if (refresh != null && refresh.isNotEmpty) {
          await ApiService.setRefreshToken(refresh);
        }
        final user = data['user'];
        await authService.activateSession(
          user: user is Map ? Map<String, dynamic>.from(user.cast<String, dynamic>()) : null,
        );
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }
      // No token: try login so we get tokens and profile
      try {
        final loginIdent = _authType == 'phone'
            ? '+964${_phoneController.text.trim()}'
            : username;
        await authService.login(loginIdent, _passwordController.text);
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      } catch (e, st) {
        logNonFatal(e, st);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.errorTitle),
            content: const Text(
              'Signup succeeded. Please log in to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
      }
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'SignupPage');
      String message =
          'Signup failed. Please check your details and try again.';
      if (e is ApiException) {
        if (e.statusCode == 409) {
          message =
              'An account with this email already exists. Try logging in or use Forgot password.';
        } else if (kDebugMode) {
          message = e.message;
        }
      }
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final textColor = isLightShell ? Colors.black87 : Colors.white;
    final mutedTextColor = isLightShell ? Colors.black54 : Colors.white70;
    final fillColor = isLightShell ? Colors.grey.shade100 : Colors.white10;
    final borderColor = isLightShell ? Colors.grey.shade400 : Colors.white54;

    InputDecoration authDecoration({
      required String labelText,
      String? hintText,
      Widget? prefixIcon,
      String? prefixText,
    }) {
      return InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: prefixIcon,
        prefixText: prefixText,
        filled: true,
        fillColor: fillColor,
        labelStyle: TextStyle(color: mutedTextColor),
        hintStyle: TextStyle(color: mutedTextColor),
        prefixStyle: TextStyle(
          color: Color(0xFFFF6B00),
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFF6B00), width: 2),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.signupTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 110),
            children: [
              // Authentication Type Selection
              Text(
                'Choose Authentication Method:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _authType,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _authType = value;
                    _otpSent = false;
                    _otpController.clear();
                  });
                },
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(
                          'Email',
                          style: TextStyle(color: textColor),
                        ),
                        value: 'email',
                        activeColor: Color(0xFFFF6B00),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(
                          'Phone',
                          style: TextStyle(color: textColor),
                        ),
                        value: 'phone',
                        activeColor: Color(0xFFFF6B00),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Account type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'I am registering as a dealership / dealer',
                  style: TextStyle(color: textColor),
                ),
                subtitle: Text(
                  _isDealer
                      ? 'Dealership details required; approval is pending until reviewed.'
                      : 'Leave off for a normal personal account.',
                  style: TextStyle(color: mutedTextColor, fontSize: 13),
                ),
                value: _isDealer,
                onChanged: (v) => setState(() => _isDealer = v),
              ),
              if (_isDealer) ...[
                SizedBox(height: 8),
                TextFormField(
                  controller: _dealershipNameController,
                  style: TextStyle(color: textColor),
                  decoration: authDecoration(labelText: 'Dealership name'),
                  validator: (v) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (v == null || v.trim().isEmpty) {
                      return 'Dealership name is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipPhoneController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.phone,
                  decoration: authDecoration(labelText: 'Dealership phone'),
                  validator: (v) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (v == null || v.trim().isEmpty) {
                      return 'Dealership phone is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipLocationController,
                  style: TextStyle(color: textColor),
                  decoration: authDecoration(labelText: 'Dealership location'),
                  validator: (v) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (v == null || v.trim().isEmpty) {
                      return 'Dealership location is required';
                    }
                    return null;
                  },
                ),
              ],
              SizedBox(height: 16),

              // Conditional fields based on auth type
              if (_authType == 'email') ...[
                TextFormField(
                  controller: _emailController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.emailAddress,
                  decoration: authDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email address',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!RegExp(
                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                    ).hasMatch(v.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
              ] else ...[
                TextFormField(
                  controller: _phoneController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.phone,
                  decoration: authDecoration(
                    labelText: AppLocalizations.of(context)!.enterPhoneNumber,
                    hintText: '7XX XXX XXXX',
                    prefixText: '+964 ',
                  ),
                  inputFormatters: [
                    services.FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9]'),
                    ),
                    services.LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? AppLocalizations.of(context)!.requiredField
                      : null,
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _otpController,
                        style: TextStyle(color: textColor),
                        decoration: authDecoration(
                          labelText: AppLocalizations.of(context)!.sendCode,
                        ),
                        validator: (v) => (!_otpSent)
                            ? AppLocalizations.of(context)!.sendCodeFirst
                            : ((v == null || v.trim().isEmpty)
                                  ? AppLocalizations.of(context)!.requiredField
                                  : null),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _loading ? null : _sendOtp,
                      child: Text(_otpSent ? 'Resend' : 'Send code'),
                    ),
                  ],
                ),
              ],
              if (!_isDealer) ...[
                SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  style: TextStyle(color: textColor),
                  decoration: authDecoration(
                    labelText: AppLocalizations.of(context)!.usernameLabel,
                    hintText: 'Choose a username',
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) {
                      return '${AppLocalizations.of(context)!.usernameLabel} is required';
                    }
                    if (value.length < 3) {
                      return 'Username must be at least 3 characters';
                    }
                    return null;
                  },
                ),
              ],
              SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                style: TextStyle(color: textColor),
                obscureText: true,
                decoration: authDecoration(
                  labelText: AppLocalizations.of(context)!.passwordLabel,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return AppLocalizations.of(context)!.requiredField;
                  }
                  if (v.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  if (!RegExp(r'[A-Z]').hasMatch(v)) {
                    return 'Password must contain at least one uppercase letter';
                  }
                  if (!RegExp(r'[a-z]').hasMatch(v)) {
                    return 'Password must contain at least one lowercase letter';
                  }
                  if (!RegExp(r'\d').hasMatch(v)) {
                    return 'Password must contain at least one number';
                  }
                  if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v)) {
                    return 'Password must contain at least one special character';
                  }
                  return null;
                },
              ),
              SizedBox(height: 12),
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _acceptedTerms = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _trLegacyText(
                        context,
                        'I agree to the ',
                        ar: 'أوافق على ',
                        ku: 'ڕازیم بە ',
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LegalDocumentPage(
                            document: LegalDocument.terms,
                          ),
                        ),
                      ),
                      child: Text(
                        _trLegacyText(
                          context,
                          'Terms',
                          ar: 'الشروط',
                          ku: 'مەرجەکان',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(
                      _trLegacyText(context, ' and ', ar: ' و', ku: ' و'),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LegalDocumentPage(
                            document: LegalDocument.privacy,
                          ),
                        ),
                      ),
                      child: Text(
                        _trLegacyText(
                          context,
                          'Privacy Policy',
                          ar: 'سياسة الخصوصية',
                          ku: 'تایبەتمەندی',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Semantics(
                button: true,
                label: AppLocalizations.of(context)!.createAccount,
                child: ElevatedButton(
                  onPressed: (_loading || !_acceptedTerms) ? null : _signup,
                  child: _loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(AppLocalizations.of(context)!.createAccount),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/login'),
                child: Text(AppLocalizations.of(context)!.haveAccountLogin),
              ),
            ],
          ),
        ),
      ),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              _switchMainTabNoAnimation(context, '/');
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                _switchMainTabNoAnimation(context, '/profile');
              }
              break;
          }
        },
      ),
    );
  }
}

