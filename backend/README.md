# Watermarkly License Plate Blurring Backend (Flask)

Production-ready Flask backend that proxies images to Watermarkly Blur API (license plates only), returns the blurred image, and keeps the API key server-side.

## Features
- Single upload: `POST /blur-license-plate` → returns blurred image bytes
- Logs uploads, job outcomes, and errors
- No API key exposure to clients

## Requirements
- Python 3.10+
- Watermarkly API key (`WATERMARKLY_API_KEY`) — trial or live works the same

## Setup

```bash
cd backend
python -m venv .venv
.\.venv\Scripts\activate    # Windows PowerShell
pip install -r requirements.txt
```

Create a `.env` file alongside `server.py` (or use `env.local`):

```
WATERMARKLY_API_KEY=trial_xxx
# PORT=5000
```

## Run (development)

```bash
cd backend
.\.venv\Scripts\activate
set FLASK_ENV=production
python server.py
```

Server will listen on `http://0.0.0.0:5000` by default.

To run with a WSGI server in production, point to `backend.server:create_app`.

## API

### POST /blur-license-plate
- Content-Type: multipart/form-data
- Field: `image` (also accepts `file` or `upload`) → single image file
- Response: blurred image bytes (`image/jpeg` or matching original when possible)

Example (PowerShell):
```powershell
Invoke-WebRequest -Uri http://localhost:5000/blur-license-plate -Method Post -Form @{ image = Get-Item "C:\path\plate.jpg" } -OutFile blurred.jpg
```

## Flutter Mobile Client Example

Add dependency:
```yaml
dependencies:
  http: ^1.2.2
  path: ^1.9.0
```

Single-image blur:
```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

Future<Uint8List> blurSingleImage(File image) async {
  final uri = Uri.parse('http://<YOUR_SERVER_IP>:5000/blur-license-plate');
  final req = http.MultipartRequest('POST', uri);
  final stream = http.ByteStream(image.openRead());
  final length = await image.length();
  final filename = p.basename(image.path);
  req.files.add(http.MultipartFile('image', stream, length, filename: filename));
  final resp = await http.Response.fromStream(await req.send());
  if (resp.statusCode != 200) {
    throw Exception('Blur failed: ${resp.statusCode} ${resp.body}');
  }
  return resp.bodyBytes;
}
```

Notes:
- Never embed `WATERMARKLY_API_KEY` in the app; only the backend has it.
- Use a trusted connection to your backend (HTTPS in production).

## Logging
- Server logs uploads and errors.

## Troubleshooting
- 403: Check `WATERMARKLY_API_KEY` validity.
- 429: Trial/plan rate limit exceeded; the backend retries once automatically.
- 5xx from backend: See server logs for upstream error details.


