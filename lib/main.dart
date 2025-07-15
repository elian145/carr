import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Listings App',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF1A1A1A),
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
        '/car_detail': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return CarDetailsPage(carId: args['carId']);
        },
        '/chat/conversation': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return ChatConversationPage(conversationId: args['conversationId']);
        },
        '/payment/status': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return PaymentStatusPage(paymentId: args['paymentId']);
        },
        '/edit': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return EditListingPage(car: args['car']);
        },
      },
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> cars = [];
  bool isLoading = false;

  // Filter variables
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

  // Static options
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

  final Map<String, Map<String, List<String>>> trimsByBrandModel = {
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

  bool useCustomMinPrice = false;
  bool useCustomMaxPrice = false;
  bool useCustomMinMileage = false;
  bool useCustomMaxMileage = false;

  // Only include brands with a logo file
  // Remove the manual brandLogoFilenames map

  @override
  void initState() {
    super.initState();
    fetchCars();
  }

  Future<void> fetchCars() async {
    setState(() => isLoading = true);
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
          Container(
            decoration: BoxDecoration(
              color: Color(0xFF1A1A1A),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 80.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
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
                              Flexible(
                                flex: 3,
                                child: GestureDetector(
                                  onTap: () async {
                                    final brand = await showDialog<String>(
                                      context: context,
                                      builder: (context) {
                                        return Dialog(
                                          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            child: Container(
                                            width: 400,
                                            padding: EdgeInsets.all(20),
                              child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                                    Text('Select Brand', style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                                    IconButton(
                                                      icon: Icon(Icons.close, color: Colors.white),
                                                      onPressed: () => Navigator.pop(context),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(height: 10),
                                                SizedBox(
                                                  height: 380, // Constrain grid height for scrolling
                                                  child: GridView.builder(
                                                    shrinkWrap: true,
                                                    physics: BouncingScrollPhysics(),
                                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                      crossAxisCount: 4,
                                                      childAspectRatio: 0.85,
                                                      crossAxisSpacing: 10,
                                                      mainAxisSpacing: 10,
                                                    ),
                                                    itemCount: brands.length,
                                                    itemBuilder: (context, index) {
                                                      final brand = brands[index];
                                                      final logoFile = brand
                                                        .toLowerCase()
                                                        .replaceAll(' ', '-')
                                                        .replaceAll('é', 'e')
                                                        .replaceAll('ö', 'o')
                                                        .replaceAll('ô', 'o')
                                                        .replaceAll('ü', 'u')
                                                        .replaceAll('ä', 'a')
                                                        .replaceAll('ã', 'a')
                                                        .replaceAll('å', 'a')
                                                        .replaceAll('ç', 'c')
                                                        .replaceAll('ñ', 'n')
                                                        .replaceAll('š', 's')
                                                        .replaceAll('ž', 'z')
                                                        .replaceAll('á', 'a')
                                                        .replaceAll('í', 'i')
                                                        .replaceAll('ó', 'o')
                                                        .replaceAll('ú', 'u')
                                                        .replaceAll('ý', 'y')
                                                        .replaceAll('ř', 'r')
                                                        .replaceAll('č', 'c')
                                                        .replaceAll('ě', 'e')
                                                        .replaceAll('Š', 's')
                                                        .replaceAll('Ž', 'z')
                                                        .replaceAll('Č', 'c')
                                                        .replaceAll('Ě', 'e')
                                                        .replaceAll('â', 'a')
                                                        .replaceAll('ê', 'e')
                                                        .replaceAll('î', 'i')
                                                        .replaceAll('ô', 'o')
                                                        .replaceAll('û', 'u')
                                                        .replaceAll('œ', 'oe')
                                                        .replaceAll('æ', 'ae')
                                                        .replaceAll('ß', 'ss')
                                                        + '.png';
                                                      final logoUrl = 'http://10.0.2.2:5000/static/uploads/car_brand_logos/' + logoFile;
                                                      print('Brand: ' + brand + ' Logo URL: ' + logoUrl);
                                                      return InkWell(
                                                        borderRadius: BorderRadius.circular(12),
                                                        onTap: () => Navigator.pop(context, brand),
                                                        child: Container(
                                                          decoration: BoxDecoration(
                                                            color: Colors.black.withOpacity(0.15),
                                                            borderRadius: BorderRadius.circular(12),
                                                            border: Border.all(color: Colors.white24),
                                                          ),
                                                          padding: EdgeInsets.all(6),
                                                          child: Column(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              SizedBox(
                                                                width: 32,
                                                                height: 32,
                                                                child: Image.network(
                                                                  logoUrl,
                                                                  errorBuilder: (context, error, stackTrace) => Icon(Icons.directions_car, size: 22, color: Color(0xFFFF6B00)),
                                                                ),
                                                              ),
                                                              SizedBox(height: 4),
                                                              Text(
                                                                brand,
                                                                style: GoogleFonts.orbitron(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                                                textAlign: TextAlign.center,
                                                                overflow: TextOverflow.ellipsis,
                                                                maxLines: 1,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                    if (brand != null) {
                                            setState(() {
                                        selectedBrand = brand;
                                              selectedModel = '';
                                            });
                                            onFilterChanged();
                                    }
                                  },
                                  child: AbsorbPointer(
                                    child: TextFormField(
                                      readOnly: true,
                                      controller: TextEditingController(text: selectedBrand ?? ''),
                                      style: GoogleFonts.orbitron(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        labelText: 'Brand',
                                        labelStyle: GoogleFonts.orbitron(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                        filled: true,
                                        fillColor: Colors.black.withOpacity(0.15),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                        suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Flexible(
                                        flex: 3,
                                        child: DropdownButtonFormField<String>(
                                          isDense: true,
                                  style: GoogleFonts.orbitron(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                                          value: selectedModel,
                                          decoration: InputDecoration(
                                            labelText: 'Model',
                                    labelStyle: GoogleFonts.orbitron(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                            filled: true,
                                            fillColor: Colors.black.withOpacity(0.15),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                          ),
                                          items: [
                                    DropdownMenuItem(value: '', child: Text('Any', style: GoogleFonts.orbitron(color: Colors.grey, fontSize: 14))),
                                            if (selectedBrand != null && models[selectedBrand!] != null)
                                      ...models[selectedBrand!]!.map((m) => DropdownMenuItem(value: m, child: Text(m, style: GoogleFonts.orbitron(fontSize: 14)))).toList(),
                                          ],
                                          onChanged: (value) {
                                            setState(() { selectedModel = value; });
                                            onFilterChanged();
                                          },
                                        ),
                                      ),
                            ],
                          ),
                          SizedBox(height: 8),
                                      SizedBox(
                            width: double.infinity,
                            height: 36,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Color(0xFFFF6B00),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                minimumSize: Size(0, 32),
                                          ),
                              icon: Icon(Icons.tune, size: 18),
                              label: Text('More Filters', style: GoogleFonts.orbitron(fontSize: 15, fontWeight: FontWeight.bold)),
                                          onPressed: () async {
                                            await showDialog(
                                              context: context,
                                              builder: (context) {
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
                                                            DropdownButtonFormField<String>(
                                                              value: selectedTrim ?? '',
                                                              decoration: InputDecoration(labelText: 'Trim', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                              items: () {
                                                                if (selectedBrand != null && selectedModel != null && trimsByBrandModel[selectedBrand] != null && trimsByBrandModel[selectedBrand]![selectedModel] != null) {
                                                                  return [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey)))]
                                                                    + trimsByBrandModel[selectedBrand]![selectedModel]!.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList();
                                                                } else {
                                                                  return [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey)))];
                                                                }
                                                              }(),
                                                              onChanged: (value) => setState(() => selectedTrim = value == '' ? null : value),
                                                            ),
                                                            SizedBox(height: 10),
                                                            Row(
                                                              children: [
                                                                Expanded(
                                                                  child: DropdownButtonFormField<String>(
                                                                    value: selectedMinYear ?? '',
                                                                    decoration: InputDecoration(labelText: 'Min Year', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                                    items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...List.generate(35, (i) => (1990 + i).toString()).reversed.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList()],
                                                                    onChanged: (value) => setState(() => selectedMinYear = value == '' ? null : value),
                                                                  ),
                                                                ),
                                                                SizedBox(width: 4),
                                                                Expanded(
                                                                  child: DropdownButtonFormField<String>(
                                                                    value: selectedMaxYear ?? '',
                                                                    decoration: InputDecoration(labelText: 'Max Year', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                                    items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...List.generate(35, (i) => (1990 + i).toString()).reversed.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList()],
                                                                    onChanged: (value) => setState(() => selectedMaxYear = value == '' ? null : value),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            SizedBox(height: 10),
                                                            DropdownButtonFormField<String>(
                                                              value: selectedCondition ?? '',
                                                              decoration: InputDecoration(labelText: 'Condition', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                              items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...conditions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList()],
                                                              onChanged: (value) => setState(() => selectedCondition = value == '' ? null : value),
                                                            ),
                                                            SizedBox(height: 10),
                                                            DropdownButtonFormField<String>(
                                                              value: selectedTransmission ?? '',
                                                              decoration: InputDecoration(labelText: 'Transmission', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                              items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...transmissions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList()],
                                                              onChanged: (value) => setState(() => selectedTransmission = value == '' ? null : value),
                                                            ),
                                                            SizedBox(height: 10),
                                                            DropdownButtonFormField<String>(
                                                              value: selectedFuelType ?? '',
                                                              decoration: InputDecoration(labelText: 'Fuel Type', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                              items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...fuelTypes.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList()],
                                                              onChanged: (value) => setState(() => selectedFuelType = value == '' ? null : value),
                                                            ),
                                                            SizedBox(height: 10),
                                                            DropdownButtonFormField<String>(
                                                              value: selectedBodyType ?? '',
                                                              decoration: InputDecoration(labelText: 'Body Type', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                              items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...bodyTypes.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList()],
                                                              onChanged: (value) => setState(() => selectedBodyType = value == '' ? null : value),
                                                            ),
                                                            SizedBox(height: 10),
                                                            DropdownButtonFormField<String>(
                                                              value: selectedColor ?? '',
                                                              decoration: InputDecoration(labelText: 'Color', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                              items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...colors.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList()],
                                                              onChanged: (value) => setState(() => selectedColor = value == '' ? null : value),
                                                            ),
                                                            SizedBox(height: 10),
                                                            DropdownButtonFormField<String>(
                                                              value: selectedCity ?? '',
                                                              decoration: InputDecoration(labelText: 'City', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                              items: [DropdownMenuItem(value: '', child: Text('Any', style: TextStyle(color: Colors.grey))), ...cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList()],
                                                              onChanged: (value) => setState(() => selectedCity = value == '' ? null : value),
                                                            ),
                                                            SizedBox(height: 10),
                                                            DropdownButtonFormField<String>(
                                                              value: selectedSortBy ?? '',
                                                              decoration: InputDecoration(labelText: 'Sort By', filled: true, fillColor: Colors.black.withOpacity(0.2), labelStyle: TextStyle(color: Colors.white), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                                                              items: [DropdownMenuItem(value: '', child: Text('Default', style: TextStyle(color: Colors.grey))), ...sortByOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList()],
                                                              onChanged: (value) => setState(() => selectedSortBy = value == '' ? null : value),
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
                                      ),
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
                            'http://10.0.2.2:5000/static/uploads/car_brand_logos/' + (car['brand'].toString().toLowerCase().replaceAll(' ', '-').replaceAll('é', 'e').replaceAll('ö', 'o')) + '.png',
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
                    car['price'] != null ? '₦${car['price']}' : 'Contact for price',
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

// Placeholder classes for other pages
class CarDetailsPage extends StatefulWidget {
  final int carId;
  CarDetailsPage({required this.carId});
  @override
  _CarDetailsPageState createState() => _CarDetailsPageState();
}

class _CarDetailsPageState extends State<CarDetailsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Car Details')),
      body: Center(child: Text('Car Details Page')),
    );
  }
}

class AddListingPage extends StatefulWidget {
  @override
  _AddListingPageState createState() => _AddListingPageState();
}

class _AddListingPageState extends State<AddListingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add Listing')),
      body: Center(child: Text('Add Listing Page')),
    );
  }
}

class FavoritesPage extends StatefulWidget {
  @override
  _FavoritesPageState createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Favorites')),
      body: Center(child: Text('Favorites Page')),
    );
  }
}

class ChatListPage extends StatefulWidget {
  @override
  _ChatListPageState createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: Center(child: Text('Chat List Page')),
    );
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Center(child: Text('Login Page')),
    );
  }
}

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sign Up')),
      body: Center(child: Text('Sign Up Page')),
    );
  }
}

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
      body: Center(child: Text('Profile Page')),
    );
  }
}

class PaymentHistoryPage extends StatefulWidget {
  @override
  _PaymentHistoryPageState createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Payment History')),
      body: Center(child: Text('Payment History Page')),
    );
  }
}

class PaymentInitiatePage extends StatefulWidget {
  @override
  _PaymentInitiatePageState createState() => _PaymentInitiatePageState();
}

class _PaymentInitiatePageState extends State<PaymentInitiatePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Payment Initiate')),
      body: Center(child: Text('Payment Initiate Page')),
    );
  }
}

class ChatConversationPage extends StatefulWidget {
  final String conversationId;
  ChatConversationPage({required this.conversationId});
  @override
  _ChatConversationPageState createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat Conversation')),
      body: Center(child: Text('Chat Conversation Page')),
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Payment Status')),
      body: Center(child: Text('Payment Status Page')),
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Listing')),
      body: Center(child: Text('Edit Listing Page')),
    );
  }
}
