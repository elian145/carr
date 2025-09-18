from flask import Blueprint, request, jsonify, render_template
from flask_jwt_extended import jwt_required, get_jwt_identity
from models import db, User, Car, Message, Notification, UserAction
from auth import admin_required, get_current_user
import logging

admin_bp = Blueprint('admin', __name__, url_prefix='/api/admin')
logger = logging.getLogger(__name__)

@admin_bp.route('/dashboard', methods=['GET'])
@admin_required
def get_dashboard_stats():
    """Get admin dashboard statistics"""
    try:
        # Get basic statistics
        total_users = User.query.count()
        active_users = User.query.filter_by(is_active=True).count()
        total_cars = Car.query.count()
        active_cars = Car.query.filter_by(is_active=True).count()
        total_messages = Message.query.count()
        total_notifications = Notification.query.count()
        
        # Get recent activity
        recent_users = User.query.order_by(User.created_at.desc()).limit(10).all()
        recent_cars = Car.query.order_by(Car.created_at.desc()).limit(10).all()
        recent_messages = Message.query.order_by(Message.created_at.desc()).limit(10).all()
        
        # Get user actions summary
        user_actions = db.session.query(
            UserAction.action_type,
            db.func.count(UserAction.id).label('count')
        ).group_by(UserAction.action_type).all()
        
        return jsonify({
            'stats': {
                'total_users': total_users,
                'active_users': active_users,
                'total_cars': total_cars,
                'active_cars': active_cars,
                'total_messages': total_messages,
                'total_notifications': total_notifications
            },
            'recent_activity': {
                'users': [user.to_dict() for user in recent_users],
                'cars': [car.to_dict() for car in recent_cars],
                'messages': [message.to_dict() for message in recent_messages]
            },
            'user_actions': [{'action_type': action.action_type, 'count': action.count} for action in user_actions]
        }), 200
        
    except Exception as e:
        logger.error(f"Get dashboard stats error: {str(e)}")
        return jsonify({'message': 'Failed to get dashboard statistics'}), 500

@admin_bp.route('/users', methods=['GET'])
@admin_required
def get_users():
    """Get all users with pagination"""
    try:
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        search = request.args.get('search', '')
        
        query = User.query
        
        if search:
            query = query.filter(
                (User.username.ilike(f'%{search}%')) |
                (User.email.ilike(f'%{search}%')) |
                (User.first_name.ilike(f'%{search}%')) |
                (User.last_name.ilike(f'%{search}%'))
            )
        
        pagination = query.order_by(User.created_at.desc()).paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        users = [user.to_dict(include_private=True) for user in pagination.items]
        
        return jsonify({
            'users': users,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Get users error: {str(e)}")
        return jsonify({'message': 'Failed to get users'}), 500

@admin_bp.route('/users/<user_id>', methods=['GET'])
@admin_required
def get_user(user_id):
    """Get specific user details"""
    try:
        user = User.query.filter_by(public_id=user_id).first()
        if not user:
            return jsonify({'message': 'User not found'}), 404
        
        # Get user's cars
        cars = Car.query.filter_by(seller_id=user.id).all()
        
        # Get user's recent actions
        recent_actions = UserAction.query.filter_by(user_id=user.id).order_by(UserAction.created_at.desc()).limit(20).all()
        
        return jsonify({
            'user': user.to_dict(include_private=True),
            'cars': [car.to_dict() for car in cars],
            'recent_actions': [action.to_dict() for action in recent_actions]
        }), 200
        
    except Exception as e:
        logger.error(f"Get user error: {str(e)}")
        return jsonify({'message': 'Failed to get user'}), 500

@admin_bp.route('/users/<user_id>', methods=['PUT'])
@admin_required
def update_user(user_id):
    """Update user (admin only)"""
    try:
        user = User.query.filter_by(public_id=user_id).first()
        if not user:
            return jsonify({'message': 'User not found'}), 404
        
        data = request.get_json()
        
        # Update fields
        if 'is_active' in data:
            user.is_active = data['is_active']
        if 'is_verified' in data:
            user.is_verified = data['is_verified']
        if 'is_admin' in data:
            user.is_admin = data['is_admin']
        
        user.updated_at = datetime.utcnow()
        db.session.commit()
        
        return jsonify({
            'message': 'User updated successfully',
            'user': user.to_dict(include_private=True)
        }), 200
        
    except Exception as e:
        logger.error(f"Update user error: {str(e)}")
        return jsonify({'message': 'Failed to update user'}), 500

@admin_bp.route('/users/<user_id>', methods=['DELETE'])
@admin_required
def delete_user(user_id):
    """Delete user (admin only)"""
    try:
        current_admin = get_current_user()
        user = User.query.filter_by(public_id=user_id).first()
        
        if not user:
            return jsonify({'message': 'User not found'}), 404
        
        if user.id == current_admin.id:
            return jsonify({'message': 'Cannot delete your own account'}), 400
        
        # Soft delete - deactivate user
        user.is_active = False
        user.updated_at = datetime.utcnow()
        
        # Deactivate user's cars
        Car.query.filter_by(seller_id=user.id).update({'is_active': False})
        
        db.session.commit()
        
        return jsonify({'message': 'User deactivated successfully'}), 200
        
    except Exception as e:
        logger.error(f"Delete user error: {str(e)}")
        return jsonify({'message': 'Failed to delete user'}), 500

@admin_bp.route('/cars', methods=['GET'])
@admin_required
def get_all_cars():
    """Get all cars with admin details"""
    try:
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        search = request.args.get('search', '')
        status = request.args.get('status', 'all')  # all, active, inactive
        
        query = Car.query
        
        if search:
            query = query.filter(
                (Car.brand.ilike(f'%{search}%')) |
                (Car.model.ilike(f'%{search}%')) |
                (Car.location.ilike(f'%{search}%'))
            )
        
        if status == 'active':
            query = query.filter_by(is_active=True)
        elif status == 'inactive':
            query = query.filter_by(is_active=False)
        
        pagination = query.order_by(Car.created_at.desc()).paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        cars = [car.to_dict(include_private=True) for car in pagination.items]
        
        return jsonify({
            'cars': cars,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Get all cars error: {str(e)}")
        return jsonify({'message': 'Failed to get cars'}), 500

@admin_bp.route('/cars/<car_id>', methods=['PUT'])
@admin_required
def update_car_admin(car_id):
    """Update car (admin only)"""
    try:
        car = Car.query.filter_by(public_id=car_id).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404
        
        data = request.get_json()
        
        # Update fields
        if 'is_active' in data:
            car.is_active = data['is_active']
        if 'is_featured' in data:
            car.is_featured = data['is_featured']
        
        car.updated_at = datetime.utcnow()
        db.session.commit()
        
        return jsonify({
            'message': 'Car updated successfully',
            'car': car.to_dict(include_private=True)
        }), 200
        
    except Exception as e:
        logger.error(f"Update car admin error: {str(e)}")
        return jsonify({'message': 'Failed to update car'}), 500

@admin_bp.route('/cars/<car_id>', methods=['DELETE'])
@admin_required
def delete_car_admin(car_id):
    """Delete car (admin only)"""
    try:
        car = Car.query.filter_by(public_id=car_id).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404
        
        # Soft delete
        car.is_active = False
        car.updated_at = datetime.utcnow()
        db.session.commit()
        
        return jsonify({'message': 'Car deleted successfully'}), 200
        
    except Exception as e:
        logger.error(f"Delete car admin error: {str(e)}")
        return jsonify({'message': 'Failed to delete car'}), 500

@admin_bp.route('/messages', methods=['GET'])
@admin_required
def get_messages():
    """Get all messages"""
    try:
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 50, type=int)
        
        pagination = Message.query.order_by(Message.created_at.desc()).paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        messages = [message.to_dict() for message in pagination.items]
        
        return jsonify({
            'messages': messages,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Get messages error: {str(e)}")
        return jsonify({'message': 'Failed to get messages'}), 500

@admin_bp.route('/notifications', methods=['GET'])
@admin_required
def get_notifications():
    """Get all notifications"""
    try:
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 50, type=int)
        
        pagination = Notification.query.order_by(Notification.created_at.desc()).paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        notifications = [notification.to_dict() for notification in pagination.items]
        
        return jsonify({
            'notifications': notifications,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Get notifications error: {str(e)}")
        return jsonify({'message': 'Failed to get notifications'}), 500

@admin_bp.route('/user-actions', methods=['GET'])
@admin_required
def get_user_actions():
    """Get user actions for analytics"""
    try:
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 100, type=int)
        action_type = request.args.get('action_type', '')
        user_id = request.args.get('user_id', '')
        
        query = UserAction.query
        
        if action_type:
            query = query.filter_by(action_type=action_type)
        
        if user_id:
            user = User.query.filter_by(public_id=user_id).first()
            if user:
                query = query.filter_by(user_id=user.id)
        
        pagination = query.order_by(UserAction.created_at.desc()).paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        actions = [action.to_dict() for action in pagination.items]
        
        return jsonify({
            'actions': actions,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Get user actions error: {str(e)}")
        return jsonify({'message': 'Failed to get user actions'}), 500

@admin_bp.route('/send-notification', methods=['POST'])
@admin_required
def send_notification():
    """Send notification to all users or specific user"""
    try:
        data = request.get_json()
        
        title = data.get('title')
        message = data.get('message')
        notification_type = data.get('notification_type', 'admin')
        target_user_id = data.get('target_user_id')
        
        if not title or not message:
            return jsonify({'message': 'Title and message are required'}), 400
        
        if target_user_id:
            # Send to specific user
            user = User.query.filter_by(public_id=target_user_id).first()
            if not user:
                return jsonify({'message': 'User not found'}), 404
            
            from app_new import create_notification
            create_notification(user, title, message, notification_type)
            
            return jsonify({'message': 'Notification sent successfully'}), 200
        else:
            # Send to all users
            users = User.query.filter_by(is_active=True).all()
            
            for user in users:
                from app_new import create_notification
                create_notification(user, title, message, notification_type)
            
            return jsonify({'message': f'Notification sent to {len(users)} users'}), 200
        
    except Exception as e:
        logger.error(f"Send notification error: {str(e)}")
        return jsonify({'message': 'Failed to send notification'}), 500
