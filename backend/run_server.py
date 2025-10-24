"""
Local server starter. On Windows this uses Waitress to avoid reloader/socket issues.
Usage:
    python run_server.py
"""
import os
from app import app

port = int(os.environ.get('APP_PORT') or os.environ.get('PORT') or 5000)
host = '0.0.0.0'

try:
    # Prefer waitress for local and Windows environments
    from waitress import serve
    print(f"Starting server with Waitress on {host}:{port}")
    serve(app, host=host, port=port)
except Exception as e:
    # Fallback to Flask built-in (not recommended for production)
    print(f"Waitress not available or failed to start ({e}), falling back to Flask dev server")
    app.run(host=host, port=port, debug=False)
