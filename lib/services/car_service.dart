import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';

class CarService extends ChangeNotifier {
  static final CarService _instance = CarService._internal();
  factory CarService() => _instance;
  CarService._internal();

  List<Map<String, dynamic>> _cars = [];
  List<Map<String, dynamic>> _favorites = [];
  Map<String, dynamic>? _currentCar;
  bool _isLoading = false;
  int _currentPage = 1;
  bool _hasMore = true;

  // Getters
  List<Map<String, dynamic>> get cars => _cars;
  List<Map<String, dynamic>> get favorites => _favorites;
  Map<String, dynamic>? get currentCar => _currentCar;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  // Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Get cars with filtering
  Future<void> getCars({
    bool refresh = false,
    String? brand,
    String? model,
    int? yearMin,
    int? yearMax,
    double? priceMin,
    double? priceMax,
    String? location,
    String? condition,
    String? bodyType,
    String? transmission,
    String? driveType,
    String? engineType,
  }) async {
    if (refresh) {
      _cars.clear();
      _currentPage = 1;
      _hasMore = true;
    }

    if (!_hasMore && !refresh) return;

    _setLoading(true);

    try {
      final response = await ApiService.getCars(
        page: _currentPage,
        brand: brand,
        model: model,
        yearMin: yearMin,
        yearMax: yearMax,
        priceMin: priceMin,
        priceMax: priceMax,
        location: location,
        condition: condition,
        bodyType: bodyType,
        transmission: transmission,
        driveType: driveType,
        engineType: engineType,
      );

      final newCars = List<Map<String, dynamic>>.from(response['cars']);
      
      if (refresh) {
        _cars = newCars;
      } else {
        _cars.addAll(newCars);
      }

      final pagination = response['pagination'];
      _hasMore = pagination['has_next'];
      _currentPage++;

    } catch (e) {
      developer.log('Get cars error: $e', name: 'CarService');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Get single car
  Future<void> getCar(String carId) async {
    _setLoading(true);

    try {
      final response = await ApiService.getCar(carId);
      _currentCar = response['car'];
    } catch (e) {
      developer.log('Get car error: $e', name: 'CarService');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Create car listing
  Future<Map<String, dynamic>> createCar(Map<String, dynamic> carData) async {
    _setLoading(true);

    try {
      final response = await ApiService.createCar(carData);

      // If AI just processed images on server, attach paths immediately to the local car object
      try {
        final paths = ApiService.getLastProcessedServerPaths();
        if (paths != null && paths.isNotEmpty && response['car'] is Map<String, dynamic>) {
          response['car']['images'] = List<String>.from(paths);
          response['car']['image_url'] = paths.first;
        }
      } catch (_) {}
      
      // Add to local list
      if (response['car'] != null) {
        _cars.insert(0, response['car']);
        notifyListeners();
      }
      
      return response;
    } catch (e) {
      developer.log('Create car error: $e', name: 'CarService');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Add a created car to local store (used for optimistic UI on submit flows)
  void addCarLocal(Map<String, dynamic> car) {
    _cars.insert(0, car);
    notifyListeners();
  }

  // Update car listing
  Future<Map<String, dynamic>> updateCar(String carId, Map<String, dynamic> carData) async {
    _setLoading(true);

    try {
      final response = await ApiService.updateCar(carId, carData);
      
      // Update local data
      if (response['car'] != null) {
        final updatedCar = response['car'];
        
        // Update in cars list
        final index = _cars.indexWhere((car) => car['id'] == carId);
        if (index != -1) {
          _cars[index] = updatedCar;
        }
        
        // Update current car if it's the same
        if (_currentCar?['id'] == carId) {
          _currentCar = updatedCar;
        }
        
        notifyListeners();
      }
      
      return response;
    } catch (e) {
      developer.log('Update car error: $e', name: 'CarService');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Delete car listing
  Future<void> deleteCar(String carId) async {
    _setLoading(true);

    try {
      await ApiService.deleteCar(carId);
      
      // Remove from local list
      _cars.removeWhere((car) => car['id'] == carId);
      
      // Clear current car if it's the same
      if (_currentCar?['id'] == carId) {
        _currentCar = null;
      }
      
      notifyListeners();
    } catch (e) {
      developer.log('Delete car error: $e', name: 'CarService');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Upload car images
  Future<Map<String, dynamic>> uploadCarImages(String carId, List<XFile> imageFiles) async {
    _setLoading(true);

    try {
      final response = await ApiService.uploadCarImages(carId, imageFiles);
      
      // Update local car data
      // Accept either { images: [...] } or { uploaded: [...] } from backend
      final dynamic imagesField = response['images'] ?? response['uploaded'];
      if (imagesField != null) {
        final newImages = imagesField;
        
        // Update in cars list
        final carIndex = _cars.indexWhere((car) => car['id'] == carId);
        if (carIndex != -1) {
          _cars[carIndex]['images'] = [..._cars[carIndex]['images'], ...newImages];
          // Update primary image if backend provided one and we don't have it yet
          final String? newPrimary = (response['image_url'] as String?)?.trim();
          if ((newPrimary != null && newPrimary.isNotEmpty)) {
            _cars[carIndex]['image_url'] = newPrimary;
          } else if ((_cars[carIndex]['image_url'] == null || (_cars[carIndex]['image_url'] as String).isEmpty) && newImages is List && newImages.isNotEmpty) {
            _cars[carIndex]['image_url'] = newImages.first.toString();
          }
        }
        
        // Update current car if it's the same
        if (_currentCar?['id'] == carId) {
          _currentCar!['images'] = [..._currentCar!['images'], ...newImages];
          final String? newPrimary = (response['image_url'] as String?)?.trim();
          if ((newPrimary != null && newPrimary.isNotEmpty)) {
            _currentCar!['image_url'] = newPrimary;
          } else if ((_currentCar!['image_url'] == null || (_currentCar!['image_url'] as String).isEmpty) && newImages is List && newImages.isNotEmpty) {
            _currentCar!['image_url'] = newImages.first.toString();
          }
        }
        
        notifyListeners();
      }
      
      return response;
    } catch (e) {
      developer.log('Upload car images error: $e', name: 'CarService');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Attach already-processed images by server paths (used after "Blur Plates")
  Future<Map<String, dynamic>> attachCarImages(String carId, List<String> paths) async {
    _setLoading(true);
    try {
      final response = await ApiService.attachCarImages(carId, paths);

      final dynamic imagesField = response['images'] ?? response['uploaded'];
      if (imagesField != null) {
        final newImages = imagesField;
        final carIndex = _cars.indexWhere((car) => car['id'] == carId);
        if (carIndex != -1) {
          _cars[carIndex]['images'] = [...(_cars[carIndex]['images'] ?? const []), ...newImages];
          final String? newPrimary = (response['image_url'] as String?)?.trim();
          if (newPrimary != null && newPrimary.isNotEmpty) {
            _cars[carIndex]['image_url'] = newPrimary;
          } else if ((_cars[carIndex]['image_url'] == null || (_cars[carIndex]['image_url'] as String).isEmpty) &&
              newImages is List &&
              newImages.isNotEmpty) {
            _cars[carIndex]['image_url'] = newImages.first.toString();
          }
        }

        if (_currentCar?['id'] == carId) {
          _currentCar!['images'] = [...(_currentCar!['images'] ?? const []), ...newImages];
          final String? newPrimary = (response['image_url'] as String?)?.trim();
          if (newPrimary != null && newPrimary.isNotEmpty) {
            _currentCar!['image_url'] = newPrimary;
          } else if ((_currentCar!['image_url'] == null || (_currentCar!['image_url'] as String).isEmpty) &&
              newImages is List &&
              newImages.isNotEmpty) {
            _currentCar!['image_url'] = newImages.first.toString();
          }
        }
        notifyListeners();
      }

      return response;
    } catch (e) {
      developer.log('Attach car images error: $e', name: 'CarService');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Upload car videos
  Future<Map<String, dynamic>> uploadCarVideos(String carId, List<XFile> videoFiles) async {
    _setLoading(true);

    try {
      final response = await ApiService.uploadCarVideos(carId, videoFiles);
      
      // Update local car data
      if (response['videos'] != null) {
        final newVideos = response['videos'];
        
        // Update in cars list
        final carIndex = _cars.indexWhere((car) => car['id'] == carId);
        if (carIndex != -1) {
          _cars[carIndex]['videos'] = [..._cars[carIndex]['videos'], ...newVideos];
        }
        
        // Update current car if it's the same
        if (_currentCar?['id'] == carId) {
          _currentCar!['videos'] = [..._currentCar!['videos'], ...newVideos];
        }
        
        notifyListeners();
      }
      
      return response;
    } catch (e) {
      developer.log('Upload car videos error: $e', name: 'CarService');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Get favorites
  Future<void> getFavorites({bool refresh = false}) async {
    if (refresh) {
      _favorites.clear();
    }

    _setLoading(true);

    try {
      final response = await ApiService.getFavorites();
      _favorites = List<Map<String, dynamic>>.from(response['cars']);
    } catch (e) {
      developer.log('Get favorites error: $e', name: 'CarService');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Toggle favorite
  Future<void> toggleFavorite(String carId) async {
    try {
      final response = await ApiService.toggleFavorite(carId);
      final isFavorited = response['is_favorited'];
      
      // Update local data
      final carIndex = _cars.indexWhere((car) => car['id'] == carId);
      if (carIndex != -1) {
        _cars[carIndex]['is_favorited'] = isFavorited;
      }
      
      // Update current car if it's the same
      if (_currentCar?['id'] == carId) {
        _currentCar!['is_favorited'] = isFavorited;
      }
      
      // Update favorites list
      if (isFavorited) {
        // Add to favorites
        final car = _cars.firstWhere((car) => car['id'] == carId);
        _favorites.add(car);
      } else {
        // Remove from favorites
        _favorites.removeWhere((car) => car['id'] == carId);
      }
      
      notifyListeners();
    } catch (e) {
      developer.log('Toggle favorite error: $e', name: 'CarService');
      rethrow;
    }
  }

  // Check if car is favorited
  bool isFavorited(String carId) {
    return _favorites.any((car) => car['id'] == carId);
  }

  // Clear current car
  void clearCurrentCar() {
    _currentCar = null;
    notifyListeners();
  }

  // Clear all data
  void clearData() {
    _cars.clear();
    _favorites.clear();
    _currentCar = null;
    _currentPage = 1;
    _hasMore = true;
    notifyListeners();
  }

  // Get car brands
  List<String> getCarBrands() {
    final brands = <String>{};
    for (final car in _cars) {
      brands.add(car['brand']);
    }
    return brands.toList()..sort();
  }

  // Get car models for a brand
  List<String> getCarModels(String brand) {
    final models = <String>{};
    for (final car in _cars) {
      if (car['brand'] == brand) {
        models.add(car['model']);
      }
    }
    return models.toList()..sort();
  }

  // Get price range
  Map<String, double> getPriceRange() {
    if (_cars.isEmpty) return {'min': 0.0, 'max': 0.0};

    // Be robust to price coming as String or num
    final List<double> prices = [];
    for (final car in _cars) {
      final dynamic raw = car['price'];
      if (raw == null) continue;
      if (raw is num) {
        prices.add(raw.toDouble());
      } else {
        final parsed = double.tryParse(raw.toString().replaceAll(RegExp(r'[^0-9.-]'), ''));
        if (parsed != null) prices.add(parsed);
      }
    }

    if (prices.isEmpty) return {'min': 0.0, 'max': 0.0};

    prices.sort();

    return {
      'min': prices.first,
      'max': prices.last,
    };
  }

  // Get year range
  Map<String, int> getYearRange() {
    if (_cars.isEmpty) return {'min': 0, 'max': 0};

    // Be robust to year coming as String or num
    final List<int> years = [];
    for (final car in _cars) {
      final dynamic raw = car['year'];
      if (raw == null) continue;
      if (raw is int) {
        years.add(raw);
      } else if (raw is num) {
        years.add(raw.toInt());
      } else {
        final parsed = int.tryParse(raw.toString().replaceAll(RegExp(r'[^0-9-]'), ''));
        if (parsed != null) years.add(parsed);
      }
    }

    if (years.isEmpty) return {'min': 0, 'max': 0};

    years.sort();

    return {
      'min': years.first,
      'max': years.last,
    };
  }
}
