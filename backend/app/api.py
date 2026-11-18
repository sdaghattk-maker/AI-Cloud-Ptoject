"""API برای اپ موبایل:  uvicorn app.api:app --host 0.0.0.0 --port 8000"""
import time
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from . import analyzer, config

app = FastAPI(title="CryptoSignal AI")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
_cache = {}


def cached(key, ttl, fn):
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < ttl:
        return hit[1]
    val = fn()
    _cache[key] = (time.time(), val)
    return val


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/analyze")
def analyze(symbol: str = "BTCUSDT", tf: str = "1h"):
    if tf not in config.TIMEFRAMES:
        raise HTTPException(400, f"tf must be one of {config.TIMEFRAMES}")
    try:
        return cached(("a", symbol, tf), 300, lambda: analyzer.analyze(symbol.upper(), tf))
    except Exception as e:
        raise HTTPException(502, str(e))


@app.get("/scan")
def scan():
    return cached("scan", 600, analyzer.scan)
