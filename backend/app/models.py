import uuid
from datetime import datetime, timezone
from sqlalchemy import DateTime, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .database import Base

def new_id() -> str:
    return str(uuid.uuid4())

def utcnow() -> datetime:
    return datetime.now(timezone.utc)

class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    phone_number: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    username: Mapped[str | None] = mapped_column(String(32), unique=True)
    first_name: Mapped[str] = mapped_column(String(80), default="")
    last_name: Mapped[str] = mapped_column(String(80), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

class Chat(Base):
    __tablename__ = "chats"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    type: Mapped[str] = mapped_column(String(16), nullable=False, default="direct")
    title: Mapped[str | None] = mapped_column(String(160))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

class ChatMember(Base):
    __tablename__ = "chat_members"
    __table_args__ = (UniqueConstraint("chat_id", "user_id", name="uq_chat_member"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    chat_id: Mapped[str] = mapped_column(ForeignKey("chats.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    role: Mapped[str] = mapped_column(String(16), default="member")

class Message(Base):
    __tablename__ = "messages"
    __table_args__ = (UniqueConstraint("sender_id", "client_message_id", name="uq_message_idempotency"), Index("ix_message_chat_created", "chat_id", "created_at"))
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    chat_id: Mapped[str] = mapped_column(ForeignKey("chats.id", ondelete="CASCADE"), nullable=False)
    sender_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    client_message_id: Mapped[str] = mapped_column(String(64), nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    edited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
