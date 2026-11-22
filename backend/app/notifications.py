"""Optional Firebase Cloud Messaging integration.

Set FIREBASE_SERVICE_ACCOUNT_JSON to a Firebase service-account JSON object.
Push is disabled when credentials are absent. Never commit credentials.
"""
import json,os
from sqlalchemy import select
from .models import DeviceToken

def push_to_users(db,user_ids,title,body):
    raw=os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    if not raw:
        return {"sent":0,"configured":False}
    try:
        import firebase_admin
        from firebase_admin import credentials,messaging
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))
        tokens=db.scalars(select(DeviceToken.token).where(DeviceToken.user_id.in_(list(user_ids)))).all()
        sent=0
        for token in tokens:
            try:
                messaging.send(messaging.Message(token=token,notification=messaging.Notification(title=title,body=body[:150])))
                sent+=1
            except Exception:
                pass
        return {"sent":sent,"configured":True}
    except Exception:
        return {"sent":0,"configured":False}
