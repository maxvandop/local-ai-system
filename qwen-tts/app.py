import io
import torch
import soundfile as sf
from fastapi import FastAPI
from fastapi.responses import Response
from pydantic import BaseModel
from qwen_tts import Qwen3TTSModel

app = FastAPI()

print("Loading Qwen3 TTS model, this may take a while...")

model = Qwen3TTSModel.from_pretrained(
    "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
    device_map="cuda:0",
    dtype=torch.bfloat16,
)

print("Model loaded and ready!")

class TTSRequest(BaseModel):
    text: str
    speaker: str = ""
    language: str = "English"
    instruct: str = ""

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/tts")
def generate(req: TTSRequest):
    wavs, sr = model.generate_custom_voice(
        text=req.text,
        language=req.language,
        speaker=req.speaker,
        instruct=req.instruct if req.instruct else None,
    )
    buf = io.BytesIO()
    sf.write(buf, wavs[0], sr, format="WAV")
    buf.seek(0)
    return Response(content=buf.read(), media_type="audio/wav")