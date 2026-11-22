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
