"""
SMS Service for sending password reset and verification codes.
Supports: Twilio, OTPIQ (Iraq SMS/WhatsApp), console (dev only).
"""

import os
import logging
from typing import Optional

import requests

logger = logging.getLogger(__name__)

OTPIQ_API_URL = "https://api.otpiq.com/api/sms"

def _app_env() -> str:
    return (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "development").strip().lower()

def _normalize_phone_otpiq(phone: str) -> str:
    """Normalize to digits only; ensure Iraq country code 964 if 11 digits starting with 7 or 0."""
    digits = "".join(c for c in (phone or "") if c.isdigit())
    if len(digits) == 11 and digits.startswith("7"):
        return "964" + digits
    if len(digits) == 11 and digits.startswith("0"):
        return "964" + digits[1:]
    if len(digits) >= 10 and len(digits) <= 15:
        return digits
    return digits

class SMSService:
    """SMS service for sending messages"""
    
    def __init__(self):
        self.provider = (os.environ.get('SMS_PROVIDER') or 'console').strip().lower()
        self.twilio_account_sid = os.environ.get('TWILIO_ACCOUNT_SID')
        self.twilio_auth_token = os.environ.get('TWILIO_AUTH_TOKEN')
        self.twilio_phone_number = os.environ.get('TWILIO_PHONE_NUMBER')
        self.otpiq_api_key = (os.environ.get('OTPIQ_API_KEY') or "").strip()
        self.otpiq_provider = (os.environ.get('OTPIQ_PROVIDER') or 'sms').strip().lower()
    
    def send_password_reset_code(self, phone_number: str, reset_code: str) -> bool:
        """
        Send password reset code via SMS
        
        Args:
            phone_number: User's phone number
            reset_code: The reset code to send
            
        Returns:
            bool: True if sent successfully, False otherwise
        """
        try:
            if self.provider == 'twilio':
                return self._send_via_twilio(phone_number, reset_code)
            elif self.provider == 'otpiq':
                return self._send_via_otpiq(phone_number, reset_code, purpose="password_reset")
            elif self.provider == 'console':
                return self._send_via_console(phone_number, reset_code)
            else:
                logger.error(f"Unsupported SMS provider: {self.provider}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to send SMS: {str(e)}")
            return False
    
    def _send_via_twilio(self, phone_number: str, reset_code: str) -> bool:
        """Send SMS via Twilio"""
        try:
            from twilio.rest import Client
            
            if not all([self.twilio_account_sid, self.twilio_auth_token, self.twilio_phone_number]):
                logger.error("Twilio credentials not configured")
                return False
            
            client = Client(self.twilio_account_sid, self.twilio_auth_token)
            
            message = client.messages.create(
                body=f"Your password reset code is: {reset_code}. This code expires in 1 hour.",
                from_=self.twilio_phone_number,
                to=phone_number
            )
            
            logger.info(f"SMS sent successfully to {phone_number}, SID: {message.sid}")
            return True
            
        except ImportError:
            logger.error("Twilio library not installed. Install with: pip install twilio")
            return False
        except Exception as e:
            logger.error(f"Twilio SMS failed: {str(e)}")
            return False
    
    def _send_via_console(self, phone_number: str, reset_code: str) -> bool:
        """Send SMS via console (for development)"""
        if _app_env() == "production":
            logger.error("SMS_PROVIDER=console is not allowed in production")
            return False
        print(f"\n{'='*50}")
        print(f"SMS TO: {phone_number}")
        print(f"MESSAGE: Your password reset code is: {reset_code}")
        print(f"EXPIRES: 1 hour")
        print(f"{'='*50}\n")
        
        logger.info(f"Password reset code for {phone_number}: {reset_code}")
        return True

    def _send_via_otpiq(self, phone_number: str, code: str, purpose: str = "verification") -> bool:
        """Send OTP via OTPIQ (Iraq SMS/WhatsApp). See https://docs.otpiq.com"""
        if not self.otpiq_api_key:
            logger.error("OTPIQ_API_KEY not set")
            return False
        normalized = _normalize_phone_otpiq(phone_number)
        if len(normalized) < 10 or len(normalized) > 15:
            logger.error("OTPIQ phone number must be 10–15 digits (intl format)")
            return False
        payload = {
            "smsType": "verification",
            "phoneNumber": normalized,
            "verificationCode": str(code)[:20],
        }
        if self.otpiq_provider and self.otpiq_provider != "sms":
            payload["provider"] = self.otpiq_provider
        try:
            r = requests.post(
                OTPIQ_API_URL,
                json=payload,
                headers={"Authorization": f"Bearer {self.otpiq_api_key}", "Content-Type": "application/json"},
                timeout=15,
            )
            if 200 <= r.status_code < 300:
                logger.info("OTPIQ %s sent to %s***", purpose, normalized[:4])
                return True
            data = r.json() if r.text else {}
            err = data.get("error", data.get("message", r.text or str(r.status_code)))
            logger.warning("OTPIQ returned %s: %s", r.status_code, err)
            return False
        except Exception as e:
            logger.exception("OTPIQ request failed: %s", e)
            return False
    
    def send_verification_code(self, phone_number: str, verification_code: str) -> bool:
        """
        Send phone verification code via SMS
        
        Args:
            phone_number: User's phone number
            verification_code: The verification code to send
            
        Returns:
            bool: True if sent successfully, False otherwise
        """
        try:
            if self.provider == 'twilio':
                return self._send_verification_via_twilio(phone_number, verification_code)
            elif self.provider == 'otpiq':
                return self._send_via_otpiq(phone_number, verification_code, purpose="verification")
            elif self.provider == 'console':
                return self._send_verification_via_console(phone_number, verification_code)
            else:
                logger.error(f"Unsupported SMS provider: {self.provider}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to send verification SMS: {str(e)}")
            return False
    
    def _send_verification_via_twilio(self, phone_number: str, verification_code: str) -> bool:
        """Send verification SMS via Twilio"""
        try:
            from twilio.rest import Client
            
            if not all([self.twilio_account_sid, self.twilio_auth_token, self.twilio_phone_number]):
                logger.error("Twilio credentials not configured")
                return False
            
            client = Client(self.twilio_account_sid, self.twilio_auth_token)
            
            message = client.messages.create(
                body=f"Your verification code is: {verification_code}. This code expires in 10 minutes.",
                from_=self.twilio_phone_number,
                to=phone_number
            )
            
            logger.info(f"Verification SMS sent successfully to {phone_number}, SID: {message.sid}")
            return True
            
        except ImportError:
            logger.error("Twilio library not installed. Install with: pip install twilio")
            return False
        except Exception as e:
            logger.error(f"Twilio verification SMS failed: {str(e)}")
            return False
    
    def _send_verification_via_console(self, phone_number: str, verification_code: str) -> bool:
        """Send verification SMS via console (for development)"""
        if _app_env() == "production":
            logger.error("SMS_PROVIDER=console is not allowed in production")
            return False
        print(f"\n{'='*50}")
        print(f"VERIFICATION SMS TO: {phone_number}")
        print(f"MESSAGE: Your verification code is: {verification_code}")
        print(f"EXPIRES: 10 minutes")
        print(f"{'='*50}\n")
        
        logger.info(f"Phone verification code for {phone_number}: {verification_code}")
        return True

# Global SMS service instance
sms_service = SMSService()

def send_password_reset_sms(phone_number: str, reset_code: str) -> bool:
    """Convenience function to send password reset SMS"""
    return sms_service.send_password_reset_code(phone_number, reset_code)

def send_verification_sms(phone_number: str, verification_code: str) -> bool:
    """Convenience function to send verification SMS"""
    return sms_service.send_verification_code(phone_number, verification_code)
