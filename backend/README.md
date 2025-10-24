# NeuroVision Backend (prototype)

This folder contains a small Flask-based prototype backend that performs face landmark detection using MediaPipe (Python) and returns normalized landmarks.

Requirements
- Python 3.8+ (3.10 recommended)
- The Python packages in `requirements.txt`

Install and run

Windows / PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

Linux / macOS:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

API
- POST /detect
  - Accepts multipart form-data (`image` file) or JSON {"dataUrl": "data:image/jpeg;base64,..."}
  - Returns JSON: {"landmarks": [x0,y0,x1,y1,...], "width":W, "height":H} or {"landmarks": null, "message": "no_face"}

Notes
- This backend is purposely minimal to help troubleshooting face-detection on a stable environment (server-side). For production, add authentication, rate-limiting, batching, model lifecycle management, logging, and error handling.
- MediaPipe Python has prebuilt wheels and is fast on modern CPUs. For high throughput, use a worker queue and persist a long-running FaceMesh instance.
