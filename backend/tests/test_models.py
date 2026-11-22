from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool
from app.database import Base
from app.models import Chat, ChatMember, Message, User

def test_persist_chat_and_message():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        user = User(phone_number="+12025550111", username="tester")
        session.add(user)
        session.flush()
        chat = Chat(type="direct")
        session.add(chat)
        session.flush()
        session.add(ChatMember(chat_id=chat.id, user_id=user.id))
        session.add(Message(chat_id=chat.id, sender_id=user.id, client_message_id="abc-1", text="Hello"))
        session.commit()
        assert session.query(Message).count() == 1
        assert session.query(ChatMember).count() == 1
