import asyncio, os, re, uuid
from collections import defaultdict
import jwt
from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from sqlalchemy import select
from .database import SessionLocal
from .messaging import DB, UserDep
from .models import User, ChatMember, DeviceToken

router=APIRouter(prefix="/api/v1",tags=["features"])
class ContactsRequest(BaseModel):
    phones:list[str]=Field(max_length=500)
class DeviceRequest(BaseModel):
    token:str=Field(min_length=16,max_length=4096)
    platform:str=Field(pattern="^(android|ios)$")
class CallSignal(BaseModel):
    recipient_id:uuid.UUID
    call_id:uuid.UUID
    type:str=Field(pattern="^(offer|answer|ice|hangup)$")
    payload:dict=Field(default_factory=dict)

@router.post("/contacts/match")
def match_contacts(body:ContactsRequest,db:DB,user:UserDep):
    phones=list(dict.fromkeys(body.phones))
    if any(not re.fullmatch(r"\+[1-9][0-9]{7,14}",p) for p in phones):
        raise HTTPException(422,"Phone numbers must use E.164 format")
    if not phones: return {"contacts":[]}
    users=db.scalars(select(User).where(User.phone_number.in_(phones),User.id!=user.id)).all()
    return {"contacts":[{"id":u.id,"phone_number":u.phone_number,"first_name":u.first_name,"last_name":u.last_name} for u in users]}

@router.post("/devices",status_code=201)
def register_device(body:DeviceRequest,db:DB,user:UserDep):
    entry=db.scalar(select(DeviceToken).where(DeviceToken.token==body.token))
    if entry: entry.user_id=user.id;entry.platform=body.platform
    else: db.add(DeviceToken(user_id=user.id,token=body.token,platform=body.platform))
    db.commit()
    return {"registered":True}

@router.delete("/devices",status_code=204)
def unregister_device(body:DeviceRequest,db:DB,user:UserDep):
    entry=db.scalar(select(DeviceToken).where(DeviceToken.token==body.token,DeviceToken.user_id==user.id))
    if entry: db.delete(entry);db.commit()

class Hub:
    def __init__(self): self.clients=defaultdict(set)
    async def send(self,user_id,data):
        for ws in list(self.clients.get(user_id,())):
            try: await ws.send_json(data)
            except Exception: self.clients[user_id].discard(ws)
hub=Hub()

@router.websocket("/ws")
async def websocket_endpoint(ws:WebSocket):
    await ws.accept()
    try:
        first=await asyncio.wait_for(ws.receive_json(),timeout=10)
        token=first.get("token") if isinstance(first,dict) else None
        secret=os.getenv("JWT_SECRET")
        if not secret or len(secret)<32 or not isinstance(token,str):
            await ws.close(code=1008);return
        try:
            claims=jwt.decode(token,secret,algorithms=["HS256"],audience="riogram")
            user_id=str(uuid.UUID(claims["sub"]))
        except (jwt.PyJWTError,KeyError,ValueError,TypeError):
            await ws.close(code=1008);return
        with SessionLocal() as db:
            if not db.get(User,user_id):
                await ws.close(code=1008);return
        hub.clients[user_id].add(ws)
        await ws.send_json({"type":"connected"})
        while True:
            event=await ws.receive_json()
            if not isinstance(event,dict):continue
            if event.get("type")=="ping": await ws.send_json({"type":"pong"})
            elif event.get("type")=="call_signal":
                try: signal=CallSignal.model_validate(event.get("data"))
                except Exception:
                    await ws.send_json({"type":"error","detail":"Invalid call signal"});continue
                with SessionLocal() as db:
                    own=select(ChatMember.chat_id).where(ChatMember.user_id==user_id)
                    shared=db.scalar(select(ChatMember.chat_id).where(ChatMember.user_id==str(signal.recipient_id),ChatMember.chat_id.in_(own)).limit(1))
                if not shared:
                    await ws.send_json({"type":"error","detail":"Recipient unavailable"});continue
                await hub.send(str(signal.recipient_id),{"type":"call_signal","sender_id":user_id,"data":signal.model_dump(mode="json")})
    except (WebSocketDisconnect,asyncio.TimeoutError):pass
    finally:
        if "user_id" in locals():
            hub.clients[user_id].discard(ws)
