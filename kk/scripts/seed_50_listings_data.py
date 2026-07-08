"""Curated listing data for seed_50_listings.py (50 realistic cars, Iraq market)."""

from __future__ import annotations

# Validated Unsplash car photos (free to use per Unsplash License).
IMAGE_POOL = [
    "https://images.unsplash.com/photo-1542362567-b07e54358753?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1503376780353-7e6692767b70?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1618843479313-40f8afb4b4d8?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1617531653332-bd46c24f2068?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1502877338535-766e1452684a?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1770563466851-5f1b4b22d660?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1774854133843-5b6563caaf2a?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1776610149018-7690dbf90b05?auto=format&fit=crop&w=1200&q=80",
    "https://images.unsplash.com/photo-1768969030762-c1ceb8287414?auto=format&fit=crop&w=1200&q=80",
]

CITIES = [
    "baghdad",
    "basra",
    "erbil",
    "najaf",
    "karbala",
    "kirkuk",
    "mosul",
    "sulaymaniyah",
    "dohuk",
    "diyala",
]

REGION_SPECS = ["gcc", "iraq", "us", "eu", "korea"]

# 50 listings with realistic specs (prices in USD, mileage in km).
LISTINGS: list[dict] = [
    {
        "brand": "toyota", "model": "Camry", "trim": "XSE", "year": 2022, "price": 28500, "mileage": 42000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "white",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "GCC-spec Toyota Camry XSE. Full dealer service history, non-smoker, accident-free.",
    },
    {
        "brand": "toyota", "model": "Land Cruiser", "trim": "VXR", "year": 2021, "price": 72000, "mileage": 58000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "black",
        "body_type": "suv", "seating": 7, "drive_type": "4wd", "cylinder_count": 8, "engine_size": 5.7,
        "description": "Land Cruiser VXR with cooled seats, radar cruise, and fresh tires. Ideal for long trips.",
    },
    {
        "brand": "toyota", "model": "Corolla", "trim": "SE", "year": 2023, "price": 21500, "mileage": 18000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "silver",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "Low-mileage Corolla SE with Toyota Safety Sense. Excellent fuel economy.",
    },
    {
        "brand": "toyota", "model": "RAV4", "trim": "XLE", "year": 2022, "price": 33500, "mileage": 35000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "gray",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "RAV4 XLE AWD, panoramic roof, blind-spot monitor. One owner.",
    },
    {
        "brand": "toyota", "model": "Hilux", "trim": "SR5", "year": 2020, "price": 31000, "mileage": 89000,
        "condition": "used", "transmission": "automatic", "fuel_type": "diesel", "color": "white",
        "body_type": "pickup", "seating": 5, "drive_type": "4wd", "cylinder_count": 4, "engine_size": 2.8,
        "description": "Reliable Hilux diesel pickup. Bed liner, tow package, recently serviced.",
    },
    {
        "brand": "honda", "model": "Civic", "trim": "Sport", "year": 2023, "price": 24800, "mileage": 22000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "blue",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 1.5,
        "description": "Sport trim Civic with turbo engine. Clean title, all keys and manuals included.",
    },
    {
        "brand": "honda", "model": "CR-V", "trim": "EX-L", "year": 2022, "price": 31800, "mileage": 41000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "black",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 1.5,
        "description": "CR-V EX-L with leather, power tailgate, and Honda Sensing package.",
    },
    {
        "brand": "honda", "model": "Accord", "trim": "Touring", "year": 2021, "price": 29500, "mileage": 52000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "red",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 1.5,
        "description": "Top-spec Accord Touring with navigation and heated rear seats.",
    },
    {
        "brand": "nissan", "model": "Patrol", "trim": "Platinum", "year": 2020, "price": 65000, "mileage": 72000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "white",
        "body_type": "suv", "seating": 7, "drive_type": "4wd", "cylinder_count": 8, "engine_size": 5.6,
        "description": "Nissan Patrol Platinum with captain chairs and 360 camera.",
    },
    {
        "brand": "nissan", "model": "Altima", "trim": "SV", "year": 2022, "price": 22800, "mileage": 38000,
        "condition": "used", "transmission": "cvt", "fuel_type": "gasoline", "color": "silver",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "Comfortable daily driver with ProPILOT assist and remote start.",
    },
    {
        "brand": "nissan", "model": "X-Trail", "trim": "SL", "year": 2023, "price": 30200, "mileage": 25000,
        "condition": "used", "transmission": "cvt", "fuel_type": "gasoline", "color": "gray",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "Family SUV with third-row option removed for extra cargo space.",
    },
    {
        "brand": "hyundai", "model": "Sonata", "trim": "Limited", "year": 2022, "price": 24200, "mileage": 44000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "blue",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "Sonata Limited with digital key and Bose audio. Warranty transferable.",
    },
    {
        "brand": "hyundai", "model": "Tucson", "trim": "SEL", "year": 2023, "price": 27800, "mileage": 19000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "white",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "Nearly new Tucson with panoramic sunroof and wireless CarPlay.",
    },
    {
        "brand": "hyundai", "model": "Elantra", "trim": "N Line", "year": 2024, "price": 26500, "mileage": 8000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "black",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 1.6,
        "description": "Sporty Elantra N Line with DCT and factory warranty remaining.",
    },
    {
        "brand": "kia", "model": "Sportage", "trim": "EX", "year": 2023, "price": 28900, "mileage": 28000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "gray",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "Kia Sportage EX with highway driving assist and ventilated seats.",
    },
    {
        "brand": "kia", "model": "K5", "trim": "GT-Line", "year": 2022, "price": 25500, "mileage": 36000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "red",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 1.6,
        "description": "Sharp K5 GT-Line with red interior accents. Non-smoker vehicle.",
    },
    {
        "brand": "kia", "model": "Sorento", "trim": "SX", "year": 2021, "price": 32400, "mileage": 55000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "silver",
        "body_type": "suv", "seating": 7, "drive_type": "awd", "cylinder_count": 6, "engine_size": 3.5,
        "description": "Three-row Sorento SX with tow hitch and new brakes.",
    },
    {
        "brand": "bmw", "model": "X5", "trim": "xDrive40i", "year": 2021, "price": 58000, "mileage": 48000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "black",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 6, "engine_size": 3.0,
        "description": "BMW X5 with M Sport package, harman/kardon sound, and service records.",
    },
    {
        "brand": "bmw", "model": "3 Series", "trim": "330i", "year": 2022, "price": 42000, "mileage": 32000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "white",
        "body_type": "sedan", "seating": 5, "drive_type": "rwd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "330i with live cockpit pro and adaptive suspension.",
    },
    {
        "brand": "bmw", "model": "X3", "trim": "xDrive30i", "year": 2023, "price": 48500, "mileage": 15000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "blue",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "Compact luxury SUV, parking assistant plus, panoramic roof.",
    },
    {
        "brand": "mercedes-benz", "model": "C-Class", "trim": "C300", "year": 2022, "price": 46500, "mileage": 29000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "silver",
        "body_type": "sedan", "seating": 5, "drive_type": "rwd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "Mercedes C300 AMG line exterior, Burmester audio, clean GCC specs.",
    },
    {
        "brand": "mercedes-benz", "model": "GLC", "trim": "300", "year": 2021, "price": 49800, "mileage": 44000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "black",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "GLC 300 with 360 camera and MBUX infotainment.",
    },
    {
        "brand": "mercedes-benz", "model": "E-Class", "trim": "E350", "year": 2020, "price": 52000, "mileage": 62000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "gray",
        "body_type": "sedan", "seating": 5, "drive_type": "rwd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "Executive sedan with air suspension and rear sunshades.",
    },
    {
        "brand": "audi", "model": "Q5", "trim": "Premium Plus", "year": 2022, "price": 47200, "mileage": 37000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "white",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "Audi Q5 with virtual cockpit and matrix LED headlights.",
    },
    {
        "brand": "audi", "model": "A4", "trim": "Premium Plus", "year": 2023, "price": 43800, "mileage": 21000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "black",
        "body_type": "sedan", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "Quattro AWD sedan with sport seats and Bang & Olufsen sound.",
    },
    {
        "brand": "audi", "model": "A6", "trim": "45 TFSI", "year": 2021, "price": 49500, "mileage": 50000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "blue",
        "body_type": "sedan", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "A6 with adaptive cruise and massage seats.",
    },
    {
        "brand": "ford", "model": "Explorer", "trim": "Limited", "year": 2022, "price": 38500, "mileage": 45000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "white",
        "body_type": "suv", "seating": 7, "drive_type": "awd", "cylinder_count": 6, "engine_size": 3.0,
        "description": "Large family SUV with captain chairs and Co-Pilot360.",
    },
    {
        "brand": "ford", "model": "F-150", "trim": "XLT", "year": 2021, "price": 42000, "mileage": 68000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "red",
        "body_type": "pickup", "seating": 6, "drive_type": "4wd", "cylinder_count": 6, "engine_size": 3.5,
        "description": "F-150 XLT SuperCrew with bed cover and running boards.",
    },
    {
        "brand": "ford", "model": "Mustang", "trim": "GT", "year": 2020, "price": 39800, "mileage": 42000,
        "condition": "used", "transmission": "manual", "fuel_type": "gasoline", "color": "yellow",
        "body_type": "coupe", "seating": 4, "drive_type": "rwd", "cylinder_count": 8, "engine_size": 5.0,
        "description": "V8 Mustang GT manual. Performance pack, garage kept.",
    },
    {
        "brand": "chevrolet", "model": "Tahoe", "trim": "Premier", "year": 2021, "price": 55800, "mileage": 59000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "black",
        "body_type": "suv", "seating": 8, "drive_type": "4wd", "cylinder_count": 8, "engine_size": 5.3,
        "description": "Full-size Tahoe Premier with magnetic ride and rear entertainment.",
    },
    {
        "brand": "chevrolet", "model": "Malibu", "trim": "LT", "year": 2022, "price": 21800, "mileage": 40000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "silver",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 1.5,
        "description": "Economical Malibu LT with Apple CarPlay and backup camera.",
    },
    {
        "brand": "chevrolet", "model": "Silverado", "trim": "LT", "year": 2020, "price": 36500, "mileage": 95000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "white",
        "body_type": "pickup", "seating": 6, "drive_type": "4wd", "cylinder_count": 8, "engine_size": 5.3,
        "description": "Work-ready Silverado with tow mirrors and spray-in bedliner.",
    },
    {
        "brand": "gmc", "model": "Yukon", "trim": "Denali", "year": 2020, "price": 62000, "mileage": 71000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "white",
        "body_type": "suv", "seating": 7, "drive_type": "4wd", "cylinder_count": 8, "engine_size": 6.2,
        "description": "Yukon Denali with adaptive air suspension and premium interior.",
    },
    {
        "brand": "jeep", "model": "Wrangler", "trim": "Sahara", "year": 2022, "price": 44500, "mileage": 33000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "green",
        "body_type": "suv", "seating": 5, "drive_type": "4wd", "cylinder_count": 6, "engine_size": 3.6,
        "description": "Wrangler Sahara with hard top and upgraded all-terrain tires.",
    },
    {
        "brand": "jeep", "model": "Grand Cherokee", "trim": "Limited", "year": 2021, "price": 39800, "mileage": 47000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "gray",
        "body_type": "suv", "seating": 5, "drive_type": "4wd", "cylinder_count": 6, "engine_size": 3.6,
        "description": "Comfortable Grand Cherokee with leather and dual-pane sunroof.",
    },
    {
        "brand": "lexus", "model": "RX 350", "trim": "Luxury", "year": 2022, "price": 51200, "mileage": 31000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "pearl",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 6, "engine_size": 3.5,
        "description": "Lexus RX 350 with Mark Levinson audio and heads-up display.",
    },
    {
        "brand": "lexus", "model": "ES 350", "trim": "F Sport", "year": 2023, "price": 46800, "mileage": 14000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "black",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 6, "engine_size": 3.5,
        "description": "ES F Sport with adaptive variable suspension and red leather.",
    },
    {
        "brand": "mazda", "model": "CX-5", "trim": "Grand Touring", "year": 2022, "price": 27800, "mileage": 39000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "red",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "CX-5 Grand Touring with Bose speakers and power liftgate.",
    },
    {
        "brand": "mazda", "model": "Mazda3", "trim": "Premium", "year": 2023, "price": 24500, "mileage": 16000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "gray",
        "body_type": "sedan", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "Premium Mazda3 with leather and adaptive front lighting.",
    },
    {
        "brand": "mitsubishi", "model": "Pajero", "trim": "GLS", "year": 2019, "price": 28500, "mileage": 98000,
        "condition": "used", "transmission": "automatic", "fuel_type": "diesel", "color": "white",
        "body_type": "suv", "seating": 7, "drive_type": "4wd", "cylinder_count": 4, "engine_size": 3.2,
        "description": "Legendary Pajero diesel 4WD. Recently serviced transfer case and timing belt.",
    },
    {
        "brand": "mitsubishi", "model": "Outlander", "trim": "SEL", "year": 2023, "price": 26800, "mileage": 24000,
        "condition": "used", "transmission": "cvt", "fuel_type": "gasoline", "color": "blue",
        "body_type": "suv", "seating": 7, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "Three-row Outlander with driver assist and wireless charging.",
    },
    {
        "brand": "volkswagen", "model": "Tiguan", "trim": "SE", "year": 2022, "price": 29200, "mileage": 35000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "silver",
        "body_type": "suv", "seating": 7, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "VW Tiguan with digital cockpit and panoramic sunroof.",
    },
    {
        "brand": "volkswagen", "model": "Golf GTI", "trim": "Autobahn", "year": 2021, "price": 31500, "mileage": 38000,
        "condition": "used", "transmission": "manual", "fuel_type": "gasoline", "color": "white",
        "body_type": "hatchback", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 2.0,
        "description": "Hot hatch with DCC adaptive chassis and plaid seats.",
    },
    {
        "brand": "tesla", "model": "Model 3", "trim": "Long Range", "year": 2022, "price": 38500, "mileage": 42000,
        "condition": "used", "transmission": "automatic", "fuel_type": "electric", "color": "white",
        "body_type": "sedan", "seating": 5, "drive_type": "awd", "cylinder_count": None, "engine_size": None,
        "description": "Model 3 LR AWD with autopilot. Battery health report available.",
    },
    {
        "brand": "tesla", "model": "Model Y", "trim": "Performance", "year": 2023, "price": 52000, "mileage": 18000,
        "condition": "used", "transmission": "automatic", "fuel_type": "electric", "color": "black",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": None, "engine_size": None,
        "description": "Model Y Performance with 21-inch wheels and white interior.",
    },
    {
        "brand": "porsche", "model": "Cayenne", "trim": "S", "year": 2021, "price": 78000, "mileage": 36000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "gray",
        "body_type": "suv", "seating": 5, "drive_type": "awd", "cylinder_count": 6, "engine_size": 2.9,
        "description": "Cayenne S with air suspension and sport chrono package.",
    },
    {
        "brand": "range-rover", "model": "Sport", "trim": "HSE", "year": 2020, "price": 69000, "mileage": 65000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "black",
        "body_type": "suv", "seating": 5, "drive_type": "4wd", "cylinder_count": 6, "engine_size": 3.0,
        "description": "Range Rover Sport HSE with meridian sound and soft-close doors.",
    },
    {
        "brand": "dodge", "model": "Charger", "trim": "R/T", "year": 2020, "price": 35800, "mileage": 54000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "gray",
        "body_type": "sedan", "seating": 5, "drive_type": "rwd", "cylinder_count": 8, "engine_size": 5.7,
        "description": "American muscle sedan with HEMI V8. Well maintained.",
    },
    {
        "brand": "subaru", "model": "Outback", "trim": "Limited", "year": 2022, "price": 30200, "mileage": 37000,
        "condition": "used", "transmission": "cvt", "fuel_type": "gasoline", "color": "green",
        "body_type": "wagon", "seating": 5, "drive_type": "awd", "cylinder_count": 4, "engine_size": 2.5,
        "description": "Outback Limited with eyesight safety and roof rails.",
    },
    {
        "brand": "changan", "model": "CS75", "trim": "Plus", "year": 2023, "price": 19800, "mileage": 12000,
        "condition": "used", "transmission": "automatic", "fuel_type": "gasoline", "color": "white",
        "body_type": "suv", "seating": 5, "drive_type": "fwd", "cylinder_count": 4, "engine_size": 1.5,
        "description": "Popular Chinese SUV with large touchscreen and factory warranty.",
    },
]

assert len(LISTINGS) == 50, f"Expected 50 listings, got {len(LISTINGS)}"
