## Android release quickstart

1. Create a keystore (one time):
```
keytool -genkey -v -keystore release-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Create `signing.properties` in the project root:
```
STORE_FILE=/absolute/path/to/release-keystore.jks
STORE_PASSWORD=your_store_password
KEY_ALIAS=upload
KEY_PASSWORD=your_key_password
```

3. In `android/app/build.gradle.kts`, uncomment the signing block to use `releaseConfig` and enable minify for release.

4. Build a signed release:
```
flutter build apk --flavor prod --release
```

5. For Google Play App Bundle:
```
flutter build appbundle --flavor prod --release
```

Use `--flavor dev` or `--flavor stage` for other environments.

# Car Listings App - Complete Backend & Frontend System

A comprehensive car listing application with real-time chat, notifications, user authentication, and admin dashboard.

## 🚀 Features

### Backend Features
- **Secure Authentication**: JWT-based authentication with password hashing
- **User Management**: Registration, login, profile management, email verification
- **Car Listings**: Full CRUD operations for car listings with image/video uploads
- **Real-time Chat**: WebSocket-based messaging between buyers and sellers
- **Notifications**: Push notifications and in-app notifications
- **Admin Dashboard**: Complete admin panel for user and content management
- **File Uploads**: Secure image and video upload handling
- **Database**: SQLAlchemy ORM with SQLite/PostgreSQL support
- **API**: RESTful API with comprehensive endpoints

### Frontend Features (Flutter)
- **Cross-platform**: Works on Android and iOS
- **Dark/Light Mode**: Theme switching with persistence
- **Real-time Updates**: Live chat and notifications
- **Image/Video Support**: Upload and display car media
- **User Authentication**: Complete auth flow with validation
- **Responsive Design**: Modern UI with smooth animations
- **Multi-language**: English, Arabic, and Kurdish support

## Listings not loading?

If the app shows "Loading listings..." forever or "Failed to load listings":

1. **Start both servers** (from repo root):
   - Windows: `.\start_servers.ps1`
   - Or manually: start **kk** on port **5000** (`python -m kk.app_new`), then **proxy** on **5003** (`python backend/server.py` from repo root; needs `backend/env.local` with `PORT=5003` and `LISTINGS_API_BASE=http://127.0.0.1:5000`).

2. **Check API URL**: The app calls `http://<API_BASE>/api/cars`. Default is `http://192.168.1.7:5003`. Your PC must be reachable at that IP:
   - On PC: run `ipconfig` (Windows) and use the IPv4 address of your Wi‑Fi adapter. If your IP changes, rebuild with `--dart-define=API_BASE=http://YOUR_IP:5003` or set that in Codemagic env vars.

3. **Same network**: Phone/emulator and PC must be on the same Wi‑Fi. Emulator: use `10.0.2.2:5003` (Android) or `localhost:5003` (iOS sim) and build with that as `API_BASE`.

4. **Quick test**: On the PC, open a browser: `http://127.0.0.1:5003/health` should show `{"status":"ok"}` and `http://127.0.0.1:5003/api/cars` should return JSON with `"cars": [...]`. If `/api/cars` returns 500, the kk DB may need the User table columns (e.g. `is_verified`, `is_active`); the app adds them on startup.

5. **Firewall**: Allow inbound TCP on ports **5000** and **5003** for your local network (or temporarily disable firewall to test).

## Production (public internet) deployment notes

If you deploy the backend to the public internet, do **not** run it in debug mode and do **not** rely on development defaults.

- **Set required environment variables** (at minimum):
  - `APP_ENV=production`
  - `SECRET_KEY=<long-random>`
  - `JWT_SECRET_KEY=<long-random>`
  - `DATABASE_URL=<postgres://...>` (recommended) or `DB_PATH=<path-to-sqlite>`
- **CORS (browser clients only)**:
  - Set `CORS_ORIGINS=https://yourdomain.com,https://admin.yourdomain.com`
  - In production, wildcard CORS is disabled by default.
- **HTTPS**:
  - Put the backend behind a reverse proxy (nginx/Caddy) with HTTPS. Do not send auth tokens over plain HTTP.
- **Dev/debug endpoints**:
  - Dev endpoints like `/dev/reinit`, `/dev/seed`, `/debug/info`, and dev OTP responses are removed/disabled for safety.

## Repo hygiene

- Local databases and uploads are ignored (see `.gitignore`). If you previously committed `*.db` files, they have been removed from tracking to avoid shipping private/local data.

## 📋 Requirements

### Backend Requirements
- Python 3.8+
- Flask 3.0+
- SQLAlchemy
- Redis (optional, for caching)
- Email service (Gmail, SendGrid, etc.)
- Firebase (for push notifications)

### Frontend Requirements
- Flutter 3.0+
- Dart 3.0+
- Android Studio / Xcode
- Firebase project (for push notifications)

## 🛠️ Installation & Setup

### Backend Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd car_listing_app
   ```

2. **Navigate to backend directory**
   ```bash
   cd kk
   ```

3. **Create virtual environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

4. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

5. **Run setup script**
   ```bash
   python setup_backend.py
   ```

6. **Update environment variables**
   Edit the `.env` file with your configuration:
   ```env
   # Email Configuration
   MAIL_USERNAME=your-email@gmail.com
   MAIL_PASSWORD=your-app-password
   
   # Firebase Configuration
   FIREBASE_SERVER_KEY=your-firebase-server-key
   FIREBASE_PROJECT_ID=your-firebase-project-id
   ```

7. **Start the backend server**
   ```bash
   python app_new.py
   ```

The backend will be available at `http://localhost:5000`

### Frontend Setup (Flutter)

1. **Navigate to Flutter directory**
   ```bash
   cd ..  # Go back to root directory
   ```

2. **Install Flutter dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase (Optional)**
   - Create a Firebase project
   - Add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Update Firebase configuration in the app

4. **Run the Flutter app**
   ```bash
   flutter run
   ```

## 📱 API Endpoints

### Authentication
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `POST /api/auth/logout` - User logout
- `POST /api/auth/refresh` - Refresh access token
- `POST /api/auth/forgot-password` - Request password reset
- `POST /api/auth/reset-password` - Reset password
- `POST /api/auth/verify-email` - Verify email address

### User Management
- `GET /api/user/profile` - Get user profile
- `PUT /api/user/profile` - Update user profile
- `POST /api/user/upload-profile-picture` - Upload profile picture
- `GET /api/user/favorites` - Get user's favorite cars
- `POST /api/cars/{car_id}/favorite` - Toggle favorite status

### Car Listings
- `GET /api/cars` - Get all cars (with filtering)
- `GET /api/cars/{car_id}` - Get single car
- `POST /api/cars` - Create new car listing
- `PUT /api/cars/{car_id}` - Update car listing
- `DELETE /api/cars/{car_id}` - Delete car listing
- `POST /api/cars/{car_id}/images` - Upload car images
- `POST /api/cars/{car_id}/videos` - Upload car videos

### Admin Endpoints
- `GET /api/admin/dashboard` - Get dashboard statistics
- `GET /api/admin/users` - Get all users
- `GET /api/admin/cars` - Get all cars
- `GET /api/admin/messages` - Get all messages
- `GET /api/admin/notifications` - Get all notifications
- `POST /api/admin/send-notification` - Send notification to users

## 🔧 Configuration

### Backend Configuration

The backend uses environment variables for configuration. Key settings:

```env
# Security
SECRET_KEY=your-secret-key
JWT_SECRET_KEY=your-jwt-secret

# Database
DATABASE_URL=sqlite:///car_listings.db

# Email
MAIL_SERVER=smtp.gmail.com
MAIL_USERNAME=your-email@gmail.com
MAIL_PASSWORD=your-app-password

# Firebase
FIREBASE_SERVER_KEY=your-firebase-server-key
FIREBASE_PROJECT_ID=your-firebase-project-id
```

### Frontend Configuration

Update the API base URL in `lib/services/api_service.dart`:

```dart
static const String baseUrl = 'http://your-backend-url:5000/api';
```

## 🗄️ Database Schema

### Users Table
- `id` - Primary key
- `public_id` - Public identifier
- `username` - Unique username
- `email` - Unique email
- `password_hash` - Hashed password
- `first_name`, `last_name` - User names
- `phone_number` - Phone number
- `profile_picture` - Profile image URL
- `is_verified` - Email verification status
- `is_active` - Account status
- `is_admin` - Admin privileges

### Cars Table
- `id` - Primary key
- `public_id` - Public identifier
- `seller_id` - Foreign key to users
- `brand`, `model`, `year` - Car details
- `mileage`, `price` - Car specifications
- `engine_type`, `transmission`, `drive_type` - Technical specs
- `condition`, `body_type` - Car condition
- `location` - Car location
- `description` - Car description
- `is_active` - Listing status

### Messages Table
- `id` - Primary key
- `sender_id`, `receiver_id` - User references
- `car_id` - Car reference
- `content` - Message content
- `message_type` - Message type
- `is_read` - Read status
- `created_at` - Timestamp

## 🔐 Security Features

- **Password Hashing**: bcrypt with salt rounds
- **JWT Authentication**: Secure token-based auth
- **Input Validation**: Comprehensive input sanitization
- **File Upload Security**: File type and size validation
- **Rate Limiting**: API rate limiting
- **CORS Protection**: Cross-origin request handling
- **SQL Injection Protection**: SQLAlchemy ORM protection

## 📊 Admin Dashboard

The admin dashboard provides:

- **User Management**: View, edit, delete users
- **Content Moderation**: Manage car listings
- **Analytics**: User actions and statistics
- **Notifications**: Send system-wide notifications
- **Message Monitoring**: View chat messages
- **System Statistics**: Platform usage metrics

Access the admin dashboard at: `http://localhost:5000/api/admin/dashboard`

Default admin credentials:
- Username: `admin`
- Password: `admin123`

## 🔔 Real-time Features

### WebSocket Events
- `connect` - Client connection
- `join_chat` - Join car chat room
- `send_message` - Send chat message
- `new_message` - Receive new message
- `new_notification` - Receive notification

### Push Notifications
- New messages
- New listings matching preferences
- Updates on favorite listings
- System notifications

## 🧪 Testing

### Backend Testing
```bash
# Run backend tests
python -m pytest tests/

# Run with coverage
python -m pytest --cov=app tests/
```

### Frontend Testing
```bash
# Run Flutter tests
flutter test

# Run integration tests
flutter drive --target=test_driver/app.dart
```

## 🚀 Deployment

### Backend Deployment

1. **Production Environment**
   ```bash
   export FLASK_ENV=production
   export DATABASE_URL=postgresql://user:pass@host:port/db
   ```

2. **Using Gunicorn**
   ```bash
   gunicorn -w 4 -b 0.0.0.0:5000 app_new:app
   ```

3. **Using Docker**
   ```bash
   docker build -t car-listings-backend .
   docker run -p 5000:5000 car-listings-backend
   ```

### Frontend Deployment

1. **Android**
   ```bash
   flutter build apk --release
   ```

2. **iOS**
   ```bash
   flutter build ios --release
   ```

3. **Web**
   ```bash
   flutter build web --release
   ```

## 📝 Development

### Adding New Features

1. **Backend**: Add new models, routes, and services
2. **Frontend**: Create new pages and services
3. **Database**: Run migrations for schema changes
4. **Testing**: Add tests for new functionality

### Code Structure

```
car_listing_app/
├── kk/                          # Backend (Flask)
│   ├── app_new.py              # Main Flask app
│   ├── models.py               # Database models
│   ├── auth.py                 # Authentication utilities
│   ├── admin_routes.py         # Admin endpoints
│   ├── config.py               # Configuration
│   ├── requirements.txt        # Python dependencies
│   └── setup_backend.py        # Setup script
├── lib/                        # Frontend (Flutter)
│   ├── main.dart              # Main Flutter app
│   ├── services/              # API services
│   ├── pages/                 # App pages
│   └── theme_provider.dart    # Theme management
└── README.md                  # This file
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support and questions:
- Create an issue in the repository
- Check the documentation
- Review the API endpoints

## 🔄 Updates

### Version 1.0.0
- Initial release with complete backend and frontend
- User authentication and management
- Car listing system
- Real-time chat
- Push notifications
- Admin dashboard
- Dark/light mode support
- Multi-language support

---

**Note**: This is a comprehensive car listing application with enterprise-level features. Make sure to configure all environment variables and test thoroughly before deploying to production.