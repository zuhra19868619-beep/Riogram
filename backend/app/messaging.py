import os, uuid
from datetime import datetime, timezone
from typing import Annotated
import jwt
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session
from .database import SessionLocal
from .models import User, Chat, ChatMember, Message

router = APIRouter(prefix="/api/v1", tags=["messaging"])

def get_db():
    with SessionLocal() as db:
        yield db

DB = Annotated[Session, Depends(get_db)]

def current_user(db: DB, authorization: Annotated[str | None, Header()] = None):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Bearer token required")
    secret = os.getenv("JWT_SECRET")
    if not secret or len(secret) < 32:
        raise HTTPException(503, "Authentication not configured")
    try:
        claims = jwt.decode(authorization[7:], secret, algorithms=["HS256"], audience="riogram")
        user_id = str(uuid.UUID(claims["sub"]))
    except (jwt.PyJWTError, KeyError, ValueError, TypeError):
        raise HTTPException(401, "Invalid or expired token")
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(401, "Unknown user")
    return user

UserDep = Annotated[User, Depends(current_user)]

def require_member(db, chat_id, user_id):
    if db.scalar(select(ChatMember).where(ChatMember.chat_id == chat_id, ChatMember.user_id == user_id)) is None:
        raise HTTPException(404, "Chat not found")

class DirectChatRequest(BaseModel):
    recipient_id: uuid.UUID

class MessageRequest(BaseModel):
    client_message_id: str = Field(min_length=1, max_length=64)
    text: str = Field(min_length=1, max_length=10000)

class EditRequest(BaseModel):
    text: str = Field(min_length=1, max_length=10000)

def as_message(message):
    return {"id": message.id, "chat_id": message.chat_id, "sender_id": message.sender_id,
            "client_message_id": message.client_message_id, "text": message.text,
            "created_at": message.created_at, "edited_at": message.edited_at,
            "deleted_at": message.deleted_at}

@router.get("/chats")
def chats(db: DB, user: UserDep):
    items = db.scalars(select(Chat).join(ChatMember, ChatMember.chat_id == Chat.id).where(ChatMember.user_id == user.id)).all()
    return [{"id": item.id, "type": item.type, "title": item.title} for item in items]

@router.post("/chats/direct", status_code=201)
def direct_chat(data: DirectChatRequest, db: DB, user: UserDep):
    recipient_id = str(data.recipient_id)
    if recipient_id == user.id:
        raise HTTPException(400, "Cannot message yourself")
    if db.get(User, recipient_id) is None:
        raise HTTPException(404, "Recipient not found")
    candidates = db.scalars(select(Chat).join(ChatMember, ChatMember.chat_id == Chat.id).where(Chat.type == "direct", ChatMember.user_id == user.id)).all()
    for chat in candidates:
        members = set(db.scalars(select(ChatMember.user_id).where(ChatMember.chat_id == chat.id)).all())
        if members == {user.id, recipient_id}:
            return {"id": chat.id, "type": chat.type}
    chat = Chat(type="direct")
    db.add(chat)
    db.flush()
    db.add_all([ChatMember(chat_id=chat.id, user_id=user.id), ChatMember(chat_id=chat.id, user_id=recipient_id)])
    db.commit()
    return {"id": chat.id, "type": chat.type}

@router.get("/chats/{chat_id}/messages")
def messages(chat_id: uuid.UUID, db: DB, user: UserDep, limit: int = 50):
    require_member(db, str(chat_id), user.id)
    if limit < 1 or limit > 100:
        raise HTTPException(422, "limit must be 1..100")
    rows = db.scalars(select(Message).where(Message.chat_id == str(chat_id), Message.deleted_at.is_(None)).order_by(Message.created_at.desc(), Message.id.desc()).limit(limit)).all()
    return [as_message(row) for row in reversed(rows)]

@router.post("/chats/{chat_id}/messages", status_code=201)
async def send(chat_id: uuid.UUID, data: MessageRequest, db: DB, user: UserDep):
    require_member(db, str(chat_id), user.id)
    existing = db.scalar(select(Message).where(Message.sender_id == user.id, Message.client_message_id == data.client_message_id))
    if existing:
        if existing.chat_id != str(chat_id):
            raise HTTPException(409, "Message ID already used")
        return as_message(existing)
    message = Message(chat_id=str(chat_id), sender_id=user.id, client_message_id=data.client_message_id, text=data.text)
    db.add(message)
    db.commit()
    db.refresh(message)
    from .features import hub
    from .notifications import push_to_users
    recipients = db.scalars(select(ChatMember.user_id).where(
        ChatMember.chat_id == str(chat_id), ChatMember.user_id != user.id)).all()
    event = {"type": "message", "data": as_message(message)}
    for recipient in recipients:
        await hub.send(recipient, event)
    push_to_users(db, recipients, "Riogram", "Новое сообщение")
    return as_message(message)

@router.patch("/messages/{message_id}")
def edit(message_id: uuid.UUID, data: EditRequest, db: DB, user: UserDep):
    message = db.get(Message, str(message_id))
    if message is None or message.sender_id != user.id or message.deleted_at is not None:
        raise HTTPException(404, "Message not found")
    require_member(db, message.chat_id, user.id)
    message.text = data.text
    message.edited_at = datetime.now(timezone.utc)
    db.commit()
    return as_message(message)

@router.delete("/messages/{message_id}", status_code=204)
def delete(message_id: uuid.UUID, db: DB, user: UserDep):
    message = db.get(Message, str(message_id))
    if message is None or message.sender_id != user.id or message.deleted_at is not None:
        raise HTTPException(404, "Message not found")
    require_member(db, message.chat_id, user.id)
    message.deleted_at = datetime.now(timezone.utc)
    db.commit()
