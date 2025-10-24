from flask import Flask, request, jsonify
import base64
import io
from PIL import Image
import numpy as np
import mediapipe as mp
import os
from datetime import datetime

# Optional MongoDB (persistence) - only used if MONGO_URI is set
try:
    from pymongo import MongoClient
except Exception:
    MongoClient = None

# CORS support for browser requests
try:
    from flask_cors import CORS
except Exception:
    CORS = None

app = Flask(__name__)

# enable CORS for all origins (development). Restrict in production if needed.
if CORS:
    CORS(app, resources={r"/*": {"origins": "*"}})

mp_face_mesh = mp.solutions.face_mesh
# Use static_image_mode=True for single-image inference (no tracking)
face_mesh = mp_face_mesh.FaceMesh(static_image_mode=True, max_num_faces=1, refine_landmarks=True, min_detection_confidence=0.5)

# Initialize MongoDB client if MONGO_URI is provided
mongo_client = None
mongo_db = None
mongo_collection = None
MONGO_URI = os.environ.get('MONGO_URI')
if MONGO_URI and MongoClient:
    try:
        mongo_client = MongoClient(MONGO_URI)
        # database and collection names are configurable via env or default
        mongo_db = mongo_client.get_database(os.environ.get('MONGO_DB', 'neurovision'))
        mongo_collection = mongo_db.get_collection(os.environ.get('MONGO_COLLECTION', 'detections'))
        app.logger.info('MongoDB connected')
    except Exception as e:
        app.logger.warning(f'Could not connect to MongoDB: {e}')


@app.route('/detect', methods=['POST'])
def detect():
    try:
        # Accept multipart/form-data file or JSON {dataUrl: 'data:...'}
        img_bytes = None
        if 'image' in request.files:
            f = request.files['image']
            img_bytes = f.read()
        else:
            data = request.get_json(silent=True) or {}
            data_url = data.get('dataUrl') or data.get('dataurl')
            if data_url:
                # strip header
                header, _, b64 = data_url.partition(',')
                img_bytes = base64.b64decode(b64)

        if not img_bytes:
            return jsonify({'error': 'no image provided'}), 400

        image = Image.open(io.BytesIO(img_bytes)).convert('RGB')
        width, height = image.size
        img_np = np.array(image)

        # MediaPipe expects RGB images
        results = face_mesh.process(img_np)
        if not results.multi_face_landmarks:
            resp = {'landmarks': None, 'message': 'no_face'}
            return jsonify(resp), 200

        lm = results.multi_face_landmarks[0]
        flat = []
        for p in lm.landmark:
            # normalized coords [0..1]
            flat.append(p.x)
            flat.append(p.y)

        resp = {'landmarks': flat, 'width': width, 'height': height}

        # Persist to MongoDB if configured (best-effort, non-blocking for client)
        if mongo_collection:
            try:
                doc = {
                    'timestamp': datetime.utcnow(),
                    'landmarks': flat,
                    'width': width,
                    'height': height,
                    'source': request.remote_addr
                }
                mongo_collection.insert_one(doc)
            except Exception as e:
                app.logger.warning(f'Failed to persist detection: {e}')

        return jsonify(resp), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# Ensure CORS headers are always present even if flask-cors isn't installed
@app.after_request
def _add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
    response.headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'
    return response


if __name__ == '__main__':
    # Allow overriding host/port via env for flexibility
    host = os.environ.get('APP_HOST', '0.0.0.0')
    port = int(os.environ.get('APP_PORT', 5000))
    app.run(host=host, port=port, debug=True)
