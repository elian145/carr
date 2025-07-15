import os

brands = [
    'Toyota', 'Volkswagen', 'Ford', 'Honda', 'Hyundai', 'Nissan', 'Chevrolet', 'Kia', 'Mercedes-Benz', 'BMW', 'Audi', 'Lexus', 'Mazda', 'Subaru', 'Volvo', 'Jeep', 'RAM', 'GMC', 'Buick', 'Cadillac', 'Lincoln', 'Mitsubishi', 'Acura', 'Infiniti', 'Tesla', 'Mini', 'Porsche', 'Land Rover', 'Jaguar', 'Fiat', 'Renault', 'Peugeot', 'Citroën', 'Škoda', 'SEAT', 'Dacia', 'Chery', 'BYD', 'Great Wall', 'FAW', 'Roewe', 'Proton', 'Perodua', 'Tata', 'Mahindra', 'Lada', 'ZAZ', 'Daewoo', 'SsangYong', 'Changan', 'Haval', 'Wuling', 'Baojun', 'Nio', 'XPeng', 'Li Auto', 'VinFast', 'Ferrari', 'Lamborghini', 'Bentley', 'Rolls-Royce', 'Aston Martin', 'McLaren', 'Maserati', 'Bugatti', 'Pagani', 'Koenigsegg', 'Polestar', 'Rivian', 'Lucid', 'Alfa Romeo', 'Lancia', 'Abarth', 'Opel', 'DS', 'MAN', 'Iran Khodro', 'Genesis', 'Isuzu', 'Datsun', 'JAC Motors', 'JAC Trucks', 'KTM', 'Alpina', 'Brabus', 'Mansory', 'Bestune', 'Hongqi', 'Dongfeng', 'FAW Jiefang', 'Foton', 'Leapmotor', 'GAC', 'SAIC', 'MG', 'Vauxhall', 'Smart'
]

def normalize(brand):
    return (brand.lower()
        .replace(' ', '-')
        .replace('é', 'e')
        .replace('ö', 'o')
        .replace('ô', 'o')
        .replace('ü', 'u')
        .replace('ä', 'a')
        .replace('ã', 'a')
        .replace('å', 'a')
        .replace('ç', 'c')
        .replace('ñ', 'n')
        .replace('š', 's')
        .replace('ž', 'z')
        .replace('á', 'a')
        .replace('í', 'i')
        .replace('ó', 'o')
        .replace('ú', 'u')
        .replace('ý', 'y')
        .replace('ř', 'r')
        .replace('č', 'c')
        .replace('ě', 'e')
        .replace('Š', 's')
        .replace('Ž', 'z')
        .replace('Č', 'c')
        .replace('Ě', 'e')
        .replace('â', 'a')
        .replace('ê', 'e')
        .replace('î', 'i')
        .replace('ô', 'o')
        .replace('û', 'u')
        .replace('œ', 'oe')
        .replace('æ', 'ae')
        .replace('ß', 'ss')
    )

logo_dir = 'kk/static/uploads/car_brand_logos'
missing = []
for brand in brands:
    fname = normalize(brand) + '.png'
    if not os.path.isfile(os.path.join(logo_dir, fname)):
        missing.append((brand, fname))

print('Missing logo files:')
for brand, fname in missing:
    print(f'{brand}: {fname}') 