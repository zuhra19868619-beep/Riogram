from fastapi import FastAPI,HTTPException
from sqlalchemy import text
from .database import engine
from .messaging import router as messaging_router
from .features import router as features_router
from .auth import router as auth_router
app=FastAPI(title="Riogram API",version="0.4.0")
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
