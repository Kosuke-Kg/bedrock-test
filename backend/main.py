from datetime import datetime
from typing import Dict

from fastapi import FastAPI

app = FastAPI()


@app.get("/")
def hello_world() -> Dict[str, str]:
    return {"Hello": "World"}


@app.get("/health_check")
def health_check() -> Dict[str, str | datetime]:
    return {"status": "healthy", "timestamp": datetime.now()}
