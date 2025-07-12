from app import app, db, Payment, PaymentTransaction, Car, User
from datetime import datetime
import uuid

def test_payment_integration():
    """Test the FIB payment integration"""
    with app.app_context():
        print("=== Testing FIB Payment Integration ===\n")
        
        # Check if we have cars and users
        cars = Car.query.all()
        users = User.query.all()
        
        print(f"Found {len(cars)} cars and {len(users)} users")
        
        if len(cars) == 0 or len(users) < 2:
            print("Need at least 1 car and 2 users to test payment integration")
            return
        
        # Get first car and two users
        car = cars[0]
        buyer = users[0]
        seller = users[1] if len(users) > 1 else users[0]
        
        print(f"Testing with:")
        print(f"  Car: {car.brand} {car.model} (${car.price})")
        print(f"  Buyer: {buyer.username}")
        print(f"  Seller: {seller.username}")
        
        # Create a test payment
        payment = Payment(
            payment_id=str(uuid.uuid4()),
            car_id=car.id,
            buyer_id=buyer.id,
            seller_id=seller.id,
            amount=car.price or 25000.0,
            currency='USD',
            status='pending'
        )
        
        db.session.add(payment)
        db.session.commit()
        
        print(f"\nCreated test payment:")
        print(f"  Payment ID: {payment.payment_id}")
        print(f"  Amount: ${payment.amount}")
        print(f"  Status: {payment.status}")
        
        # Create a test transaction
        transaction = PaymentTransaction(
            payment_id=payment.id,
            transaction_type='init',
            amount=payment.amount,
            status='pending',
            response_data='{"test": "data"}'
        )
        
        db.session.add(transaction)
        db.session.commit()
        
        print(f"\nCreated test transaction:")
        print(f"  Transaction ID: {transaction.id}")
        print(f"  Type: {transaction.transaction_type}")
        print(f"  Status: {transaction.status}")
        
        # Test payment status update
        payment.status = 'completed'
        payment.transaction_reference = f"FIB_TEST_{uuid.uuid4().hex[:16].upper()}"
        db.session.commit()
        
        print(f"\nUpdated payment status to: {payment.status}")
        print(f"Transaction reference: {payment.transaction_reference}")
        
        # Query payments
        all_payments = Payment.query.all()
        print(f"\nTotal payments in database: {len(all_payments)}")
        
        for p in all_payments:
            print(f"  - {p.payment_id[:8]}... | ${p.amount} | {p.status}")
        
        print("\n=== Payment Integration Test Complete ===")

if __name__ == '__main__':
    test_payment_integration() 