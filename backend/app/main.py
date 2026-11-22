import os
from contextlib import asynccontextmanager
from fastapi import FastAPI,HTTPException
from sqlalchemy import text
from .database import engine,Base
from . import models
from .messaging import router as messaging_router
from .features import router as features_router
from .auth import router as auth_router

@asynccontextmanager
async def lifespan(app):
    # SQLite only for explicitly enabled development/demo use.
    # Render free filesystem is ephemeral: not suitable for real user data.
    if os.getenv("RIOGRAM_DEMO_SQLITE")=="1" and engine.dialect.name=="sqlite":
        Base.metadata.create_all(bind=engine)
    yield

app=FastAPI(title="Riogram API",version="0.5.0",lifespan=lifespan)
app.include_router(messaging_router)
app.include_router(features_router)
app.include_router(auth_router)

@app.get("/api/v1/health")
def health():return {"status":"ok","service":"riogram"}
@app.get("/api/v1/health/database")
def database_health():
    try:
        with engine.connect() as connection:connection.execute(text("SELECT 1"))
    except Exception:raise HTTPException(status_code=503,detail="Database unavailable")
    return {"status":"ok","database":"connected"}
