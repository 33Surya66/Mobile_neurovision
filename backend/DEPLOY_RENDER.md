Render deployment notes

Options:
1) Use the Dockerfile (recommended because it pins Python and system libs):
   - In Render create a new service -> Web Service -> connect to repo
   - Choose "Docker" as the environment (Render will build your Dockerfile)
   - Set the port to 5000 (or leave default; Dockerfile uses 5000)
   - Configure Environment Variables: MONGO_URI, MONGO_DB, MONGO_COLLECTION, DETECTION_API_KEY, ALLOWED_ORIGINS, REQUIRE_MONGO
   - Deploy

2) Use Render's Buildpacks (non-Docker):
   - Ensure the service Root Directory is `backend/` (so Render reads backend/runtime.txt or backend/pyproject)
   - In Service settings set Python version to 3.11 if available
   - Build Command: pip install --upgrade pip setuptools wheel && pip install -r requirements.txt
   - Start Command: gunicorn --bind 0.0.0.0:$PORT app:app
   - Environment Variables: same as above
   - Health check path: /health

Notes:
- We added `dnspython` to requirements so mongodb+srv URIs resolve properly.
- The Dockerfile installs system libs required by Pillow and keeps Python pinned to 3.11.
- If you deploy with Docker, Render won't need to build wheels on its default Python runtime.

Testing:
- After deploy, test health: curl https://<your-service>.onrender.com/health
- Test detection (example): curl -X POST -F "image=@face.jpg" https://<your-service>.onrender.com/detect
