import os

# List of expected brand IDs (from your JS brand list)
expected_brand_ids = [
    'abarth', 'acura', 'alfa-romeo', 'alpina', 'aston-martin', 'audi', 'baic', 'baojun', 'bentley', 'bestune', 'bmw',
    'brabus', 'bugatti', 'buick', 'byd-company', 'byd', 'cadillac', 'changan-croup', 'changan', 'chery-automobile',
    'chery', 'chevrolet', 'chrysler', 'citroen', 'dacia', 'daewoo', 'datsun', 'dodge', 'dongfeng-motor', 'ds',
    'faw-jiefang', 'faw', 'ferrari', 'fiat', 'ford', 'foton', 'gac', 'geely-zgh', 'genesis', 'gmc',
    'great-wall-motors', 'great-wall', 'haval', 'honda', 'hongqi', 'hyundai', 'infiniti', 'iran-khodro', 'isuzu',
    'jac-motors', 'jac-trucks', 'jaguar', 'jeep', 'kia', 'koenigsegg', 'ktm', 'lada', 'lamborghini', 'lancia',
    'land-rover', 'leapmotor', 'lexus', 'li-auto', 'liauto', 'lincoln', 'lixiang', 'lucid', 'mahindra', 'man',
    'mansory', 'maserati', 'mazda', 'mclaren', 'mercedes-benz', 'mg', 'mini', 'mitsubishi', 'nio', 'nissan',
    'opel', 'pagani', 'perodua', 'peugeot', 'polestar', 'porsche', 'proton', 'ram', 'renault', 'rivian', 'roewe',
    'rolls-royce', 'saic', 'seat', 'skoda', 'smart', 'ssangyong', 'subaru', 'suzuki', 'tata', 'tesla', 'toyota',
    'vauxhall', 'vinfast', 'volkswagen', 'volvo', 'wuling', 'xpeng', 'zaz'
]

# Change to check the correct directory used by the frontend
logo_dir = os.path.join(os.path.dirname(__file__), 'static', 'images', 'brands')
expected_files = set(f"{brand_id}.png" for brand_id in expected_brand_ids)
actual_files = set(f for f in os.listdir(logo_dir) if f.lower().endswith('.png'))

missing = expected_files - actual_files
extra = actual_files - expected_files

print("Missing logo files:")
for f in sorted(missing):
    print(f"  {f}")

if extra:
    print("\nExtra logo files (not matched to any brand ID):")
    for f in sorted(extra):
        print(f"  {f}") 