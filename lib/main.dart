import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(CarListingApp());
}

class CarListingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Listings',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Color(0xFFFF6B00),
        colorScheme: ColorScheme.dark(
          primary: Color(0xFFFF6B00),
          secondary: Color(0xFFFF8533),
          background: Color(0xFF1A1A1A),
        ),
        cardColor: Color(0xFF2A2A2A),
        scaffoldBackgroundColor: Color(0xFF1A1A1A),
        fontFamily: 'Segoe UI',
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => HomePage(),
        '/add': (context) => AddListingPage(),
        '/favorites': (context) => FavoritesPage(),
        '/chat': (context) => ChatListPage(),
        '/login': (context) => LoginPage(),
        '/signup': (context) => SignupPage(),
        '/profile': (context) => ProfilePage(),
        '/payment/history': (context) => PaymentHistoryPage(),
        '/payment/initiate': (context) => PaymentInitiatePage(),
        // For detail pages, use onGenerateRoute
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/car_detail') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => CarDetailsPage(carId: args['carId']),
          );
        }
        if (settings.name == '/edit_listing') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => EditListingPage(car: args['car']),
          );
        }
        if (settings.name == '/chat_conversation') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ChatConversationPage(conversationId: args['conversationId']),
          );
        }
        if (settings.name == '/payment_status') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => PaymentStatusPage(paymentId: args['paymentId']),
          );
        }
        return null;
      },
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List cars = [];
  bool isLoading = true;
  String? selectedBrand;
  String? selectedModel;
  String? selectedTrim;
  String? selectedMinPrice;
  String? selectedMaxPrice;
  String? selectedMinYear;
  String? selectedMaxYear;
  String? selectedMinMileage;
  String? selectedMaxMileage;
  String? selectedCondition;
  String? selectedTransmission;
  String? selectedFuelType;
  String? selectedBodyType;
  String? selectedColor;
  String? selectedDriveType;
  String? selectedCylinderCount;
  String? selectedSeating;
  String? selectedCity;
  String? selectedSortBy;

  // Static options (should be moved to a separate file for maintainability)
  final List<String> brands = [
    'Toyota', 'Volkswagen', 'Ford', 'Honda', 'Hyundai', 'Nissan', 'Chevrolet', 'Kia', 'Mercedes-Benz', 'BMW', 'Audi', 'Lexus', 'Mazda', 'Subaru', 'Volvo', 'Jeep', 'RAM', 'GMC', 'Buick', 'Cadillac', 'Lincoln', 'Mitsubishi', 'Acura', 'Infiniti', 'Tesla', 'Mini', 'Porsche', 'Land Rover', 'Jaguar', 'Fiat', 'Renault', 'Peugeot', 'Citroën', 'Škoda', 'SEAT', 'Dacia', 'Chery', 'BYD', 'Great Wall', 'FAW', 'Roewe', 'Proton', 'Perodua', 'Tata', 'Mahindra', 'Lada', 'ZAZ', 'Daewoo', 'SsangYong', 'Changan', 'Haval', 'Wuling', 'Baojun', 'Nio', 'XPeng', 'Li Auto', 'VinFast', 'Ferrari', 'Lamborghini', 'Bentley', 'Rolls-Royce', 'Aston Martin', 'McLaren', 'Maserati', 'Bugatti', 'Pagani', 'Koenigsegg', 'Polestar', 'Rivian', 'Lucid', 'Alfa Romeo', 'Lancia', 'Abarth', 'Opel', 'DS', 'MAN', 'Iran Khodro', 'Genesis', 'Isuzu', 'Datsun', 'JAC Motors', 'JAC Trucks', 'KTM', 'Alpina', 'Brabus', 'Mansory', 'Bestune', 'Hongqi', 'Dongfeng', 'FAW Jiefang', 'Foton', 'Leapmotor', 'GAC', 'SAIC', 'MG', 'Vauxhall', 'Smart'
  ];
  final Map<String, List<String>> models = {
    'BMW': ['X3', 'X5', 'X7', '3 Series', '5 Series', '7 Series', 'M3', 'M5', 'X1', 'X6'],
    'Mercedes-Benz': ['C-Class', 'E-Class', 'S-Class', 'GLC', 'GLE', 'GLS', 'A-Class', 'CLA', 'GLA', 'AMG GT'],
    'Audi': ['A3', 'A4', 'A6', 'A8', 'Q3', 'Q5', 'Q7', 'Q8', 'RS6', 'TT'],
    'Toyota': ['Camry', 'Corolla', 'RAV4', 'Highlander', 'Tacoma', 'Tundra', 'Prius', 'Avalon', '4Runner', 'Sequoia'],
    'Honda': ['Civic', 'Accord', 'CR-V', 'Pilot', 'Ridgeline', 'Odyssey', 'HR-V', 'Passport', 'Insight', 'Clarity'],
    'Nissan': ['Altima', 'Maxima', 'Rogue', 'Murano', 'Pathfinder', 'Frontier', 'Titan', 'Leaf', 'Sentra', 'Versa'],
    'Ford': ['F-150', 'Mustang', 'Explorer', 'Escape', 'Edge', 'Ranger', 'Bronco', 'Mach-E', 'Focus', 'Fusion'],
    'Chevrolet': ['Silverado', 'Camaro', 'Equinox', 'Tahoe', 'Suburban', 'Colorado', 'Corvette', 'Malibu', 'Cruze', 'Traverse'],
    'Hyundai': ['Elantra', 'Sonata', 'Tucson', 'Santa Fe', 'Palisade', 'Kona', 'Venue', 'Accent', 'Veloster', 'Ioniq'],
    'Kia': ['Forte', 'K5', 'Sportage', 'Telluride', 'Sorento', 'Soul', 'Rio', 'Stinger', 'EV6', 'Niro']
    // Add more as needed
  };
  final List<String> trims = ['Base', 'Sport', 'Luxury', 'Premium', 'Limited', 'Platinum', 'Signature', 'Touring', 'SE', 'LE', 'XLE', 'XSE'];
  final List<String> conditions = ['Any', 'New', 'Used'];
  final List<String> transmissions = ['Any', 'Automatic', 'Manual'];
  final List<String> fuelTypes = ['Any', 'Gasoline', 'Diesel', 'Electric', 'Hybrid', 'LPG', 'Plug-in Hybrid'];
  final List<String> bodyTypes = ['Any', 'Sedan', 'SUV', 'Hatchback', 'Coupe', 'Wagon', 'Pickup', 'Van', 'Minivan', 'Motorcycle', 'UTV', 'ATV'];
  final List<String> colors = ['Any', 'Black', 'White', 'Silver', 'Gray', 'Red', 'Blue', 'Green', 'Yellow', 'Orange', 'Purple', 'Brown', 'Beige', 'Gold'];
  final List<String> driveTypes = ['Any', 'FWD', 'RWD', 'AWD', '4WD'];
  final List<String> cylinderCounts = ['Any', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10+'];
  final List<String> seatings = ['Any', '2', '4', '5', '6', '7', '8', '9', '10+'];
  final List<String> cities = ['Any', 'Baghdad', 'Basra', 'Erbil', 'Najaf', 'Karbala', 'Kirkuk', 'Mosul', 'Sulaymaniyah', 'Dohuk', 'Anbar', 'Halabja', 'Diyala', 'Diyarbakir', 'Maysan', 'Muthanna', 'Dhi Qar', 'Salaheldeen'];
  final List<String> sortByOptions = ['Default', 'Price (Low to High)', 'Price (High to Low)', 'Year (Newest)', 'Year (Oldest)', 'Mileage (Low to High)', 'Mileage (High to Low)'];

  // Add this mapping for trims by brand and model
  final Map<String, Map<String, List<String>>> trimsByBrandModel = {
    'BMW': {
      'X3': ['Base', 'xDrive30i', 'M40i'],
      'X5': ['Base', 'xDrive40i', 'M50i'],
      '3 Series': ['320i', '330i', 'M340i', 'M3'],
      // ... add more as needed
    },
    'Toyota': {
      'Camry': ['L', 'LE', 'SE', 'XSE', 'XLE'],
      'Corolla': ['L', 'LE', 'SE', 'XSE', 'XLE'],
      // ...
    },
    'Mercedes-Benz': {
      'C-Class': ['C 200', 'C 300', 'AMG C 43', 'AMG C 63'],
      // ...
    },
    // ... add more brands/models as needed
  };

  @override
  void initState() {
    super.initState();
    fetchCars();
  }

  Future<void> fetchCars() async {
    setState(() => isLoading = true);
    // Build query string from filters
    Map<String, String> filters = {};
    if (selectedBrand != null && selectedBrand!.isNotEmpty) filters['brand'] = selectedBrand!;
    if (selectedModel != null && selectedModel!.isNotEmpty) filters['model'] = selectedModel!;
    if (selectedTrim != null && selectedTrim!.isNotEmpty) filters['trim'] = selectedTrim!;
    if (selectedMinPrice != null && selectedMaxPrice != null) filters['price_min'] = selectedMinPrice!;
    if (selectedMaxPrice != null) filters['price_max'] = selectedMaxPrice!;
    if (selectedMinYear != null && selectedMaxYear != null) filters['year_min'] = selectedMinYear!;
    if (selectedMaxYear != null) filters['year_max'] = selectedMaxYear!;
    if (selectedMinMileage != null && selectedMaxMileage != null) filters['mileage_min'] = selectedMinMileage!;
    if (selectedMaxMileage != null) filters['mileage_max'] = selectedMaxMileage!;
    if (selectedCondition != null && selectedCondition!.isNotEmpty) filters['condition'] = selectedCondition!;
    if (selectedTransmission != null && selectedTransmission!.isNotEmpty) filters['transmission'] = selectedTransmission!;
    if (selectedFuelType != null && selectedFuelType!.isNotEmpty) filters['fuel_type'] = selectedFuelType!;
    if (selectedBodyType != null && selectedBodyType!.isNotEmpty) filters['body_type'] = selectedBodyType!;
    if (selectedColor != null && selectedColor!.isNotEmpty) filters['color'] = selectedColor!;
    if (selectedDriveType != null && selectedDriveType!.isNotEmpty) filters['drive_type'] = selectedDriveType!;
    if (selectedCylinderCount != null && selectedCylinderCount!.isNotEmpty) filters['cylinder_count'] = selectedCylinderCount!;
    if (selectedSeating != null && selectedSeating!.isNotEmpty) filters['seating'] = selectedSeating!;
    if (selectedCity != null && selectedCity!.isNotEmpty) filters['city'] = selectedCity!;
    if (selectedSortBy != null && selectedSortBy!.isNotEmpty) filters['sort_by'] = selectedSortBy!;
    // Add more filters here
    String query = Uri(queryParameters: filters).query;
    final url = Uri.parse('http://10.0.2.2:5000/cars${query.isNotEmpty ? '?$query' : ''}');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          cars = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  void onFilterChanged() {
    fetchCars();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'CAR LISTINGS',
          style: GoogleFonts.orbitron(
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.account_circle),
            onPressed: () {
              Navigator.pushNamed(context, '/profile');
            },
          ),
          IconButton(
            icon: Icon(Icons.payment),
            onPressed: () {
              Navigator.pushNamed(context, '/payment/history');
            },
          ),
          IconButton(
            icon: Icon(Icons.chat),
            onPressed: () {
              Navigator.pushNamed(context, '/chat');
            },
          ),
          IconButton(
            icon: Icon(Icons.favorite),
            onPressed: () {
              Navigator.pushNamed(context, '/favorites');
            },
          ),
          IconButton(
            icon: Icon(Icons.login),
            onPressed: () {
              Navigator.pushNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background
          Container(
            decoration: BoxDecoration(
              color: Color(0xFF1A1A1A),
            ),
          ),
          // Main content
          Padding(
            padding: const EdgeInsets.only(top: 80.0),
            child: Column(
              children: [
                // Glass-effect search/filter card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    color: Colors.white.withOpacity(0.08),
        child: Padding(
                      padding: const EdgeInsets.all(20.0),
          child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                          Text(
                            'SEARCH VEHICLES',
                            style: GoogleFonts.orbitron(
                              color: Color(0xFFFF6B00),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            children: [
                              // Brand Dropdown
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: selectedBrand,
                                  decoration: InputDecoration(
                                    labelText: 'Brand',
                                    filled: true,
                                    fillColor: Colors.black.withOpacity(0.2),
                                    labelStyle: TextStyle(color: Colors.white),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  items: [
                                    DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))),
                                    ...brands.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      selectedBrand = value;
                                      selectedModel = null;
                                    });
                                    onFilterChanged();
                                  },
                                ),
                              ),
                              SizedBox(width: 12),
                              // Model Dropdown
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: selectedModel,
                                  decoration: InputDecoration(
                                    labelText: 'Model',
                                    filled: true,
                                    fillColor: Colors.black.withOpacity(0.2),
                                    labelStyle: TextStyle(color: Colors.white),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  items: [
                                    DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))),
                                    if (selectedBrand != null && models[selectedBrand!] != null)
                                      ...models[selectedBrand!]!.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                  ],
                                  onChanged: (value) {
                                    setState(() { selectedModel = value; });
                                    onFilterChanged();
                                  },
                                ),
                              ),
                              SizedBox(width: 12),
                              // More Filters Button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFFFF6B00),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(Icons.tune),
                                label: Text('More Filters'),
                                onPressed: () async {
                                  await showDialog(
                                    context: context,
                                    builder: (context) {
                                      // Temporary variables to hold filter values in the dialog
                                      String? tempTrim = selectedTrim;
                                      String? tempMinYear = selectedMinYear;
                                      String? tempMaxYear = selectedMaxYear;
                                      String? tempMinPrice = selectedMinPrice;
                                      String? tempMaxPrice = selectedMaxPrice;
                                      String? tempMinMileage = selectedMinMileage;
                                      String? tempMaxMileage = selectedMaxMileage;
                                      String? tempCondition = selectedCondition;
                                      String? tempTransmission = selectedTransmission;
                                      String? tempFuelType = selectedFuelType;
                                      String? tempBodyType = selectedBodyType;
                                      String? tempColor = selectedColor;
                                      String? tempCity = selectedCity;
                                      String? tempSortBy = selectedSortBy;
                                      String? tempBrand = selectedBrand;
                                      String? tempModel = selectedModel;
                                      return StatefulBuilder(
                                        builder: (context, setStateDialog) {
                                          return AlertDialog(
                                            backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            title: Text('More Filters', style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold)),
                                            content: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Trim (contextual)
                                                  DropdownButtonFormField<String>(
                                                    value: tempTrim ?? '',
                                                    decoration: InputDecoration(labelText: 'Trim', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                    items: () {
                                                      if (tempBrand != null && tempModel != null && trimsByBrandModel[tempBrand] != null && trimsByBrandModel[tempBrand]![tempModel] != null) {
                                                        return [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey)))]
                                                          + trimsByBrandModel[tempBrand]![tempModel]!.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList();
                                                      } else {
                                                        return [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey)))];
                                                      }
                                                    }(),
                                                    onChanged: (tempBrand != null && tempModel != null && trimsByBrandModel[tempBrand] != null && trimsByBrandModel[tempBrand]![tempModel] != null)
                                                      ? (value) => setStateDialog(() => tempTrim = value == '' ? null : value)
                                                      : null,
                                                  ),
                                                  SizedBox(height: 10),
                                                  // Year Range
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: DropdownButtonFormField<String>(
                                                          value: tempMinYear ?? '',
                                                          decoration: InputDecoration(labelText: 'Min Year', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                          items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...List.generate(35, (i) => (1990 + i).toString()).reversed.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList()],
                                                          onChanged: (value) => setStateDialog(() => tempMinYear = value == '' ? null : value),
                                                        ),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Expanded(
                                                        child: DropdownButtonFormField<String>(
                                                          value: tempMaxYear ?? '',
                                                          decoration: InputDecoration(labelText: 'Max Year', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                          items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...List.generate(35, (i) => (1990 + i).toString()).reversed.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList()],
                                                          onChanged: (value) => setStateDialog(() => tempMaxYear = value == '' ? null : value),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 10),
                                                  // Price Range
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: DropdownButtonFormField<String>(
                                                          value: tempMinPrice ?? '',
                                                          decoration: InputDecoration(labelText: 'Min Price', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                          items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...[for (int i = 0; i <= 100000; i += 5000) i.toString()].map((p) => DropdownMenuItem(value: p, child: Text(p == '0' ? 'Any' : p))).toList()],
                                                          onChanged: (value) => setStateDialog(() => tempMinPrice = value == '' ? null : value),
                                                        ),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Expanded(
                                                        child: DropdownButtonFormField<String>(
                                                          value: tempMaxPrice ?? '',
                                                          decoration: InputDecoration(labelText: 'Max Price', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                          items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...[for (int i = 0; i <= 100000; i += 5000) i.toString()].map((p) => DropdownMenuItem(value: p, child: Text(p == '0' ? 'Any' : p))).toList()],
                                                          onChanged: (value) => setStateDialog(() => tempMaxPrice = value == '' ? null : value),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 10),
                                                  // Mileage Range
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: DropdownButtonFormField<String>(
                                                          value: tempMinMileage ?? '',
                                                          decoration: InputDecoration(labelText: 'Min Mileage', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                          items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...[for (int i = 0; i <= 300000; i += 10000) i.toString()].map((m) => DropdownMenuItem(value: m, child: Text(m == '0' ? 'Any' : m))).toList()],
                                                          onChanged: (value) => setStateDialog(() => tempMinMileage = value == '' ? null : value),
                                                        ),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Expanded(
                                                        child: DropdownButtonFormField<String>(
                                                          value: tempMaxMileage ?? '',
                                                          decoration: InputDecoration(labelText: 'Max Mileage', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                          items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...[for (int i = 0; i <= 300000; i += 10000) i.toString()].map((m) => DropdownMenuItem(value: m, child: Text(m == '0' ? 'Any' : m))).toList()],
                                                          onChanged: (value) => setStateDialog(() => tempMaxMileage = value == '' ? null : value),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 10),
                                                  // Condition
                                                  DropdownButtonFormField<String>(
                                                    value: tempCondition ?? '',
                                                    decoration: InputDecoration(labelText: 'Condition', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                    items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...conditions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList()],
                                                    onChanged: (value) => setStateDialog(() => tempCondition = value == '' ? null : value),
                                                  ),
                                                  SizedBox(height: 10),
                                                  // Transmission
                                                  DropdownButtonFormField<String>(
                                                    value: tempTransmission ?? '',
                                                    decoration: InputDecoration(labelText: 'Transmission', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                    items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...transmissions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList()],
                                                    onChanged: (value) => setStateDialog(() => tempTransmission = value == '' ? null : value),
                                                  ),
                                                  SizedBox(height: 10),
                                                  // Fuel Type
                                                  DropdownButtonFormField<String>(
                                                    value: tempFuelType ?? '',
                                                    decoration: InputDecoration(labelText: 'Fuel Type', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                    items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...fuelTypes.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList()],
                                                    onChanged: (value) => setStateDialog(() => tempFuelType = value == '' ? null : value),
                                                  ),
                                                  SizedBox(height: 10),
                                                  // Body Type
                                                  DropdownButtonFormField<String>(
                                                    value: tempBodyType ?? '',
                                                    decoration: InputDecoration(labelText: 'Body Type', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                    items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...bodyTypes.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList()],
                                                    onChanged: (value) => setStateDialog(() => tempBodyType = value == '' ? null : value),
                                                  ),
                                                  SizedBox(height: 10),
                                                  // Color
                                                  DropdownButtonFormField<String>(
                                                    value: tempColor ?? '',
                                                    decoration: InputDecoration(labelText: 'Color', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                    items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...colors.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList()],
                                                    onChanged: (value) => setStateDialog(() => tempColor = value == '' ? null : value),
                                                  ),
                                                  SizedBox(height: 10),
                                                  // City
                                                  DropdownButtonFormField<String>(
                                                    value: tempCity ?? '',
                                                    decoration: InputDecoration(labelText: 'City', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                    items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList()],
                                                    onChanged: (value) => setStateDialog(() => tempCity = value == '' ? null : value),
                                                  ),
                                                  SizedBox(height: 10),
                                                  // Sort By
                                                  DropdownButtonFormField<String>(
                                                    value: tempSortBy ?? '',
                                                    decoration: InputDecoration(labelText: 'Sort By', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                    items: [DropdownMenuItem(value: '', child: Text('Default', style: TextStyle(color: Colors.grey))), ...sortByOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList()],
                                                    onChanged: (value) => setStateDialog(() => tempSortBy = value == '' ? null : value),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: Text('Cancel', style: TextStyle(color: Colors.white70)),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF6B00)),
                                                onPressed: () {
                                                  setState(() {
                                                    selectedTrim = tempTrim;
                                                    selectedMinYear = tempMinYear;
                                                    selectedMaxYear = tempMaxYear;
                                                    selectedMinPrice = tempMinPrice;
                                                    selectedMaxPrice = tempMaxPrice;
                                                    selectedMinMileage = tempMinMileage;
                                                    selectedMaxMileage = tempMaxMileage;
                                                    selectedCondition = tempCondition;
                                                    selectedTransmission = tempTransmission;
                                                    selectedFuelType = tempFuelType;
                                                    selectedBodyType = tempBodyType;
                                                    selectedColor = tempColor;
                                                    selectedCity = tempCity;
                                                    selectedSortBy = tempSortBy;
                                                    selectedBrand = tempBrand;
                                                    selectedModel = tempModel;
                                                  });
                                                  onFilterChanged();
                                                  Navigator.pop(context);
                                                },
                                                child: Text('Apply'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : cars.isEmpty
                    ? Center(child: Text('No cars found.'))
                    : GridView.builder(
                        padding: EdgeInsets.all(8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: cars.length,
                        itemBuilder: (context, index) {
                          final car = cars[index];
                          return buildCarCard(car);
                        },
                            ),
                ),
              ],
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.pushNamed(context, '/add');
          if (result == true) {
            fetchCars();
          }
        },
        child: Icon(Icons.add),
        backgroundColor: Theme.of(context).primaryColor,
        tooltip: 'Add Listing',
      ),
    );
  }

  Widget buildCarCard(Map car) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      color: Colors.white.withOpacity(0.10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.pushNamed(
            context,
            '/car_detail',
            arguments: {'carId': car['id']},
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Car image
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              child: car['image_url'] != null && car['image_url'].isNotEmpty
                    ? Image.network(
                        'http://10.0.2.2:5000/static/uploads/${car['image_url']}',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.grey[900],
                          child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
                      ),
                    )
                  : Container(
                        color: Colors.grey[900],
                      width: double.infinity,
                      child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Row(
                    children: [
                      // Brand logo (if available)
                      if (car['brand'] != null && car['brand'].toString().isNotEmpty)
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: Image.network(
                            'http://10.0.2.2:5000/static/uploads/car_brand_logos/${car['brand'].toString().toLowerCase().replaceAll(' ', '-')}.png',
                            errorBuilder: (context, error, stackTrace) => Icon(Icons.directions_car, size: 20, color: Color(0xFFFF6B00)),
                          ),
                        ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          car['title'] ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF6B00),
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    '${car['year'] ?? ''} • ${car['mileage'] ?? ''} km • ${car['city'] ?? ''}',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  SizedBox(height: 6),
                  Text(
                    car['price'] != null ? ' 24${car['price']}' : 'Contact for price',
                    style: TextStyle(
                      color: Color(0xFFFF6B00),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CarDetailsPage extends StatefulWidget {
  final int carId;
  CarDetailsPage({required this.carId});
  @override
  _CarDetailsPageState createState() => _CarDetailsPageState();
}

class _CarDetailsPageState extends State<CarDetailsPage> {
  Map? car;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchCarDetails();
  }

  Future<void> fetchCarDetails() async {
    final url = Uri.parse('http://10.0.2.2:5000/cars/${widget.carId}');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      setState(() {
        car = json.decode(response.body);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Car Details', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
            ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : car == null
              ? Center(child: Text('Car not found.', style: TextStyle(color: Colors.white70)))
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Card(
                      elevation: 12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      color: Colors.white.withOpacity(0.10),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                  child: Column(
                          mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: car!['image_url'] != null && car!['image_url'].isNotEmpty
                                  ? Image.network(
                                'http://10.0.2.2:5000/static/uploads/${car!['image_url']}',
                                height: 220,
                                      width: double.infinity,
                                fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        height: 220,
                                        color: Colors.grey[900],
                                        child: Icon(Icons.directions_car, size: 80, color: Colors.grey[400]),
                              ),
                            )
                          : Container(
                              height: 220,
                                      color: Colors.grey[900],
                              width: double.infinity,
                              child: Icon(Icons.directions_car, size: 80, color: Colors.grey[400]),
                            ),
                            ),
                            SizedBox(height: 20),
                            Text(car!['title'] ?? '', style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 1.5)),
                            SizedBox(height: 12),
                            Text(car!['price'] != null ? '\u0024${car!['price']}' : 'Contact for price', style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 22)),
                            SizedBox(height: 10),
                            Text('${car!['year'] ?? ''} • ${car!['mileage'] ?? ''} km • ${car!['city'] ?? ''}', style: TextStyle(color: Colors.white70, fontSize: 16)),
                            SizedBox(height: 18),
                      Wrap(
                              spacing: 16,
                              runSpacing: 8,
                        children: [
                                _detailChip('Body', car!['body_type']),
                                _detailChip('Transmission', car!['transmission']),
                                _detailChip('Fuel', car!['fuel_type']),
                                _detailChip('Condition', car!['condition']),
                                _detailChip('Seating', car!['seating']?.toString()),
                                _detailChip('Drive', car!['drive_type']),
                                _detailChip('Color', car!['color']),
                                _detailChip('Title', car!['title_status']),
                              ],
                            ),
                            SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  // TODO: Implement contact seller/chat functionality
                                  // For now, show a snackbar
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Contact Seller feature coming soon!')),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFFFF6B00),
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                ),
                                child: Text('Contact Seller', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                      ),
                    ),
    );
  }

  Widget _detailChip(String label, String? value) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    return Chip(
      label: Text('24label: $value', style: TextStyle(color: Colors.white)),
      backgroundColor: Colors.black.withOpacity(0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { isLoading = true; errorMessage = null; });
    final url = Uri.parse('http://10.0.2.2:5000/login');
    final response = await http.post(url, body: {
      'email': emailController.text,
      'password': passwordController.text,
    });
    if (response.statusCode == 200) {
      // Assume login success if 200 (adjust as needed)
      Navigator.pop(context);
    } else {
      setState(() { errorMessage = 'Login failed. Check your credentials.'; });
    }
    setState(() { isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Login', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
        padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: Colors.white.withOpacity(0.10),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
        child: Form(
          key: _formKey,
          child: Column(
                    mainAxisSize: MainAxisSize.min,
            children: [
                      Text(
                        'LOGIN',
                        style: GoogleFonts.orbitron(
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 24),
              TextFormField(
                controller: emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          labelStyle: TextStyle(color: Colors.white),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: TextStyle(color: Colors.white),
                validator: (v) => v == null || v.isEmpty ? 'Enter email' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          labelStyle: TextStyle(color: Colors.white),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: TextStyle(color: Colors.white),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? 'Enter password' : null,
              ),
              SizedBox(height: 24),
              if (errorMessage != null)
                Text(errorMessage!, style: TextStyle(color: Colors.red)),
              SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : login,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                            backgroundColor: Color(0xFFFF6B00),
                          ),
                          child: isLoading
                              ? CircularProgressIndicator(color: Colors.white)
                              : Text('Login', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                      SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {}, // TODO: Implement Google sign-in
                          icon: Icon(Icons.g_mobiledata, color: Colors.white),
                          label: Text('Log in with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[700],
                            padding: EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
              TextButton(
                onPressed: () {
                          Navigator.pushNamed(context, '/signup');
                },
                        child: Text('Don\'t have an account? Sign up', style: TextStyle(color: Colors.white70)),
                ),
              ],
                  ),
                ),
              ),
            ),
            ),
        ),
      ),
    );
  }
}

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  Future<void> signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { isLoading = true; errorMessage = null; });
    final url = Uri.parse('http://10.0.2.2:5000/signup');
    final response = await http.post(url, body: {
      'email': emailController.text,
      'username': usernameController.text,
      'password': passwordController.text,
    });
    if (response.statusCode == 200) {
      Navigator.pop(context);
    } else {
      setState(() { errorMessage = 'Signup failed. Try again.'; });
    }
    setState(() { isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Sign Up', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
        padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: Colors.white.withOpacity(0.10),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
        child: Form(
          key: _formKey,
          child: Column(
                    mainAxisSize: MainAxisSize.min,
            children: [
                      Text(
                        'SIGN UP',
                        style: GoogleFonts.orbitron(
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 24),
              TextFormField(
                controller: usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          labelStyle: TextStyle(color: Colors.white),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: TextStyle(color: Colors.white),
                validator: (v) => v == null || v.isEmpty ? 'Enter username' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          labelStyle: TextStyle(color: Colors.white),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: TextStyle(color: Colors.white),
                validator: (v) => v == null || v.isEmpty ? 'Enter email' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          labelStyle: TextStyle(color: Colors.white),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: TextStyle(color: Colors.white),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? 'Enter password' : null,
              ),
              SizedBox(height: 24),
              if (errorMessage != null)
                Text(errorMessage!, style: TextStyle(color: Colors.red)),
              SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : signup,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                            backgroundColor: Color(0xFFFF6B00),
                          ),
                          child: isLoading
                              ? CircularProgressIndicator(color: Colors.white)
                              : Text('Sign Up', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                      SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {}, // TODO: Implement Google sign-up
                          icon: Icon(Icons.g_mobiledata, color: Colors.white),
                          label: Text('Sign up with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[700],
                            padding: EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/login');
                        },
                        child: Text('Already have an account? Login', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
        ),
      ),
    );
  }
}

class AddListingPage extends StatefulWidget {
  @override
  _AddListingPageState createState() => _AddListingPageState();
}

class _AddListingPageState extends State<AddListingPage> {
  final _formKey = GlobalKey<FormState>();
  final picker = ImagePicker();
  File? _imageFile;
  bool isLoading = false;
  String? errorMessage;

  // Controllers for form fields
  final TextEditingController titleController = TextEditingController();
  final TextEditingController brandController = TextEditingController();
  final TextEditingController modelController = TextEditingController();
  final TextEditingController trimController = TextEditingController();
  final TextEditingController yearController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController mileageController = TextEditingController();
  final TextEditingController colorController = TextEditingController();
  final TextEditingController bodyTypeController = TextEditingController();
  final TextEditingController transmissionController = TextEditingController();
  final TextEditingController fuelTypeController = TextEditingController();
  final TextEditingController conditionController = TextEditingController();
  final TextEditingController seatingController = TextEditingController();
  final TextEditingController driveTypeController = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController titleStatusController = TextEditingController();

  // In _AddListingPageState, add state for selected values
  String selectedBrand = '';
  String selectedModel = '';
  String selectedTrim = '';
  String selectedYear = '';
  String selectedTransmission = '';
  String selectedFuelType = '';
  String selectedBodyType = '';
  String selectedColor = '';
  String selectedCity = '';

  Future<void> _pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { isLoading = true; errorMessage = null; });
    // Instead of creating the car, go to payment screen
    final carData = {
        'title': titleController.text,
        'brand': brandController.text,
        'model': modelController.text,
        'trim': trimController.text,
        'year': int.tryParse(yearController.text),
        'price': double.tryParse(priceController.text),
        'mileage': int.tryParse(mileageController.text),
        'color': colorController.text,
        'body_type': bodyTypeController.text,
        'transmission': transmissionController.text,
        'fuel_type': fuelTypeController.text,
        'condition': conditionController.text,
        'seating': int.tryParse(seatingController.text),
        'drive_type': driveTypeController.text,
        'city': cityController.text,
        'title_status': titleStatusController.text,
    };
    setState(() { isLoading = false; });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ListingFeePaymentPage(carData: carData, imageFile: _imageFile),
      ),
    ).then((result) {
      if (result == true) {
        Navigator.pop(context, true); // Notify HomePage to refresh
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Access the same lists/maps as HomePage
    final brands = [
      'Toyota', 'Volkswagen', 'Ford', 'Honda', 'Hyundai', 'Nissan', 'Chevrolet', 'Kia', 'Mercedes-Benz', 'BMW', 'Audi', 'Lexus', 'Mazda', 'Subaru', 'Volvo', 'Jeep', 'RAM', 'GMC', 'Buick', 'Cadillac', 'Lincoln', 'Mitsubishi', 'Acura', 'Infiniti', 'Tesla', 'Mini', 'Porsche', 'Land Rover', 'Jaguar', 'Fiat', 'Renault', 'Peugeot', 'Citroën', 'Škoda', 'SEAT', 'Dacia', 'Chery', 'BYD', 'Great Wall', 'FAW', 'Roewe', 'Proton', 'Perodua', 'Tata', 'Mahindra', 'Lada', 'ZAZ', 'Daewoo', 'SsangYong', 'Changan', 'Haval', 'Wuling', 'Baojun', 'Nio', 'XPeng', 'Li Auto', 'VinFast', 'Ferrari', 'Lamborghini', 'Bentley', 'Rolls-Royce', 'Aston Martin', 'McLaren', 'Maserati', 'Bugatti', 'Pagani', 'Koenigsegg', 'Polestar', 'Rivian', 'Lucid', 'Alfa Romeo', 'Lancia', 'Abarth', 'Opel', 'DS', 'MAN', 'Iran Khodro', 'Genesis', 'Isuzu', 'Datsun', 'JAC Motors', 'JAC Trucks', 'KTM', 'Alpina', 'Brabus', 'Mansory', 'Bestune', 'Hongqi', 'Dongfeng', 'FAW Jiefang', 'Foton', 'Leapmotor', 'GAC', 'SAIC', 'MG', 'Vauxhall', 'Smart'
    ];
    final models = {
      'BMW': ['X3', 'X5', 'X7', '3 Series', '5 Series', '7 Series', 'M3', 'M5', 'X1', 'X6'],
      'Mercedes-Benz': ['C-Class', 'E-Class', 'S-Class', 'GLC', 'GLE', 'GLS', 'A-Class', 'CLA', 'GLA', 'AMG GT'],
      'Audi': ['A3', 'A4', 'A6', 'A8', 'Q3', 'Q5', 'Q7', 'Q8', 'RS6', 'TT'],
      'Toyota': ['Camry', 'Corolla', 'RAV4', 'Highlander', 'Tacoma', 'Tundra', 'Prius', 'Avalon', '4Runner', 'Sequoia'],
      'Honda': ['Civic', 'Accord', 'CR-V', 'Pilot', 'Ridgeline', 'Odyssey', 'HR-V', 'Passport', 'Insight', 'Clarity'],
      'Nissan': ['Altima', 'Maxima', 'Rogue', 'Murano', 'Pathfinder', 'Frontier', 'Titan', 'Leaf', 'Sentra', 'Versa'],
      'Ford': ['F-150', 'Mustang', 'Explorer', 'Escape', 'Edge', 'Ranger', 'Bronco', 'Mach-E', 'Focus', 'Fusion'],
      'Chevrolet': ['Silverado', 'Camaro', 'Equinox', 'Tahoe', 'Suburban', 'Colorado', 'Corvette', 'Malibu', 'Cruze', 'Traverse'],
      'Hyundai': ['Elantra', 'Sonata', 'Tucson', 'Santa Fe', 'Palisade', 'Kona', 'Venue', 'Accent', 'Veloster', 'Ioniq'],
      'Kia': ['Forte', 'K5', 'Sportage', 'Telluride', 'Sorento', 'Soul', 'Rio', 'Stinger', 'EV6', 'Niro']
    };
    final trimsByBrandModel = {
      'BMW': {
        'X3': ['Base', 'xDrive30i', 'M40i'],
        'X5': ['Base', 'xDrive40i', 'M50i'],
        '3 Series': ['320i', '330i', 'M340i', 'M3'],
      },
      'Toyota': {
        'Camry': ['L', 'LE', 'SE', 'XSE', 'XLE'],
        'Corolla': ['L', 'LE', 'SE', 'XSE', 'XLE'],
      },
      'Mercedes-Benz': {
        'C-Class': ['C 200', 'C 300', 'AMG C 43', 'AMG C 63'],
      },
    };
    final years = List.generate(35, (i) => (1990 + i).toString()).reversed.toList();
    final transmissions = ['Automatic', 'Manual'];
    final fuelTypes = ['Gasoline', 'Diesel', 'Electric', 'Hybrid', 'LPG', 'Plug-in Hybrid'];
    final bodyTypes = ['Sedan', 'SUV', 'Hatchback', 'Coupe', 'Wagon', 'Pickup', 'Van', 'Minivan', 'Motorcycle', 'UTV', 'ATV'];
    final colors = ['Black', 'White', 'Silver', 'Gray', 'Red', 'Blue', 'Green', 'Yellow', 'Orange', 'Purple', 'Brown', 'Beige', 'Gold'];
    final cities = ['Baghdad', 'Basra', 'Erbil', 'Najaf', 'Karbala', 'Kirkuk', 'Mosul', 'Sulaymaniyah', 'Dohuk', 'Anbar', 'Halabja', 'Diyala', 'Diyarbakir', 'Maysan', 'Muthanna', 'Dhi Qar', 'Salaheldeen'];
    // ... existing code ...
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Add Listing', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(32),
        child: Card(
          elevation: 12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          color: Colors.white.withOpacity(0.10),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
        child: Form(
          key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: _imageFile == null
                      ? Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                                color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(Icons.camera_alt, size: 48, color: Colors.grey[400]),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.file(_imageFile!, width: 120, height: 120, fit: BoxFit.cover),
                        ),
                ),
              ),
              SizedBox(height: 16),
              Text('Add Car Details', style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
              SizedBox(height: 20),
              _buildTextField(titleController, 'Title', true),
              // Brand Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: DropdownButtonFormField<String>(
                  value: selectedBrand,
                  decoration: InputDecoration(labelText: 'Brand'),
                  items: [DropdownMenuItem(value: '', child: Text('Select Brand', style: TextStyle(color: Colors.grey)))]
                    + brands.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedBrand = value ?? '';
                      selectedModel = '';
                      selectedTrim = '';
                      brandController.text = selectedBrand;
                      modelController.text = '';
                      trimController.text = '';
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Select a brand' : null,
                ),
              ),
              // Model Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: DropdownButtonFormField<String>(
                  value: selectedModel,
                  decoration: InputDecoration(labelText: 'Model'),
                  items: [DropdownMenuItem(value: '', child: Text('Select Model', style: TextStyle(color: Colors.grey)))]
                    + (selectedBrand.isNotEmpty && models[selectedBrand] != null
                        ? models[selectedBrand]!.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList()
                        : []),
                  onChanged: (value) {
                    setState(() {
                      selectedModel = value ?? '';
                      selectedTrim = '';
                      modelController.text = selectedModel;
                      trimController.text = '';
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Select a model' : null,
                ),
              ),
              // Trim Dropdown (contextual)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: DropdownButtonFormField<String>(
                  value: selectedTrim,
                  decoration: InputDecoration(labelText: 'Trim'),
                  items: () {
                    if (selectedBrand.isNotEmpty && selectedModel.isNotEmpty && trimsByBrandModel[selectedBrand] != null && trimsByBrandModel[selectedBrand]![selectedModel] != null) {
                      return [DropdownMenuItem(value: '', child: Text('Select Trim', style: TextStyle(color: Colors.grey)))]
                        + trimsByBrandModel[selectedBrand]![selectedModel]!.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList();
                    } else {
                      return [DropdownMenuItem(value: '', child: Text('Select Trim', style: TextStyle(color: Colors.grey)))];
                    }
                  }(),
                  onChanged: (value) {
                    setState(() {
                      selectedTrim = value ?? '';
                      trimController.text = selectedTrim;
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Select a trim' : null,
                ),
              ),
              // Year Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: DropdownButtonFormField<String>(
                  value: selectedYear,
                  decoration: InputDecoration(labelText: 'Year'),
                  items: [DropdownMenuItem(value: '', child: Text('Select Year', style: TextStyle(color: Colors.grey)))]
                    + years.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedYear = value ?? '';
                      yearController.text = selectedYear;
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Select a year' : null,
                ),
              ),
              // Transmission Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: DropdownButtonFormField<String>(
                  value: selectedTransmission,
                  decoration: InputDecoration(labelText: 'Transmission'),
                  items: [DropdownMenuItem(value: '', child: Text('Select Transmission', style: TextStyle(color: Colors.grey)))]
                    + transmissions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedTransmission = value ?? '';
                      transmissionController.text = selectedTransmission;
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Select a transmission' : null,
                ),
              ),
              // Fuel Type Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: DropdownButtonFormField<String>(
                  value: selectedFuelType,
                  decoration: InputDecoration(labelText: 'Fuel Type'),
                  items: [DropdownMenuItem(value: '', child: Text('Select Fuel Type', style: TextStyle(color: Colors.grey)))]
                    + fuelTypes.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedFuelType = value ?? '';
                      fuelTypeController.text = selectedFuelType;
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Select a fuel type' : null,
                ),
              ),
              // Body Type Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: DropdownButtonFormField<String>(
                  value: selectedBodyType,
                  decoration: InputDecoration(labelText: 'Body Type'),
                  items: [DropdownMenuItem(value: '', child: Text('Select Body Type', style: TextStyle(color: Colors.grey)))]
                    + bodyTypes.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedBodyType = value ?? '';
                      bodyTypeController.text = selectedBodyType;
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Select a body type' : null,
                ),
              ),
              // Color Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: DropdownButtonFormField<String>(
                  value: selectedColor,
                  decoration: InputDecoration(labelText: 'Color'),
                  items: [DropdownMenuItem(value: '', child: Text('Select Color', style: TextStyle(color: Colors.grey)))]
                    + colors.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedColor = value ?? '';
                      colorController.text = selectedColor;
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Select a color' : null,
                ),
              ),
              // City Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: DropdownButtonFormField<String>(
                  value: selectedCity,
                  decoration: InputDecoration(labelText: 'City'),
                  items: [DropdownMenuItem(value: '', child: Text('Select City', style: TextStyle(color: Colors.grey)))]
                    + cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCity = value ?? '';
                      cityController.text = selectedCity;
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Select a city' : null,
                ),
              ),
              // The rest as before
              _buildTextField(priceController, 'Price', false, keyboardType: TextInputType.number),
              _buildTextField(mileageController, 'Mileage', true, keyboardType: TextInputType.number),
              _buildTextField(conditionController, 'Condition', true),
              _buildTextField(seatingController, 'Seating', true, keyboardType: TextInputType.number),
              _buildTextField(driveTypeController, 'Drive Type', true),
              _buildTextField(titleStatusController, 'Title Status', true),
              SizedBox(height: 24),
              if (errorMessage != null)
                Text(errorMessage!, style: TextStyle(color: Colors.red)),
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFF6B00),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text('Add Listing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, bool required, {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: keyboardType,
        validator: required ? (v) => v == null || v.isEmpty ? 'Enter $label' : null : null,
      ),
    );
  }
}

class EditListingPage extends StatefulWidget {
  final Map car;
  EditListingPage({required this.car});

  @override
  _EditListingPageState createState() => _EditListingPageState();
}

class _EditListingPageState extends State<EditListingPage> {
  final _formKey = GlobalKey<FormState>();
  final picker = ImagePicker();
  File? _imageFile;
  bool isLoading = false;
  String? errorMessage;

  // Controllers for form fields
  late TextEditingController titleController;
  late TextEditingController brandController;
  late TextEditingController modelController;
  late TextEditingController trimController;
  late TextEditingController yearController;
  late TextEditingController priceController;
  late TextEditingController mileageController;
  late TextEditingController colorController;
  late TextEditingController bodyTypeController;
  late TextEditingController transmissionController;
  late TextEditingController fuelTypeController;
  late TextEditingController conditionController;
  late TextEditingController seatingController;
  late TextEditingController driveTypeController;
  late TextEditingController cityController;
  late TextEditingController titleStatusController;

  @override
  void initState() {
    super.initState();
    final car = widget.car;
    titleController = TextEditingController(text: car['title'] ?? '');
    brandController = TextEditingController(text: car['brand'] ?? '');
    modelController = TextEditingController(text: car['model'] ?? '');
    trimController = TextEditingController(text: car['trim'] ?? '');
    yearController = TextEditingController(text: car['year']?.toString() ?? '');
    priceController = TextEditingController(text: car['price']?.toString() ?? '');
    mileageController = TextEditingController(text: car['mileage']?.toString() ?? '');
    colorController = TextEditingController(text: car['color'] ?? '');
    bodyTypeController = TextEditingController(text: car['body_type'] ?? '');
    transmissionController = TextEditingController(text: car['transmission'] ?? '');
    fuelTypeController = TextEditingController(text: car['fuel_type'] ?? '');
    conditionController = TextEditingController(text: car['condition'] ?? '');
    seatingController = TextEditingController(text: car['seating']?.toString() ?? '');
    driveTypeController = TextEditingController(text: car['drive_type'] ?? '');
    cityController = TextEditingController(text: car['city'] ?? '');
    titleStatusController = TextEditingController(text: car['title_status'] ?? '');
  }

  Future<void> _pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { isLoading = true; errorMessage = null; });
    final url = Uri.parse('http://10.0.2.2:5000/cars/${widget.car['id']}');
    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'title': titleController.text,
        'brand': brandController.text,
        'model': modelController.text,
        'trim': trimController.text,
        'year': int.tryParse(yearController.text),
        'price': double.tryParse(priceController.text),
        'mileage': int.tryParse(mileageController.text),
        'color': colorController.text,
        'body_type': bodyTypeController.text,
        'transmission': transmissionController.text,
        'fuel_type': fuelTypeController.text,
        'condition': conditionController.text,
        'seating': int.tryParse(seatingController.text),
        'drive_type': driveTypeController.text,
        'city': cityController.text,
        'title_status': titleStatusController.text,
      }),
    );
    if (response.statusCode == 200) {
      Navigator.pop(context, true);
    } else {
      setState(() { errorMessage = 'Failed to update listing. Check your input.'; });
    }
    setState(() { isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Edit Listing', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(32),
        child: Card(
          elevation: 12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          color: Colors.white.withOpacity(0.10),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: _imageFile == null
                          ? (widget.car['image_url'] != null && widget.car['image_url'].isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Image.network(
                                    'http://10.0.2.2:5000/static/uploads/${widget.car['image_url']}',
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 120,
                                      height: 120,
                                      color: Colors.grey[900],
                                      child: Icon(Icons.camera_alt, size: 48, color: Colors.grey[400]),
                                    ),
                                  ),
                                )
                              : Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                                    color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(Icons.camera_alt, size: 48, color: Colors.grey[400]),
                                ))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.file(_imageFile!, width: 120, height: 120, fit: BoxFit.cover),
                        ),
                ),
              ),
              SizedBox(height: 16),
                  Text('Edit Car Details', style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                  SizedBox(height: 20),
              _buildTextField(titleController, 'Title', true),
              _buildBrandDropdown(),
              _buildTextField(modelController, 'Model', true),
              _buildTextField(trimController, 'Trim', true),
              _buildTextField(yearController, 'Year', true, keyboardType: TextInputType.number),
              _buildTextField(priceController, 'Price', false, keyboardType: TextInputType.number),
              _buildTextField(mileageController, 'Mileage', true, keyboardType: TextInputType.number),
              _buildTextField(colorController, 'Color', true),
              _buildTextField(bodyTypeController, 'Body Type', true),
              _buildTextField(transmissionController, 'Transmission', true),
              _buildTextField(fuelTypeController, 'Fuel Type', true),
              _buildTextField(conditionController, 'Condition', true),
              _buildTextField(seatingController, 'Seating', true, keyboardType: TextInputType.number),
              _buildTextField(driveTypeController, 'Drive Type', true),
                  _buildTextField(cityController, 'City', true),
              _buildTextField(titleStatusController, 'Title Status', true),
              SizedBox(height: 24),
              if (errorMessage != null)
                Text(errorMessage!, style: TextStyle(color: Colors.red)),
              SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                      onPressed: isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFFF6B00),
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: isLoading
                          ? CircularProgressIndicator(color: Colors.white)
                          : Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
              ),
            ),
            ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, bool required, {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: keyboardType,
        validator: required ? (v) => v == null || v.isEmpty ? 'Enter $label' : null : null,
      ),
    );
  }

  Widget _buildBrandDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: DropdownButtonFormField<String>(
        value: brandController.text.isEmpty ? '' : brandController.text,
        decoration: InputDecoration(labelText: 'Brand'),
        items: [
          DropdownMenuItem(value: '', child: Text('Select Brand', style: TextStyle(color: Colors.grey))),
          // TODO: Populate with real brands
        ],
        onChanged: (value) {
          setState(() {
            brandController.text = value ?? '';
          });
        },
        validator: (v) => v == null || v.isEmpty ? 'Select a brand' : null,
      ),
    );
  }
}

class FavoritesPage extends StatefulWidget {
  @override
  _FavoritesPageState createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List cars = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchFavorites();
  }

  Future<void> fetchFavorites() async {
    setState(() => isLoading = true);
    final url = Uri.parse('http://10.0.2.2:5000/api/favorites');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          cars = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> toggleFavorite(int carId) async {
    final url = Uri.parse('http://10.0.2.2:5000/api/favorite/$carId');
    await http.post(url);
    fetchFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('My Favorites', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : cars.isEmpty
              ? Center(child: Text('No favorites yet.', style: TextStyle(color: Colors.white70)))
              : GridView.builder(
                  padding: EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: cars.length,
                  itemBuilder: (context, index) {
                    final car = cars[index];
    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 8,
                      color: Colors.white.withOpacity(0.10),
      child: Stack(
      children: [
          InkWell(
                            borderRadius: BorderRadius.circular(20),
            onTap: () {
                              Navigator.pushNamed(
                context,
                                '/car_detail',
                                arguments: {'carId': car['id']},
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  child: car['image_url'] != null && car['image_url'].isNotEmpty
                                        ? Image.network(
                            'http://10.0.2.2:5000/static/uploads/${car['image_url']}',
                            fit: BoxFit.cover,
            width: double.infinity,
                            errorBuilder: (context, error, stackTrace) => Container(
                                              color: Colors.grey[900],
                              child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
                          ),
                        )
                      : Container(
                                            color: Colors.grey[900],
                          width: double.infinity,
                          child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
                                          ),
                        ),
                ),
                Padding(
                                  padding: const EdgeInsets.all(12.0),
            child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                                      Row(
                                        children: [
                                          if (car['brand'] != null && car['brand'].toString().isNotEmpty)
                                            SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: Image.network(
                                                'http://10.0.2.2:5000/static/uploads/car_brand_logos/${car['brand'].toString().toLowerCase().replaceAll(' ', '-')}.png',
                                                errorBuilder: (context, error, stackTrace) => Icon(Icons.directions_car, size: 20, color: Color(0xFFFF6B00)),
                                              ),
                                            ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              car['title'] ?? '',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFFF6B00),
                                                fontSize: 16,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        '${car['year'] ?? ''} • ${car['mileage'] ?? ''} km • ${car['city'] ?? ''}',
                                        style: TextStyle(color: Colors.white70, fontSize: 13),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        car['price'] != null ? '\u0024${car['price']}' : 'Contact for price',
                                        style: TextStyle(
                                          color: Color(0xFFFF6B00),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                    ],
                  ),
                    ),
                  ],
                ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
                              icon: Icon(Icons.favorite, color: Color(0xFFFF6B00)),
              onPressed: () => toggleFavorite(car['id']),
                              tooltip: 'Remove from favorites',
            ),
          ),
        ],
                      ),
                    );
                  },
      ),
    );
  }
}

class ChatListPage extends StatefulWidget {
  @override
  _ChatListPageState createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  List conversations = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchChats();
  }

  Future<void> fetchChats() async {
    setState(() => isLoading = true);
    final url = Uri.parse('http://10.0.2.2:5000/api/chats');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
                        setState(() {
          conversations = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('My Chats', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : conversations.isEmpty
              ? Center(child: Text('No conversations yet.', style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conv = conversations[index];
                    return Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      color: Colors.white.withOpacity(0.10),
                      margin: EdgeInsets.only(bottom: 14),
                      child: ListTile(
                      leading: Icon(Icons.chat_bubble_outline, color: Color(0xFFFF6B00)),
                        title: Text('Conversation #${conv['id']}', style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold)),
                        subtitle: Text('Car ID: ${conv['car_id']}', style: TextStyle(color: Colors.white70)),
                      onTap: () {
                          Navigator.pushNamed(
                          context,
                            '/chat_conversation',
                            arguments: {'conversationId': conv['id']},
                        );
                      },
                      ),
                    );
                  },
                ),
    );
  }
}

class ChatConversationPage extends StatefulWidget {
  final int conversationId;
  ChatConversationPage({required this.conversationId});

  @override
  _ChatConversationPageState createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  List messages = [];
  bool isLoading = true;
  final TextEditingController messageController = TextEditingController();
  bool sending = false;

  @override
  void initState() {
    super.initState();
    fetchMessages();
  }

  Future<void> fetchMessages() async {
    setState(() => isLoading = true);
    final url = Uri.parse('http://10.0.2.2:5000/api/chats/${widget.conversationId}/messages');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          messages = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> sendMessage() async {
    if (messageController.text.trim().isEmpty) return;
    setState(() { sending = true; });
    final url = Uri.parse('http://10.0.2.2:5000/api/chats/${widget.conversationId}/send');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'content': messageController.text.trim()}),
    );
    if (response.statusCode == 200) {
      messageController.clear();
      fetchMessages();
    }
    setState(() { sending = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Conversation', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
                        children: [
          Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg['is_me'] ?? false;
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: EdgeInsets.symmetric(vertical: 6),
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                            color: isMe ? Color(0xFFFF6B00).withOpacity(0.85) : Colors.white.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            msg['content'] ?? '',
                            style: TextStyle(color: isMe ? Colors.white : Colors.white70, fontWeight: FontWeight.w500),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
                  padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                          style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                            hintStyle: TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.2),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                      SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: sending ? null : sendMessage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF6B00),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        ),
                        child: sending
                            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(Icons.send, color: Colors.white),
                          ),
                        ],
                      ),
                ),
              ],
            ),
    );
  }
}

class PaymentHistoryPage extends StatefulWidget {
  @override
  _PaymentHistoryPageState createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  List payments = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPayments();
  }

  Future<void> fetchPayments() async {
    setState(() => isLoading = true);
    final url = Uri.parse('http://10.0.2.2:5000/api/payments');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          payments = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Payment History', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : payments.isEmpty
              ? Center(child: Text('No payments yet.', style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  padding: EdgeInsets.all(24),
                  itemCount: payments.length,
                  itemBuilder: (context, index) {
                    final p = payments[index];
                    return Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      color: Colors.white.withOpacity(0.10),
                      margin: EdgeInsets.only(bottom: 18),
                      child: ListTile(
                      leading: Icon(Icons.receipt_long, color: Color(0xFFFF6B00)),
                        title: Text('Payment #${p['payment_id']}', style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold)),
                        subtitle: Text('Amount: ${p['amount']} ${p['currency']} | Status: ${p['status']}', style: TextStyle(color: Colors.white70)),
                      onTap: () {
                          Navigator.pushNamed(
                          context,
                            '/payment_status',
                            arguments: {'paymentId': p['payment_id']},
                        );
                      },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/payment/initiate');
        },
        child: Icon(Icons.add),
        backgroundColor: Color(0xFFFF6B00),
        tooltip: 'Initiate Payment',
      ),
    );
  }
}

class PaymentStatusPage extends StatefulWidget {
  final String paymentId;
  PaymentStatusPage({required this.paymentId});

  @override
  _PaymentStatusPageState createState() => _PaymentStatusPageState();
}

class _PaymentStatusPageState extends State<PaymentStatusPage> {
  Map? payment;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchStatus();
  }

  Future<void> fetchStatus() async {
    setState(() => isLoading = true);
    final url = Uri.parse('http://10.0.2.2:5000/api/payment/status/${widget.paymentId}');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          payment = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Payment Status', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : payment == null
              ? Center(child: Text('Payment not found.', style: TextStyle(color: Colors.white70)))
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Card(
                      elevation: 12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      color: Colors.white.withOpacity(0.10),
                      child: Padding(
                        padding: const EdgeInsets.all(28.0),
        child: Column(
                          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                            Text('Payment ID: ${payment!['payment_id']}', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF6B00), fontSize: 18)),
                            SizedBox(height: 10),
                            Text('Amount: ${payment!['amount']} ${payment!['currency']}', style: TextStyle(color: Colors.white, fontSize: 16)),
                            SizedBox(height: 10),
                            Text('Status: ${payment!['status']}', style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 16)),
                            SizedBox(height: 10),
                            Text('Created: ${payment!['created_at']}', style: TextStyle(color: Colors.white70)),
                            SizedBox(height: 10),
                            Text('Updated: ${payment!['updated_at']}', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class PaymentInitiatePage extends StatefulWidget {
  @override
  _PaymentInitiatePageState createState() => _PaymentInitiatePageState();
}

class _PaymentInitiatePageState extends State<PaymentInitiatePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController carIdController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;
  String? paymentId;

  Future<void> initiatePayment() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { isLoading = true; errorMessage = null; paymentId = null; });
    final url = Uri.parse('http://10.0.2.2:5000/api/payment/initiate');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'amount': double.tryParse(amountController.text),
        'car_id': int.tryParse(carIdController.text),
      }),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() { paymentId = data['payment_id']; });
    } else {
      setState(() { errorMessage = 'Failed to initiate payment.'; });
    }
    setState(() { isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Initiate Payment', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Card(
              elevation: 12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              color: Colors.white.withOpacity(0.10),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
        child: Form(
          key: _formKey,
          child: Column(
                    mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                      Text('INITIATE PAYMENT', style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 24),
              TextFormField(
                controller: amountController,
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          labelStyle: TextStyle(color: Colors.white),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'Enter amount' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: carIdController,
                        decoration: InputDecoration(
                          labelText: 'Car ID',
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          labelStyle: TextStyle(color: Colors.white),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'Enter car ID' : null,
              ),
              SizedBox(height: 24),
              if (errorMessage != null)
                Text(errorMessage!, style: TextStyle(color: Colors.red)),
              if (paymentId != null)
                Text('Payment initiated! ID: $paymentId', style: TextStyle(color: Colors.green)),
              SizedBox(height: 12),
                      SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                          onPressed: isLoading ? null : initiatePayment,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF6B00),
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          child: isLoading
                              ? CircularProgressIndicator(color: Colors.white)
                              : Text('Initiate Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
            ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map? user;
  List listings = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchProfile();
  }

  Future<void> fetchProfile() async {
    setState(() => isLoading = true);
    try {
      final userRes = await http.get(Uri.parse('http://10.0.2.2:5000/api/user'));
      final listingsRes = await http.get(Uri.parse('http://10.0.2.2:5000/api/my_listings'));
      if (userRes.statusCode == 200 && listingsRes.statusCode == 200) {
        setState(() {
          user = json.decode(userRes.body);
          listings = json.decode(listingsRes.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> deleteListing(int carId) async {
    // For demo: just remove from UI
    setState(() {
      listings.removeWhere((car) => car['id'] == carId);
    });
    // In production, call backend to delete
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Profile', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : user == null
              ? Center(child: Text('User not found.', style: TextStyle(color: Colors.white70)))
              : SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        elevation: 12,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        color: Colors.white.withOpacity(0.10),
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Row(
              children: [
                              Icon(Icons.account_circle, size: 64, color: Color(0xFFFF6B00)),
                              SizedBox(width: 20),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                  Text(user!['username'], style: GoogleFonts.orbitron(fontWeight: FontWeight.bold, fontSize: 22, color: Color(0xFFFF6B00))),
                              Text(user!['email'], style: TextStyle(color: Colors.white70)),
                                  Text('Joined: ${user!['created_at']}', style: TextStyle(color: Colors.white54)),
                            ],
                ),
              ],
            ),
                        ),
                      ),
                      SizedBox(height: 32),
                      Text('My Listings', style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 16),
                      listings.isEmpty
                          ? Text('No listings yet.', style: TextStyle(color: Colors.white70))
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              itemCount: listings.length,
                              itemBuilder: (context, index) {
                                final car = listings[index];
                                return Card(
                                  elevation: 8,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  color: Colors.white.withOpacity(0.10),
                                  margin: EdgeInsets.only(bottom: 16),
                                  child: ListTile(
                                    leading: car['image_url'] != null && car['image_url'].isNotEmpty
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: Image.network(
                                              'http://10.0.2.2:5000/static/uploads/${car['image_url']}',
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Icon(Icons.directions_car, color: Color(0xFFFF6B00)),
                                            ),
                                          )
                                        : Icon(Icons.directions_car, color: Color(0xFFFF6B00), size: 48),
                                    title: Text(car['title'] ?? '', style: TextStyle(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold)),
                                    subtitle: Text('${car['year'] ?? ''} • ${car['mileage'] ?? ''} km • ${car['city'] ?? ''}', style: TextStyle(color: Colors.white70)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
              children: [
                                        IconButton(
                                          icon: Icon(Icons.edit, color: Color(0xFFFF6B00)),
                                          onPressed: () async {
                                            final result = await Navigator.pushNamed(
                                              context,
                                              '/edit_listing',
                                              arguments: {'car': car},
                                            );
                                            if (result == true) fetchProfile();
                                          },
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => deleteListing(car['id']),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                      SizedBox(height: 24),
                      Center(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/add');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF6B00),
                            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          child: Text('Add New Listing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper for logo URL
String brandLogoUrl(String brand) {
  if (brand == null) return '';
  
  // Map brand names to actual filenames
  final brandMap = {
    'Toyota': 'toyota',
    'BMW': 'bmw',
    'Kia': 'kia',
    'Hyundai': 'hyundai',
    'Chevrolet': 'chevrolet',
    'Nissan': 'nissan',
    'Mercedes-Benz': 'mercedes-benz',
    'Ford': 'ford',
    'Honda': 'honda',
    'Mazda': 'mazda',
    'Volkswagen': 'volkswagen',
    'Audi': 'audi',
    'Lexus': 'lexus',
    'Jeep': 'jeep',
    'Subaru': 'subaru',
    'Porsche': 'porsche',
    'Land Rover': 'land-rover',
    'Jaguar': 'jaguar',
    'Fiat': 'fiat',
    'Peugeot': 'peugeot',
    'Renault': 'renault',
    'Volvo': 'volvo',
    'Suzuki': 'suzuki',
    'Mitsubishi': 'mitsubishi',
    'Mini': 'mini',
    'Opel': 'opel',
    'Skoda': 'skoda',
    'Seat': 'seat',
    'Dacia': 'dacia',
    'Citroen': 'citroen',
    'Infiniti': 'infiniti',
    'Genesis': 'genesis',
    'Chery': 'chery',
    'MG': 'mg',
    'Great Wall': 'great-wall',
    'BYD': 'byd',
    'Geely': 'geely-zgh',
    'Haval': 'haval',
    'Dongfeng': 'dongfeng-motor',
    'Foton': 'foton',
    'Proton': 'proton',
    'Tata': 'tata',
    'SsangYong': 'ssangyong',
    'Isuzu': 'isuzu',
    'Ram': 'ram',
    'GMC': 'gmc',
    'Cadillac': 'cadillac',
    'Buick': 'buick',
    'Lincoln': 'lincoln',
    'Acura': 'acura',
    'Changan': 'changan',
    'Roewe': 'roewe',
    'Wuling': 'wuling',
    'VinFast': 'vinfast',
    'Lucid': 'lucid',
    'Polestar': 'polestar',
    'Rivian': 'rivian',
    'Xpeng': 'xpeng',
    'Nio': 'nio',
    'Leapmotor': 'leapmotor',
    'Lixiang': 'lixiang',
    'Li Auto': 'li-auto',
    'Saic': 'saic',
    'Hongqi': 'hongqi',
    'Iran Khodro': 'iran-khodro',
    'Mahindra': 'mahindra',
    'Lada': 'lada',
    'Pagani': 'pagani',
    'Koenigsegg': 'koenigsegg',
    'Maserati': 'maserati',
    'McLaren': 'mclaren',
    'Rolls-Royce': 'rolls-royce',
    'Bentley': 'bentley',
    'Aston Martin': 'aston-martin',
    'Smart': 'smart',
    'Vauxhall': 'vauxhall',
    'Perodua': 'perodua',
    'MAN': 'man',
    'Faw': 'faw',
    'Faw Jiefang': 'faw-jiefang',
    'JAC Motors': 'jac-motors',
    'JAC Trucks': 'jac-trucks',
    'KTM': 'ktm',
    'Mansory': 'mansory',
    'ZAZ': 'zaz',
  };
  
  final filename = brandMap[brand] ?? brand.toLowerCase().replaceAll(' ', '-').replaceAll('_', '-').replaceAll('.', '').replaceAll('&', 'and');
  final url = 'http://10.0.2.2:5000/brand_logo/$filename.png';
  print('brandLogoUrl for brand: $brand => $url');
  return url;
}

class ListingFeePaymentPage extends StatefulWidget {
  final Map<String, dynamic> carData;
  final File? imageFile;
  ListingFeePaymentPage({required this.carData, this.imageFile});

  @override
  _ListingFeePaymentPageState createState() => _ListingFeePaymentPageState();
}

class _ListingFeePaymentPageState extends State<ListingFeePaymentPage> {
  bool isPaying = false;
  String? errorMessage;

  Future<void> _payAndCreateListing() async {
    setState(() { isPaying = true; errorMessage = null; });
    // 1. Initiate payment (simulate $50 fee)
    final paymentUrl = Uri.parse('http://10.0.2.2:5000/api/payment/initiate');
    final paymentResponse = await http.post(
      paymentUrl,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'amount': 50.0,
        'car_id': null, // Car not created yet
      }),
    );
    if (paymentResponse.statusCode == 200) {
      // Simulate payment success (in real app, redirect to gateway, etc.)
      // 2. Create the car listing
      final carUrl = Uri.parse('http://10.0.2.2:5000/cars');
      final carResponse = await http.post(
        carUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(widget.carData),
      );
      if (carResponse.statusCode == 201) {
        setState(() { isPaying = false; });
        Navigator.pop(context, true); // Success
      } else {
        setState(() { isPaying = false; errorMessage = 'Failed to add listing after payment.'; });
      }
    } else {
      setState(() { isPaying = false; errorMessage = 'Payment failed. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('Listing Fee Payment', style: GoogleFonts.orbitron(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFCC5500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Center(
        child: Card(
          elevation: 12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          color: Colors.white.withOpacity(0.10),
          margin: EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.credit_card, color: Color(0xFFFF6B00), size: 48),
                SizedBox(height: 16),
                Text('Pay Listing Fee', style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 22)),
                SizedBox(height: 12),
                Text('A fee of \$50.00 is required to list your car.', style: TextStyle(color: Colors.white70)),
                SizedBox(height: 24),
                if (errorMessage != null)
                  Text(errorMessage!, style: TextStyle(color: Colors.red)),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isPaying ? null : _payAndCreateListing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF6B00),
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: isPaying
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Pay \$50 and List Car', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ),
                SizedBox(height: 12),
                TextButton(
                  onPressed: isPaying ? null : () => Navigator.pop(context, false),
                  child: Text('Cancel', style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
