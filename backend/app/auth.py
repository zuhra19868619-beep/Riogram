"""Phone login via Twilio Verify. No demo OTP bypass is exposed."""
import os,re
from datetime import datetime,timedelta,timezone
import httpx,jwt
from fastapi import APIRouter,HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from .messaging import DB
from .models import User

router=APIRouter(prefix="/api/v1/auth",tags=["authentication"])
class PhoneRequest(BaseModel):
    phone_number:str
class VerifyRequest(PhoneRequest):
    code:str

def config():
    account=os.getenv("TWILIO_ACCOUNT_SID","")
    token=os.getenv("TWILIO_AUTH_TOKEN","")
    service=os.getenv("TWILIO_VERIFY_SERVICE_SID","")
    secret=os.getenv("JWT_SECRET","")
    if not all((account,token,service)) or len(secret)<32:
        raise HTTPException(503,"SMS authentication not configured")
    return account,token,service,secret

def validate_phone(phone):
    if not re.fullmatch(r"\+[1-9][0-9]{7,14}",phone):
        raise HTTPException(422,"Phone must be E.164")

@router.post("/request-code")
def request_code(body:PhoneRequest):
    validate_phone(body.phone_number)
    account,token,service,_=config()
    url=f"https://verify.twilio.com/v2/Services/{service}/Verifications"
    try:
        with httpx.Client(timeout=12) as client:
            response=client.post(url,auth=(account,token),data={"To":body.phone_number,"Channel":"sms"})
            response.raise_for_status()
    except httpx.HTTPError:
        raise HTTPException(502,"SMS provider unavailable")
    return {"status":"pending"}

@router.post("/verify-code")
def verify_code(body:VerifyRequest,db:DB):
    validate_phone(body.phone_number)
    if not re.fullmatch(r"[0-9]{4,10}",body.code):
        raise HTTPException(422,"Invalid code format")
    account,token,service,secret=config()
    url=f"https://verify.twilio.com/v2/Services/{service}/VerificationCheck"
    try:
        with httpx.Client(timeout=12) as client:
            response=client.post(url,auth=(account,token),data={"To":body.phone_number,"Code":body.code})
            response.raise_for_status()
            approved=response.json().get("status")=="approved"
    except httpx.HTTPError:
        raise HTTPException(502,"SMS provider unavailable")
    if not approved:
        raise HTTPException(401,"Code not approved")
    user=db.scalar(select(User).where(User.phone_number==body.phone_number))
    if user is None:
        user=User(phone_number=body.phone_number)
        db.add(user)
        db.commit()
        db.refresh(user)
    expires=datetime.now(timezone.utc)+timedelta(hours=12)
    access_token=jwt.encode({"sub":user.id,"aud":"riogram","exp":expires},secret,algorithm="HS256")
    return {"access_token":access_token,"token_type":"bearer","expires_in":43200,"user_id":user.id}


class FirebaseLoginRequest(BaseModel):
    id_token: str

@router.post("/firebase-login")
def firebase_login(body: FirebaseLoginRequest, db: DB):
    """Exchange a verified Firebase phone-auth ID token for a Riogram session."""
    import firebase_admin
    from firebase_admin import auth as firebase_auth
    from firebase_admin import credentials
    project_id = os.getenv("FIREBASE_PROJECT_ID", "").strip()
    secret = os.getenv("JWT_SECRET", "")
    if not project_id or len(secret) < 32:
        raise HTTPException(503, "Firebase authentication not configured")
    if not firebase_admin._apps:
        service_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()
        if service_json:
            import json
            try:
                cred = credentials.Certificate(json.loads(service_json))
                firebase_admin.initialize_app(cred, {"projectId": project_id})
            except (ValueError, KeyError, TypeError):
                raise HTTPException(503, "Firebase credentials invalid")
        else:
            try:
                firebase_admin.initialize_app(options={"projectId": project_id})
            except ValueError:
                raise HTTPException(503, "Firebase credentials unavailable")
    try:
        claims = firebase_auth.verify_id_token(body.id_token, check_revoked=True)
    except (ValueError, firebase_auth.InvalidIdTokenError,
            firebase_auth.ExpiredIdTokenError,
            firebase_auth.RevokedIdTokenError,
            firebase_auth.UserDisabledError):
        raise HTTPException(401, "Invalid Firebase token")
    if claims.get("firebase", {}).get("sign_in_provider") != "phone":
        raise HTTPException(403, "Phone authentication required")
    phone = claims.get("phone_number", "")
    validate_phone(phone)
    user = db.scalar(select(User).where(User.phone_number == phone))
    if user is None:
        user = User(phone_number=phone)
        db.add(user)
        db.commit()
        db.refresh(user)
    expires = datetime.now(timezone.utc) + timedelta(hours=12)
    access_token = jwt.encode({"sub": user.id, "aud": "riogram", "exp": expires},
                              secret, algorithm="HS256")
    return {"access_token": access_token, "token_type": "bearer",
            "expires_in": 43200, "user_id": user.id}
