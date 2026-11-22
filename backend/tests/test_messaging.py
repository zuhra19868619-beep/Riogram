import uuid
from datetime import datetime, timedelta, timezone
import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from app.database import Base
from app.main import app
from app.messaging import get_db
from app.models import User

@pytest.fixture
def context(monkeypatch):
    secret = "local-test-secret-with-at-least-32-characters"
    monkeypatch.setenv("JWT_SECRET", secret)
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    def db_override():
        with Session() as session:
            yield session
    app.dependency_overrides[get_db] = db_override
    with Session() as session:
        users = [User(phone_number=f"+1202555010{i}", username=f"user{i}") for i in range(3)]
        session.add_all(users)
        session.commit()
        ids = [user.id for user in users]
    def headers(i):
        token = jwt.encode({"sub": ids[i], "aud": "riogram", "exp": datetime.now(timezone.utc) + timedelta(hours=1)}, secret, algorithm="HS256")
        return {"Authorization": "Bearer " + token}
    with TestClient(app) as client:
        yield client, ids, headers
    app.dependency_overrides.clear()

def test_requires_login(context):
    client, _, _ = context
    assert client.get("/api/v1/chats").status_code == 401

def test_chat_message_idempotency_and_permissions(context):
    client, ids, headers = context
    response = client.post("/api/v1/chats/direct", json={"recipient_id": ids[1]}, headers=headers(0))
    assert response.status_code == 201
    chat_id = response.json()["id"]
    assert client.post("/api/v1/chats/direct", json={"recipient_id": ids[1]}, headers=headers(0)).json()["id"] == chat_id
    payload = {"client_message_id": str(uuid.uuid4()), "text": "Привет"}
    first = client.post(f"/api/v1/chats/{chat_id}/messages", json=payload, headers=headers(0))
    assert first.status_code == 201
    duplicate = client.post(f"/api/v1/chats/{chat_id}/messages", json=payload, headers=headers(0))
    assert duplicate.json()["id"] == first.json()["id"]
    assert len(client.get(f"/api/v1/chats/{chat_id}/messages", headers=headers(1)).json()) == 1
    assert client.get(f"/api/v1/chats/{chat_id}/messages", headers=headers(2)).status_code == 404
    assert client.post(f"/api/v1/chats/{chat_id}/messages", json=payload, headers=headers(2)).status_code == 404
    mid = first.json()["id"]
    assert client.patch(f"/api/v1/messages/{mid}", json={"text": "wrong"}, headers=headers(1)).status_code == 404
    assert client.patch(f"/api/v1/messages/{mid}", json={"text": "edited"}, headers=headers(0)).json()["text"] == "edited"
    assert client.delete(f"/api/v1/messages/{mid}", headers=headers(0)).status_code == 204
    assert client.get(f"/api/v1/chats/{chat_id}/messages", headers=headers(1)).json() == []

def test_self_chat_rejected(context):
    client, ids, headers = context
    assert client.post("/api/v1/chats/direct", json={"recipient_id": ids[0]}, headers=headers(0)).status_code == 400
