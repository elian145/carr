import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Entry Point
void main() => runApp(CarListingApp());

class CarListingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Listings',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: CarListScreen(),
    );
  }
}

// Model
class Car {
  final int id;
  final String title;
  final String model;
  final double price;
  final String? imageUrl;

  Car({required this.id, required this.title, required this.model, required this.price, this.imageUrl});

  factory Car.fromJson(Map<String, dynamic> json) {
    return Car(
      id: json['id'],
      title: json['title'],
      model: json['model'],
      price: json['price'].toDouble(),
      imageUrl: json['image_url'],
    );
  }
}

// Home Screen - List of Cars
class CarListScreen extends StatefulWidget {
  @override
  _CarListScreenState createState() => _CarListScreenState();
}

class _CarListScreenState extends State<CarListScreen> {
  late Future<List<Car>> cars;

  @override
  void initState() {
    super.initState();
    cars = fetchCars();
  }

  Future<List<Car>> fetchCars() async {
    final response = await http.get(Uri.parse('http://127.0.0.1:5000/api/cars'));

    if (response.statusCode == 200) {
      List data = json.decode(response.body);
      return data.map((json) => Car.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load cars');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Car Listings')),
      body: FutureBuilder<List<Car>>(
        future: cars,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final car = snapshot.data![index];
                return ListTile(
                  leading: car.imageUrl != null
                      ? Image.network(car.imageUrl!, width: 50, height: 50, fit: BoxFit.cover)
                      : Icon(Icons.directions_car),
                  title: Text(car.title),
                  subtitle: Text('${car.model} - \$${car.price.toStringAsFixed(0)}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => CarDetailScreen(car: car)),
                  ),
                );
              },
            );
          } else if (snapshot.hasError) {
            return Center(child: Text('Error loading cars: ${snapshot.error}'));
          }

          return Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

// Detail Screen
class CarDetailScreen extends StatelessWidget {
  final Car car;

  CarDetailScreen({required this.car});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(car.title)),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            car.imageUrl != null
                ? Image.network(car.imageUrl!)
                : Icon(Icons.directions_car, size: 100),
            SizedBox(height: 16),
            Text('Model: ${car.model}', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('Price: \$${car.price.toStringAsFixed(0)}', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
