import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'api_service.dart';
import 'websocket_service.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  bool _isAuthenticated = false;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = false;

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  // Initialize authentication state
  Future<void> initialize() async {
    _setLoading(true);
    
    try {
      await ApiService.initializeTokens();
      
      if (ApiService.isAuthenticated) {
        await _loadUserProfile();
        await WebSocketService.connect();
      }
    } catch (e) {
      developer.log('Auth initialization error: $e', name: 'AuthService');
      await _clearAuthState();
    } finally {
      _setLoading(false);
    }
  }

  // Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Load user profile
  Future<void> _loadUserProfile() async {
    try {
      final response = await ApiService.getProfile();
      // Backend returns bare user object {id, username, email}
      // or sometimes {user:{...}}. Support both.
      _currentUser = (response['user'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(response['user'])
          : Map<String, dynamic>.from(response);
      _isAuthenticated = true;
      notifyListeners();
    } catch (e) {
      developer.log('Load profile error: $e', name: 'AuthService');
      await _clearAuthState();
    }
  }

  // Register new user
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
  }) async {
    _setLoading(true);
    
    try {
      final response = await ApiService.register(
        username: username,
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
      );
      
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Login user
  Future<Map<String, dynamic>> login(String emailOrPhone, String password) async {
    _setLoading(true);
    
    try {
      final response = await ApiService.login(emailOrPhone, password);
      // Save user from response or fetch via /auth/me when absent
      if (response['user'] != null && response['user'] is Map<String, dynamic>) {
        _currentUser = Map<String, dynamic>.from(response['user']);
      } else {
        try {
          final me = await ApiService.getProfile();
          _currentUser = (me['user'] is Map<String, dynamic>) ? Map<String, dynamic>.from(me['user']) : Map<String, dynamic>.from(me);
        } catch (_) {}
      }
      _isAuthenticated = true;
      
      // Connect to WebSocket
      await WebSocketService.connect();
      
      notifyListeners();
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Logout user
  Future<void> logout() async {
    _setLoading(true);
    
    try {
      await ApiService.logout();
      WebSocketService.disconnect();
    } catch (e) {
      developer.log('Logout error: $e', name: 'AuthService');
    } finally {
      await _clearAuthState();
      _setLoading(false);
    }
  }

  // Forgot password
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    _setLoading(true);
    
    try {
      final response = await ApiService.forgotPassword(email);
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Reset password
  Future<Map<String, dynamic>> resetPassword(String token, String newPassword) async {
    _setLoading(true);
    
    try {
      final response = await ApiService.resetPassword(token, newPassword);
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Verify email
  Future<Map<String, dynamic>> verifyEmail(String token) async {
    _setLoading(true);
    
    try {
      final response = await ApiService.verifyEmail(token);
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Update profile
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> profileData) async {
    _setLoading(true);
    
    try {
      final response = await ApiService.updateProfile(profileData);
      
      // Update current user data
      if (response['user'] != null && response['user'] is Map<String, dynamic>) {
        _currentUser = Map<String, dynamic>.from(response['user']);
        notifyListeners();
      }
      
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Upload profile picture
  Future<Map<String, dynamic>> uploadProfilePicture(dynamic imageFile) async {
    _setLoading(true);
    
    try {
      final response = await ApiService.uploadProfilePicture(imageFile);
      
      // Update current user data
      if (_currentUser != null && response['profile_picture'] != null) {
        _currentUser!['profile_picture'] = response['profile_picture'];
        notifyListeners();
      }
      
      return response;
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Clear authentication state
  Future<void> _clearAuthState() async {
    _isAuthenticated = false;
    _currentUser = null;
    await ApiService.clearTokens();
    notifyListeners();
  }

  // Check if user is verified
  bool get isUserVerified => _currentUser?['is_verified'] ?? false;

  // Get user ID
  String? get userId => _currentUser?['id'];

  // Get user name
  String get userName => _currentUser != null 
      ? '${_currentUser!['first_name'] ?? ''} ${_currentUser!['last_name'] ?? ''}'.trim()
      : '';

  // Get user email
  String? get userEmail => _currentUser?['email'];

  // Get user phone
  String? get userPhone => _currentUser?['phone_number'];

  // Get profile picture
  String? get profilePicture => _currentUser?['profile_picture'];

  // Check if user is admin
  bool get isAdmin => _currentUser?['is_admin'] ?? false;
}
