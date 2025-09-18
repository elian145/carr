import 'package:flutter/foundation.dart';
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
      print('Get cars error: $e');
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
      print('Get car error: $e');
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
      
      // Add to local list
      if (response['car'] != null) {
        _cars.insert(0, response['car']);
        notifyListeners();
      }
      
      return response;
    } catch (e) {
      print('Create car error: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
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
      print('Update car error: $e');
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
      print('Delete car error: $e');
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
      if (response['images'] != null) {
        final newImages = response['images'];
        
        // Update in cars list
        final carIndex = _cars.indexWhere((car) => car['id'] == carId);
        if (carIndex != -1) {
          _cars[carIndex]['images'] = [..._cars[carIndex]['images'], ...newImages];
        }
        
        // Update current car if it's the same
        if (_currentCar?['id'] == carId) {
          _currentCar!['images'] = [..._currentCar!['images'], ...newImages];
        }
        
        notifyListeners();
      }
      
      return response;
    } catch (e) {
      print('Upload car images error: $e');
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
      print('Upload car videos error: $e');
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
      print('Get favorites error: $e');
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
      print('Toggle favorite error: $e');
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
    
    final prices = _cars.map((car) => car['price'] as double).toList();
    prices.sort();
    
    return {
      'min': prices.first,
      'max': prices.last,
    };
  }

  // Get year range
  Map<String, int> getYearRange() {
    if (_cars.isEmpty) return {'min': 0, 'max': 0};
    
    final years = _cars.map((car) => car['year'] as int).toList();
    years.sort();
    
    return {
      'min': years.first,
      'max': years.last,
    };
  }
}
