from fastapi import FastAPI
from sqlalchemy import text
from .database import engine

app = FastAPI(title="Riogram API", version="0.2.0")

@app.get("/api/v1/health")
def health():
    return {"status": "ok", "service": "riogram"}

@app.get("/api/v1/health/database")
def database_health():
    from fastapi import HTTPException
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except Exception:
        raise HTTPException(status_code=503, detail="Database unavailable")
    return {"status": "ok", "database": "connected"}
