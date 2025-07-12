# FIB Payment Integration

This document describes the First Iraqi Bank (FIB) payment integration implemented in the car listings application.

## Overview

The FIB payment integration allows users to purchase cars through secure bank transfers using First Iraqi Bank's payment gateway. The system includes:

- Payment initiation and processing
- Secure payment gateway simulation
- Payment status tracking
- Transaction history
- Webhook handling for payment confirmations

## Features

### 1. Payment Models

#### Payment Model
- `id`: Primary key
- `payment_id`: Unique FIB payment identifier
- `car_id`: Associated car listing
- `buyer_id`: User making the purchase
- `seller_id`: User selling the car
- `amount`: Payment amount
- `currency`: Payment currency (default: USD)
- `status`: Payment status (pending, completed, failed, cancelled)
- `payment_method`: Payment method (default: fib)
- `transaction_reference`: FIB transaction reference
- `created_at`: Payment creation timestamp
- `updated_at`: Last update timestamp

#### PaymentTransaction Model
- `id`: Primary key
- `payment_id`: Associated payment
- `transaction_type`: Transaction type (init, callback, webhook)
- `fib_transaction_id`: FIB transaction ID
- `amount`: Transaction amount
- `status`: Transaction status
- `response_data`: JSON response from FIB
- `created_at`: Transaction timestamp

### 2. Payment Flow

1. **Payment Initiation**
   - User clicks "Buy Now" on car detail page
   - System validates user is not the seller
   - Payment record is created with pending status
   - User is redirected to payment gateway

2. **Payment Gateway**
   - Simulated FIB payment interface
   - Collects payment information (account number, card details, OTP)
   - Validates payment data
   - Processes payment simulation

3. **Payment Completion**
   - Payment status updated to completed
   - Transaction reference generated
   - User redirected to success page
   - Seller notified of successful payment

4. **Payment Tracking**
   - Users can view payment history
   - Filter payments by status, type, and date
   - View detailed payment information

### 3. Routes

#### Payment Routes
- `GET/POST /payment/initiate/<car_id>`: Initiate payment for a car
- `GET/POST /payment/gateway/<payment_id>`: Payment gateway interface
- `POST /payment/callback`: FIB webhook endpoint
- `GET /payment/success/<payment_id>`: Payment success page
- `GET /payment/cancelled/<payment_id>`: Payment cancelled page
- `GET /payment/history`: User's payment history
- `GET /api/payment/status/<payment_id>`: Payment status API

### 4. Templates

#### Payment Templates
- `payment_initiate.html`: Payment initiation page
- `payment_gateway.html`: FIB payment gateway simulation
- `payment_success.html`: Payment success confirmation
- `payment_cancelled.html`: Payment cancellation page
- `payment_history.html`: Payment history with filtering

### 5. Configuration

#### FIB Configuration
```python
FIB_CONFIG = {
    'merchant_id': os.environ.get('FIB_MERCHANT_ID', 'your_merchant_id'),
    'api_key': os.environ.get('FIB_API_KEY', 'your_api_key'),
    'secret_key': os.environ.get('FIB_SECRET_KEY', 'your_secret_key'),
    'base_url': os.environ.get('FIB_BASE_URL', 'https://api.fib.com'),
    'callback_url': os.environ.get('FIB_CALLBACK_URL', 'https://yourdomain.com/payment/callback'),
    'return_url': os.environ.get('FIB_RETURN_URL', 'https://yourdomain.com/payment/return')
}
```

#### Environment Variables
- `FIB_MERCHANT_ID`: Your FIB merchant ID
- `FIB_API_KEY`: Your FIB API key
- `FIB_SECRET_KEY`: Your FIB secret key
- `FIB_BASE_URL`: FIB API base URL
- `FIB_CALLBACK_URL`: Webhook callback URL
- `FIB_RETURN_URL`: Return URL after payment

### 6. Security Features

#### Signature Generation
- HMAC-SHA256 signature for API requests
- Secure data transmission
- Request validation

#### Payment Validation
- User authentication required
- Seller cannot buy their own car
- Payment amount validation
- Transaction status tracking

#### Data Protection
- Payment information not stored
- Encrypted communication
- Secure session handling

### 7. UI/UX Features

#### Payment Gateway
- Professional FIB branding
- Realistic payment form
- Input validation and formatting
- OTP simulation
- Security notices

#### Payment History
- Comprehensive payment tracking
- Filtering by status, type, and date
- Payment statistics
- Detailed payment information
- Action buttons for pending/cancelled payments

#### Responsive Design
- Mobile-friendly interface
- Consistent styling with main application
- Loading states and animations
- Error handling and user feedback

### 8. Testing

#### Test Scripts
- `test_payment_integration.py`: Tests payment creation and processing
- `create_test_users.py`: Creates test users
- `fix_car_users.py`: Associates cars with users

#### Test Data
- Test users: buyer_test, seller_test
- Sample car listings with prices
- Payment transactions
- Various payment statuses

### 9. Production Deployment

#### Requirements
1. **FIB Integration**
   - Register with First Iraqi Bank
   - Obtain merchant credentials
   - Set up webhook endpoints
   - Configure SSL certificates

2. **Environment Setup**
   - Set environment variables
   - Configure database
   - Set up logging
   - Enable HTTPS

3. **Monitoring**
   - Payment success/failure rates
   - Transaction processing times
   - Error logging and alerting
   - User feedback collection

### 10. API Integration

#### FIB API Endpoints
- Payment initiation
- Payment status checking
- Transaction verification
- Refund processing

#### Webhook Handling
- Payment confirmation
- Status updates
- Error notifications
- Security validation

### 11. Error Handling

#### Common Errors
- Insufficient funds
- Invalid card information
- Network timeouts
- Bank rejections
- System errors

#### Error Recovery
- Automatic retry mechanisms
- User notification
- Payment status updates
- Support contact information

### 12. Future Enhancements

#### Planned Features
- Multiple payment methods
- Installment payments
- Payment scheduling
- Refund processing
- Advanced reporting
- Mobile app integration

#### Security Improvements
- 3D Secure integration
- Fraud detection
- Risk assessment
- Compliance monitoring

## Usage

### For Users
1. Browse car listings
2. Click "Buy Now" on desired car
3. Review payment details
4. Complete payment through FIB gateway
5. Track payment status
6. Contact seller for vehicle transfer

### For Administrators
1. Monitor payment transactions
2. Handle payment disputes
3. Generate payment reports
4. Manage user accounts
5. Configure payment settings

## Support

For technical support or questions about the FIB payment integration:

- **Email**: support@carlistings.com
- **Phone**: +964 XXX XXX XXXX
- **Hours**: 9:00 AM - 6:00 PM (Iraq Time)

## Security Notice

- Never share your payment credentials
- Always verify the payment gateway URL
- Report suspicious activities immediately
- Keep your login credentials secure
- Enable two-factor authentication when available 