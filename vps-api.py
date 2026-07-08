from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
import subprocess

app = FastAPI()

API_TOKEN = "pH112ANMIq9T7tuo_13py7t51wAqgf4ooDj_85UjzKU"

class CommandRequest(BaseModel):
    command: str

class CommandResponse(BaseModel):
    stdout: str
    stderr: str
    exit_code: int

@app.post("/api/exec")
async def execute_command(
    request: CommandRequest,
    authorization: str = Header(None)
):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing authorization header")

    token = authorization.replace("Bearer ", "")
    if token != API_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid token")

    try:
        result = subprocess.run(
            request.command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=30
        )
        return CommandResponse(
            stdout=result.stdout,
            stderr=result.stderr,
            exit_code=result.returncode
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=408, detail="Command timeout")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    return {"status": "ok"}
