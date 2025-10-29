from flask import Flask, request, jsonify
import base64
import io
from PIL import Image
import numpy as np
import mediapipe as mp
import os
from datetime import datetime, timezone
import sys
from bson import ObjectId
import uuid
try:
    # load .env in development if present
    from dotenv import load_dotenv
    load_dotenv()
except Exception:
    # python-dotenv is optional; env vars may be set in the environment
    pass

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

# Optional: allow restricting origins via ALLOWED_ORIGINS env (comma-separated)
ALLOWED_ORIGINS_RAW = os.environ.get('ALLOWED_ORIGINS', '*')
# parse comma-separated origins (allow '*' or a list)
if ALLOWED_ORIGINS_RAW.strip() == '*' or not ALLOWED_ORIGINS_RAW.strip():
    CORS_ORIGINS = '*'
else:
    CORS_ORIGINS = [o.strip() for o in ALLOWED_ORIGINS_RAW.split(',') if o.strip()]

# enable CORS for configured origins (development default '*'). Restrict in production.
if CORS:
    CORS(app, resources={r"/*": {"origins": CORS_ORIGINS}})

mp_face_mesh = mp.solutions.face_mesh
# Use static_image_mode=True for single-image inference (no tracking)
face_mesh = mp_face_mesh.FaceMesh(static_image_mode=True, max_num_faces=1, refine_landmarks=True, min_detection_confidence=0.5)


def _extract_image_bytes_from_request():
    """Return (img_bytes, None) on success or (None, (body_dict, status)) on error."""
    if 'image' in request.files:
        f = request.files['image']
        return f.read(), None

    if not request.is_json:
        return None, ({'error': 'Request must be JSON when not using form-data'}, 400)

    data = request.get_json()
    if not data:
        return None, ({'error': 'No data provided'}, 400)

    data_url = data.get('dataUrl') or data.get('dataurl')
    if data_url:
        try:
            _, _, b64 = data_url.partition(',')
            return base64.b64decode(b64), None
        except Exception:
            return None, ({'error': 'invalid image data'}, 400)

    return None, ({'error': 'no image provided'}, 400)


def _process_image_bytes(img_bytes, remote_addr=None):
    """Run MediaPipe on image bytes and persist best-effort. Returns (body_dict, status).

    This is pure logic (no Flask response objects) so it can be called from multiple endpoints.
    """
    try:
        image = Image.open(io.BytesIO(img_bytes)).convert('RGB')
    except Exception as e:
        return {'error': f'invalid image: {e}'}, 400

    width, height = image.size
    img_np = np.array(image)

    results = face_mesh.process(img_np)
    if not results or not getattr(results, 'multi_face_landmarks', None):
        return {'landmarks': None, 'message': 'no_face'}, 200

    lm = results.multi_face_landmarks[0]
    flat = []
    for p in lm.landmark:
        x = max(0.0, min(1.0, p.x))
        y = max(0.0, min(1.0, p.y))
        flat.append(x)
        flat.append(y)

    resp = {'landmarks': flat, 'width': width, 'height': height}

    # Persist to MongoDB if configured (best-effort)
    try:
        # Avoid truth-testing Collection objects (they raise TypeError).
        if detections_collection is not None:
            col = detections_collection
        elif mongo_collection is not None:
            col = mongo_collection
        else:
            col = mongo_db.get_collection('detections') if mongo_db is not None else None
        if col is not None:
            doc = {
                '_id': ObjectId(),
                'timestamp': datetime.now(timezone.utc),
                'landmarks': flat,
                'width': width,
                'height': height,
                'source': remote_addr,
            }
            col.insert_one(doc)
    except Exception as e:
        app.logger.warning(f'Failed to persist detection: {e}')

    return resp, 200

# Initialize MongoDB client if MONGO_URI is provided
mongo_client = None
mongo_db = None
mongo_collection = None
sessions_collection = None
detections_collection = None
metrics_collection = None
MONGO_URI = os.environ.get('MONGO_URI')
if MONGO_URI and MongoClient:
    try:
        mongo_client = MongoClient(MONGO_URI)
        # database and collection names are configurable via env or default
        mongo_db = mongo_client.get_database(os.environ.get('MONGO_DB', 'neurovision'))
        # default collection names
        mongo_collection = mongo_db.get_collection(os.environ.get('MONGO_COLLECTION', 'detections'))
        sessions_collection = mongo_db.get_collection(os.environ.get('MONGO_SESSIONS_COLLECTION', 'sessions'))
        detections_collection = mongo_db.get_collection(os.environ.get('MONGO_DETECTIONS_COLLECTION', 'detections'))
        metrics_collection = mongo_db.get_collection(os.environ.get('MONGO_METRICS_COLLECTION', 'metrics'))
        app.logger.info('MongoDB connected')
    except Exception as e:
        app.logger.warning(f'Could not connect to MongoDB: {e}')

# If the operator requires MongoDB for this deployment, allow failing fast.
REQUIRE_MONGO = os.environ.get('REQUIRE_MONGO', 'false').lower() == 'true'
if REQUIRE_MONGO and not mongo_client:
    app.logger.error('REQUIRE_MONGO is true but MongoDB connection is not available. Exiting.')
    sys.exit(1)

# Optional API key to protect /detect during development/production. If not set,
# the endpoint is publicly callable (subject to network rules).
DETECTION_API_KEY = os.environ.get('DETECTION_API_KEY')


@app.route('/api/detect', methods=['POST', 'OPTIONS'])
def detect():
    if request.method == 'OPTIONS':
        # Handle preflight request
        response = jsonify({'status': 'preflight'})
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type, x-api-key, Authorization')
        response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
        return response
        
    try:
        # Enforce API key if configured
        if DETECTION_API_KEY:
            auth = request.headers.get('Authorization', '')
            token = None
            if auth.lower().startswith('bearer '):
                token = auth.split(None, 1)[1].strip()
            token = token or request.headers.get('x-api-key') or request.args.get('api_key')
            if token != DETECTION_API_KEY:
                response = jsonify({'error': 'unauthorized'})
                response.headers.add('Access-Control-Allow-Origin', '*')
                return response, 401

        # Accept multipart/form-data file or JSON {dataUrl: 'data:...'}
        img_bytes, err = _extract_image_bytes_from_request()
        if err is not None:
            err_body, err_status = err
            response = jsonify(err_body)
            response.headers.add('Access-Control-Allow-Origin', '*')
            return response, err_status

        resp_body, resp_status = _process_image_bytes(img_bytes, request.remote_addr)
        response = jsonify(resp_body)
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response, resp_status


        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/sessions/<session_id>/metrics', methods=['POST', 'OPTIONS'])
def post_session_metrics(session_id):
    if request.method == 'OPTIONS':
        response = jsonify({'status': 'preflight'})
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type, x-api-key, Authorization')
        response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
        return response

    try:
        # Validate session exists in memory or allow creation if not
        if session_id not in sessions:
            # If we don't have in-memory session, still allow metrics if sessions_collection has it
            if sessions_collection is None:
                response = jsonify({'error': 'Session not found'})
                response.headers.add('Access-Control-Allow-Origin', '*')
                return response, 404

        if not request.is_json:
            response = jsonify({'error': 'Request must be JSON'})
            response.headers.add('Access-Control-Allow-Origin', '*')
            return response, 400

        data = request.get_json() or {}

        # Attach timestamp and source
        metrics_doc = {
            'session_id': session_id,
            'timestamp': datetime.now(timezone.utc),
            'source': request.remote_addr,
            'metrics': data,
        }

        # Persist metrics (best-effort)
        try:
            if metrics_collection is not None:
                col = metrics_collection
            else:
                col = mongo_db.get_collection('metrics') if mongo_db is not None else None
            if col is not None:
                to_insert = dict(metrics_doc)
                col.insert_one(to_insert)

            # Also push to the session document for quick aggregation (best-effort)
            if sessions_collection is not None:
                sc = sessions_collection
            else:
                sc = mongo_db.get_collection('sessions') if mongo_db is not None else None
            if sc is not None:
                sc.update_one({'_id': session_id}, {'$set': {'last_activity': metrics_doc['timestamp']}, '$push': {'metrics': metrics_doc}}, upsert=True)
        except Exception as e:
            app.logger.warning(f'Failed to persist metrics: {e}')

        response = jsonify({'status': 'ok'})
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response, 201
    except Exception as e:
        app.logger.error(f'Error in post_session_metrics: {str(e)}', exc_info=True)
        response = jsonify({'error': 'Internal server error', 'details': str(e)})
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response, 500


# Session management
sessions = {}

@app.route('/api/sessions/start', methods=['POST', 'OPTIONS'])
def start_session():
    if request.method == 'OPTIONS':
        # Handle preflight request
        response = jsonify({'status': 'preflight'})
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type')
        response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
        return response
        
    try:
        # Ensure we can parse JSON
        if not request.is_json:
            return jsonify({'error': 'Request must be JSON'}), 400
            
        data = request.get_json()
        if data is None:
            return jsonify({'error': 'Invalid JSON'}), 400
            
        session_id = str(uuid.uuid4())
        
        # Ensure metadata is a dictionary
        metadata = data.get('metadata', {})
        if not isinstance(metadata, dict):
            metadata = {}
        
        session_data = {
            'session_id': session_id,
            'start_time': datetime.now(timezone.utc),
            'end_time': None,
            'status': 'active',
            'metadata': metadata,
            'frames_processed': 0,
            'detections': []
        }
        
        sessions[session_id] = session_data
        
        # persist session document (best-effort)
        try:
            if sessions_collection is not None:
                col = sessions_collection
            else:
                col = mongo_db.get_collection('sessions') if mongo_db is not None else None
            if col is not None:
                col.update_one({'_id': session_id}, {'$set': session_data}, upsert=True)
        except Exception as e:
            app.logger.error(f'Failed to save session to MongoDB: {e}')
        
        response = jsonify({
            'session_id': session_id,
            'status': 'started',
            'start_time': session_data['start_time'].isoformat(),
            'message': 'Session started successfully'
        })
        
        # Add CORS headers
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response, 201
        
    except Exception as e:
        app.logger.error(f'Error in start_session: {str(e)}', exc_info=True)
        response = jsonify({
            'error': 'Internal server error',
            'details': str(e)
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response, 500

@app.route('/api/sessions/<session_id>/end', methods=['POST', 'OPTIONS'])
def end_session(session_id):
    if request.method == 'OPTIONS':
        # Handle preflight request
        response = jsonify({'status': 'preflight'})
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type')
        response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
        return response
    
    try:
        if session_id not in sessions:
            response = jsonify({'error': 'Session not found'})
            response.headers.add('Access-Control-Allow-Origin', '*')
            return response, 404
        
        end_time = datetime.now(timezone.utc)
        sessions[session_id].update({
            'end_time': end_time,
            'status': 'completed'
        })
        
        try:
            if sessions_collection is not None:
                col = sessions_collection
            else:
                col = mongo_db.get_collection('sessions') if mongo_db is not None else None
            if col is not None:
                col.update_one({'_id': session_id}, {'$set': {'end_time': end_time, 'status': 'completed'}})
        except Exception as e:
            app.logger.error(f'Failed to update session in MongoDB: {e}')
        
        response = jsonify({
            'session_id': session_id,
            'status': 'completed',
            'end_time': end_time.isoformat(),
            'message': 'Session ended successfully'
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response
        
    except Exception as e:
        app.logger.error(f'Error in end_session: {str(e)}', exc_info=True)
        response = jsonify({
            'error': 'Internal server error',
            'details': str(e)
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response, 500

@app.route('/api/sessions/<session_id>/detect', methods=['POST', 'OPTIONS'])
def detect_with_session(session_id):
    if request.method == 'OPTIONS':
        # Handle preflight request
        response = jsonify({'status': 'preflight'})
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type, x-api-key, Authorization')
        response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
        return response
    
    try:
        if session_id not in sessions:
            # Try to hydrate session from MongoDB if available
            try:
                sc = sessions_collection if sessions_collection is not None else (mongo_db.get_collection('sessions') if mongo_db is not None else None)
                if sc is not None:
                    doc = sc.find_one({'_id': session_id})
                    if doc:
                        # Normalize into in-memory session structure
                        sessions[session_id] = {
                            'session_id': session_id,
                            'start_time': doc.get('start_time'),
                            'end_time': doc.get('end_time'),
                            'status': doc.get('status', 'active'),
                            'metadata': doc.get('metadata', {}),
                            'frames_processed': doc.get('frames_processed', 0),
                            'detections': doc.get('detections', [])
                        }
            except Exception:
                pass

        if session_id not in sessions:
            response = jsonify({'error': 'Session not found or expired'})
            response.headers.add('Access-Control-Allow-Origin', '*')
            return response, 404
        
        # Extract image bytes from request
        img_bytes, err = _extract_image_bytes_from_request()
        if err is not None:
            err_body, err_status = err
            response = jsonify(err_body)
            response.headers.add('Access-Control-Allow-Origin', '*')
            return response, err_status

        resp_body, resp_status = _process_image_bytes(img_bytes, request.remote_addr)

        # If detection was successful, log it to the session
        if resp_status == 200:
            try:
                detection_data = {
                    'timestamp': datetime.now(timezone.utc),
                    'data': resp_body,
                    'source': request.remote_addr
                }

                sessions[session_id]['detections'].append(detection_data)
                sessions[session_id]['frames_processed'] = len(sessions[session_id]['detections'])

                try:
                    if detections_collection is not None:
                        col = detections_collection
                    else:
                        col = mongo_db.get_collection('detections') if mongo_db is not None else None
                    if col is not None:
                        col.insert_one({'session_id': session_id, **detection_data})
                except Exception as e:
                    app.logger.error(f'Failed to save detection to MongoDB: {e}')

                # Update session in memory
                sessions[session_id]['last_activity'] = detection_data['timestamp']

            except Exception as e:
                app.logger.error(f'Error processing detection data: {str(e)}', exc_info=True)

        response = jsonify(resp_body)
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response, resp_status
        
    except Exception as e:
        app.logger.error(f'Error in detect_with_session: {str(e)}', exc_info=True)
        response = jsonify({
            'error': 'Internal server error',
            'details': str(e)
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response, 500

@app.route('/api/sessions/<session_id>', methods=['GET', 'OPTIONS'])
def get_session(session_id):
    if request.method == 'OPTIONS':
        # Handle preflight request
        response = jsonify({'status': 'preflight'})
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS')
        return response
    
    try:
        if session_id not in sessions:
            response = jsonify({'error': 'Session not found'})
            response.headers.add('Access-Control-Allow-Origin', '*')
            return response, 404
        
        session = sessions[session_id].copy()
        # Convert datetime objects to ISO format for JSON serialization
        for time_field in ['start_time', 'end_time', 'last_activity']:
            if session.get(time_field):
                if hasattr(session[time_field], 'isoformat'):
                    session[time_field] = session[time_field].isoformat()
        
        response = jsonify({
            'session_id': session_id,
            'status': session.get('status', 'unknown'),
            'start_time': session.get('start_time'),
            'end_time': session.get('end_time'),
            'last_activity': session.get('last_activity'),
            'frames_processed': session.get('frames_processed', 0),
            'metadata': session.get('metadata', {})
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response
        
    except Exception as e:
        app.logger.error(f'Error in get_session: {str(e)}', exc_info=True)
        response = jsonify({
            'error': 'Internal server error',
            'details': str(e)
        })
        response.headers.add('Access-Control-Allow-Origin', '*')
        return response, 500

@app.route('/health', methods=['GET'])
def health():
    """Health endpoint: reports basic app + MongoDB connectivity.

    Returns 200 when MongoDB is reachable (if configured), otherwise 503.
    """
    status = {'ok': True}
    db_ok = False
    try:
        if mongo_client:
            # ping the server
            mongo_client.admin.command('ping')
            db_ok = True
    except Exception:
        db_ok = False

    status['mongo'] = db_ok
    status['mongo_db'] = os.environ.get('MONGO_DB', 'neurovision')
    status['require_mongo'] = REQUIRE_MONGO
    return (jsonify(status), 200) if db_ok or not REQUIRE_MONGO else (jsonify(status), 503)


@app.route('/', methods=['GET'])
def index():
    # Small landing page for convenience
    return (
        "<html><body><h3>NeuroVision backend</h3>"
        "<p>Health: <a href='/health'>/health</a></p>"
        "<p>POST to <code>/detect</code> with multipart form 'image=@file'</p>"
        "</body></html>",
        200,
    )


# Ensure CORS headers are always present even if flask-cors isn't installed
@app.after_request
def _add_cors_headers(response):
    # Mirror configured origins when possible
    try:
        if CORS_ORIGINS == '*':
            origin_header = '*'
        else:
            origin_header = ','.join(CORS_ORIGINS)
    except Exception:
        origin_header = '*'
    response.headers['Access-Control-Allow-Origin'] = origin_header
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
    response.headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'
    return response


if __name__ == '__main__':
    # Allow overriding host/port via env for flexibility
    host = os.environ.get('APP_HOST', '0.0.0.0')
    port = int(os.environ.get('APP_PORT', 5000))
    # Run without the automatic reloader on Windows to avoid socket/thread
    # issues observed with the debugger/reloader (select() on closed fd).
    app.run(host=host, port=port, debug=True, use_reloader=False)
