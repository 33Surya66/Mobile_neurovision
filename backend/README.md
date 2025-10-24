# NeuroVision Backend (prototype)

This folder contains a small Flask-based prototype backend that performs face landmark detection using MediaPipe (Python) and returns normalized landmarks.

Requirements
- Python 3.8+ (3.10 recommended)
- The Python packages in `requirements.txt`

Quick start (local development)

1. Create and activate a virtual environment (Windows PowerShell):

```powershell
python -m venv .venv
.\\.venv\\Scripts\\Activate.ps1
```

2. Install dependencies:

```powershell
pip install -r requirements.txt
```

3. Create a `.env` file in `backend/` (copy `.env.template`) and set `MONGO_URI` and other vars as needed.

4. Run the server (recommended on Windows):

```powershell
python run_server.py
```

This will use `waitress` if available (installed via `requirements.txt`) and avoid issues with the Flask reloader on Windows.

API
- POST /detect
  - Accepts multipart form-data (`image` file) or JSON {"dataUrl": "data:image/jpeg;base64,..."}
  - Returns JSON: {"landmarks": [x0,y0,x1,y1,...], "width":W, "height":H} or {"landmarks": null, "message": "no_face"}

Utility endpoints
- GET /health — returns {ok: true, mongo: bool, mongo_db: <name>, require_mongo: bool}
- GET / — small index/landing page (helps Render or other hosts detect the service)

Notes
- This backend is purposely minimal to help troubleshooting face-detection on a stable environment (server-side). For production, add authentication, rate-limiting, batching, model lifecycle management, logging, and error handling.
- MediaPipe Python has prebuilt wheels and is fast on modern CPUs. For high throughput, use a worker queue and persist a long-running FaceMesh instance.
