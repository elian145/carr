import sys
sys.path.append('kk')
from app_new import app

app.testing = True
with app.test_client() as c:
    r = c.get('/cars')
    print('status', r.status_code)
    print(r.data.decode('utf-8')[:400])
