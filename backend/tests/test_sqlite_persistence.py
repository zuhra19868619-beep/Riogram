from sqlalchemy import create_engine,select
from sqlalchemy.orm import Session
from app.database import Base
from app.models import User,Chat,ChatMember,Message

def test_file_sqlite_survives_reopen(tmp_path):
    path=tmp_path/"riogram.db"
    url=f"sqlite:///{path}"
    engine=create_engine(url)
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        user=User(phone_number="+12025550199",first_name="Saved")
        db.add(user);db.flush()
        chat=Chat(type="direct");db.add(chat);db.flush()
        db.add(ChatMember(chat_id=chat.id,user_id=user.id))
        db.add(Message(chat_id=chat.id,sender_id=user.id,client_message_id="persist-1",text="Durable message"))
        db.commit()
    engine.dispose()
    engine=create_engine(url)
    with Session(engine) as db:
        assert db.scalar(select(User).where(User.phone_number=="+12025550199")).first_name=="Saved"
        assert db.scalar(select(Message).where(Message.client_message_id=="persist-1")).text=="Durable message"
    engine.dispose()
