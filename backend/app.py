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
import requests
try:
    # Prefer the official Google GenAI client when available (user-provided snippet)
    from google import genai  # type: ignore
except Exception:
    genai = None
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

# Optional MongoDB initialization
MONGO_URI = os.environ.get('MONGO_URI')
REQUIRE_MONGO = os.environ.get('REQUIRE_MONGO', 'false').lower() == 'true'

mongo_client = None
mongo_db = None
sessions_collection = None
metrics_collection = None
detections_collection = None

if MongoClient is not None and MONGO_URI:
    try:
        mongo_client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        db_name = os.environ.get('MONGO_DB', 'neurovision')
        mongo_db = mongo_client[db_name]
        # Pre-create handles for common collections; they may be None in tests
        sessions_collection = mongo_db.get_collection('sessions')
        metrics_collection = mongo_db.get_collection('metrics')
        detections_collection = mongo_db.get_collection('detections')
    except Exception as e:
        app.logger.error(f'Failed to initialize MongoDB client: {e}', exc_info=True)
        mongo_client = None
        mongo_db = None
        sessions_collection = None
        metrics_collection = None
        detections_collection = None


def _extract_image_bytes_from_request():
    """Return (img_bytes, None) on success or (None, (body_dict, status)) on error."""
    # Accept multipart/form-data file or JSON {dataUrl: 'data:...'}
    if 'image' in request.files:
        f = request.files['image']
        return f.read(), None

    if not request.is_json:
        return None, ({'error': 'Request must be JSON when not using form-data'}, 400)

    data = request.get_json() or {}
    # support several names for base64 image payload
    data_url = data.get('dataUrl') or data.get('dataurl') or data.get('imageBase64') or data.get('image_base64')
    if not data_url:
        return None, ({'error': 'No image provided'}, 400)

    # If data_url is a data: URI, strip header
    if isinstance(data_url, str) and data_url.startswith('data:'):
        try:
            _, b64 = data_url.split(',', 1)
        except Exception:
            return None, ({'error': 'Invalid data URL'}, 400)
    else:
        b64 = data_url

    try:
        img_bytes = base64.b64decode(b64)
    except Exception:
        return None, ({'error': 'Failed to decode image data'}, 400)

    return img_bytes, None


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
            'sessionId': session_id,
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

            # Also push to the session document for quick aggregation (best-effort).
            # Use an upsert that ensures 'sessionId' is set so a unique index on
            # sessionId won't see null values.
            if sessions_collection is not None:
                sc = sessions_collection
            else:
                sc = mongo_db.get_collection('sessions') if mongo_db is not None else None
            if sc is not None:
                sc.update_one({'$or': [{'_id': session_id}, {'sessionId': session_id}]}, {'$set': {'last_activity': metrics_doc['timestamp'], 'sessionId': session_id}, '$push': {'metrics': metrics_doc}}, upsert=True)
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


def _process_image_bytes(img_bytes, remote_addr=None):
    """Process raw image bytes with MediaPipe face_mesh and return a JSON-serializable result plus HTTP status.
    This is a lightweight best-effort processor used by the /detect endpoints.
    """
    try:
        image = Image.open(io.BytesIO(img_bytes)).convert('RGB')
    except Exception as e:
        app.logger.error(f'Failed to open image: {e}')
        return {'error': 'Invalid image data'}, 400

    try:
        img_np = np.array(image)
        # MediaPipe expects RGB image
        results = face_mesh.process(img_np)
    except Exception as e:
        app.logger.error(f'Error running MediaPipe face mesh: {e}', exc_info=True)
        return {'error': 'Face processing failed'}, 500

    out = {'faces': 0, 'landmarks': [], 'face_area_percent': None}
    if not results or not getattr(results, 'multi_face_landmarks', None):
        return out, 200

    faces = results.multi_face_landmarks
    out['faces'] = len(faces)
    # Only return first face landmarks to keep payload small
    first = faces[0]
    lms = []
    xs = []
    ys = []
    for lm in first.landmark:
        lms.append({'x': lm.x, 'y': lm.y, 'z': lm.z})
        xs.append(lm.x)
        ys.append(lm.y)

    out['landmarks'] = lms

    try:
        minx = min(xs)
        maxx = max(xs)
        miny = min(ys)
        maxy = max(ys)
        area = max(0.0, (maxx - minx) * (maxy - miny) * 100.0)
        out['face_area_percent'] = area
    except Exception:
        out['face_area_percent'] = None

    return out, 200


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

        # Use a canonical field name that matches possible DB indexes (sessionId)
        # and also set the document _id to the session_id string so queries are fast.
        session_data = {
            '_id': session_id,
            'sessionId': session_id,
            'start_time': datetime.now(timezone.utc),
            'end_time': None,
            'status': 'active',
            'metadata': metadata,
            'frames_processed': 0,
            'detections': []
        }

        sessions[session_id] = session_data

        # persist session document (best-effort) -- ensure we set sessionId so a
        # unique index on sessionId won't see a null value.
        try:
            if sessions_collection is not None:
                col = sessions_collection
            else:
                col = mongo_db.get_collection('sessions') if mongo_db is not None else None
            if col is not None:
                # Upsert using either _id or sessionId to be robust to existing index
                col.update_one({'$or': [{'_id': session_id}, {'sessionId': session_id}]}, {'$set': session_data}, upsert=True)
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
        # If session not in memory (e.g., server restart or different worker),
        # try to hydrate from MongoDB so clients can still end sessions.
        if session_id not in sessions:
            try:
                sc = sessions_collection if sessions_collection is not None else (mongo_db.get_collection('sessions') if mongo_db is not None else None)
                if sc is not None:
                    doc = sc.find_one({'$or': [{'_id': session_id}, {'sessionId': session_id}]})
                    if doc:
                        sessions[session_id] = {
                            'session_id': session_id,
                            'start_time': doc.get('start_time'),
                            'end_time': doc.get('end_time'),
                            'status': doc.get('status', 'active'),
                            'metadata': doc.get('metadata', {}),
                            'frames_processed': doc.get('frames_processed', 0),
                            'detections': doc.get('detections', []),
                        }
            except Exception:
                pass

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
                    # Update by either _id or sessionId; ensure sessionId is set
                    col.update_one({'$or': [{'_id': session_id}, {'sessionId': session_id}]}, {'$set': {'end_time': end_time, 'status': 'completed', 'sessionId': session_id}}, upsert=False)
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
                        # Search by either the document _id or the indexed 'sessionId' field.
                        doc = sc.find_one({'$or': [{'_id': session_id}, {'sessionId': session_id}]})
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
                        # Use 'sessionId' to be consistent with session documents/indexes
                        col.insert_one({'sessionId': session_id, **detection_data})
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


@app.route('/api/sessions/<session_id>/report', methods=['GET'])
def session_report(session_id):
    """Generate a simple heuristic report for a session by aggregating stored metrics.
    This is a prototype heuristic and not medical advice.
    """
    try:
        # Resolve collections (support optional Mongo config)
        sc = sessions_collection if sessions_collection is not None else (mongo_db.get_collection('sessions') if mongo_db is not None else None)
        mc = metrics_collection if metrics_collection is not None else (mongo_db.get_collection('metrics') if mongo_db is not None else None)

        session_doc = None
        try:
            if sc is not None:
                session_doc = sc.find_one({'$or': [{'_id': session_id}, {'sessionId': session_id}]})
        except Exception:
            session_doc = None

        metrics_cursor = []
        try:
            if mc is not None:
                metrics_cursor = list(mc.find({'$or': [{'sessionId': session_id}, {'session_id': session_id}, {'_id': session_id}]}).sort('timestamp', 1))
        except Exception as e:
            app.logger.error(f'Error fetching metrics for report: {e}', exc_info=True)
            metrics_cursor = []

        if not metrics_cursor and session_doc is None:
            return jsonify({'error': 'No metrics or session found', 'session_id': session_id}), 404

        # Helpers
        def safe_get(doc, path, default=None):
            try:
                cur = doc
                for p in path.split('.'):
                    if isinstance(cur, dict):
                        cur = cur.get(p, default)
                    else:
                        return default
                return cur
            except Exception:
                return default

        def avg(xs):
            return sum(xs) / len(xs) if xs else None

        attention = []
        drowsiness = []
        blink_rate = []
        face_area = []
        ear = []
        timestamps = []

        for m in metrics_cursor:
            timestamps.append(str(m.get('timestamp')))
            a = safe_get(m, 'metrics.attentionPercent') or safe_get(m, 'attentionPercent')
            d = safe_get(m, 'metrics.drowsinessPercent') or safe_get(m, 'drowsinessPercent')
            br = safe_get(m, 'metrics.blinkRate') or safe_get(m, 'blinkRate')
            fa = safe_get(m, 'metrics.faceAreaPercent') or safe_get(m, 'faceAreaPercent')
            e = safe_get(m, 'metrics.ear') or safe_get(m, 'ear')
            try:
                if a is not None:
                    attention.append(float(a))
            except Exception:
                pass
            try:
                if d is not None:
                    drowsiness.append(float(d))
            except Exception:
                pass
            try:
                if br is not None:
                    blink_rate.append(float(br))
            except Exception:
                pass
            try:
                if fa is not None:
                    face_area.append(float(fa))
            except Exception:
                pass
            try:
                if e is not None:
                    ear.append(float(e))
            except Exception:
                pass

        report = {
            'session_id': session_id,
            'metrics_count': len(metrics_cursor),
            'summary': {
                'avg_attention': avg(attention),
                'avg_drowsiness': avg(drowsiness),
                'avg_blink_rate': avg(blink_rate),
                'avg_face_area': avg(face_area),
                'avg_ear': avg(ear),
            },
            'flags': [],
            'recommendations': [],
            'raw': {
                'timestamps': timestamps,
                'attention': attention,
                'drowsiness': drowsiness,
                'blink_rate': blink_rate,
                'face_area': face_area,
                'ear': ear,
            }
        }

        # Heuristics
        try:
            if report['summary']['avg_drowsiness'] is not None and report['summary']['avg_drowsiness'] >= 60.0:
                report['flags'].append({'code': 'high_drowsiness', 'message': 'Elevated drowsiness detected'})
            if report['summary']['avg_attention'] is not None and report['summary']['avg_attention'] < 40.0:
                report['flags'].append({'code': 'low_attention', 'message': 'Low attention/engagement detected'})
            if report['summary']['avg_blink_rate'] is not None and (report['summary']['avg_blink_rate'] > 40.0 or report['summary']['avg_blink_rate'] < 2.0):
                report['flags'].append({'code': 'abnormal_blink_rate', 'message': 'Abnormal blink rate observed'})
            if report['summary']['avg_face_area'] is not None and report['summary']['avg_face_area'] < 5.0:
                report['flags'].append({'code': 'small_face_area', 'message': 'Face small in frame (poor visibility) — results may be unreliable'})
            if report['summary']['avg_ear'] is not None and report['summary']['avg_ear'] < 0.12:
                report['flags'].append({'code': 'very_low_ear', 'message': 'Eyes frequently closed or nearly closed'})
        except Exception:
            pass

        if any(f['code'] == 'high_drowsiness' for f in report['flags']):
            report['recommendations'].append('Suggest a break and a short rest; avoid driving or operating machinery.')
        if any(f['code'] == 'low_attention' for f in report['flags']):
            report['recommendations'].append('Encourage focused tasks, reduce distractions, or repeat the test under quieter conditions.')
        if any(f['code'] == 'abnormal_blink_rate' for f in report['flags']):
            report['recommendations'].append('Consider evaluating for dry eyes, fatigue, or medication side-effects.')
        if not report['flags']:
            report['recommendations'].append('No immediate concerns detected by heuristic analysis.')

        # If Gemini/LLM is configured, send the metrics as a prompt for an assistant analysis.
        gemini_key = os.environ.get('GEMINI_API_KEY')
        gemini_url = os.environ.get('GEMINI_URL')
        gemini_timeout = float(os.environ.get('GEMINI_TIMEOUT', '6.0'))
        gemini_model = os.environ.get('GEMINI_MODEL', 'gemini-2.5-flash')

        # Build a concise prompt
        prompt_lines = [
            "You are a clinical reasoning assistant. Analyze the following session metrics and provide:",
            "1) A short plain-language assessment mentioning if there are possible neurological symptoms (tentative, non-diagnostic).",
            "2) If no neurological concerns, provide a brief generic well-being summary and suggestions.",
            "3) A short list of recommended next steps or follow-ups (non-medical, non-diagnostic guidance).",
            "\nSession metrics:\n"
        ]
        summary = report.get('summary', {})
        prompt_lines.append(f"metrics_count: {report.get('metrics_count')}")
        for k, v in summary.items():
            prompt_lines.append(f"{k}: {v}")
        prompt_lines.append("\nRecent values (first/last up to 10):")
        raw = report.get('raw', {})
        for key in ['attention', 'drowsiness', 'blink_rate', 'face_area', 'ear']:
            vals = raw.get(key, [])
            if vals:
                sample = vals[:5]
                prompt_lines.append(f"{key}: {sample} (total {len(vals)})")

        prompt_text = "\n".join(prompt_lines)

        # Prefer the official google.genai client when available and GEMINI_API_KEY present
        if genai is not None and gemini_key:
            try:
                try:
                    client = genai.Client()
                    # Use the models.generate_content API if present (user-provided sample)
                    # Some versions expose client.models.generate_content, others may differ.
                    gen_resp = None
                    try:
                        gen_resp = client.models.generate_content(model=gemini_model, contents=prompt_text)
                    except Exception:
                        # Fallback to a more generic call shape
                        gen_resp = client.generate(model=gemini_model, input=prompt_text)

                    # Extract text
                    ai_text = None
                    if gen_resp is not None:
                        if hasattr(gen_resp, 'text'):
                            ai_text = gen_resp.text
                        else:
                            try:
                                jr = gen_resp if isinstance(gen_resp, dict) else gen_resp.__dict__
                                ai_text = jr.get('output') or jr.get('text') or jr.get('result') or str(jr)
                            except Exception:
                                ai_text = str(gen_resp)

                    report['ai_analysis'] = ai_text
                except Exception as e:
                    app.logger.error(f'Error calling google.genai client: {e}', exc_info=True)
                    report['ai_analysis_error'] = {'error': str(e)}
            except Exception as e:
                app.logger.error(f'Unexpected error using genai: {e}', exc_info=True)
                report['ai_analysis_error'] = {'error': str(e)}

        # If genai client not available but GEMINI_URL is provided, fall back to HTTP
        elif gemini_key and gemini_url:
            try:
                headers = {
                    'Authorization': f'Bearer {gemini_key}',
                    'Content-Type': 'application/json'
                }
                payload = {'input': prompt_text, 'max_output_tokens': 512}
                resp = requests.post(gemini_url, headers=headers, json=payload, timeout=gemini_timeout)
                if resp.status_code == 200:
                    try:
                        jr = resp.json()
                        ai_text = None
                        if isinstance(jr, dict):
                            ai_text = jr.get('output') or jr.get('text') or jr.get('result') or jr.get('choices')
                            if isinstance(ai_text, list) and ai_text:
                                ai_text = ' '.join([str(x) for x in ai_text])
                            elif isinstance(ai_text, dict):
                                ai_text = ai_text.get('text') or str(ai_text)
                        if ai_text is None:
                            ai_text = resp.text
                        report['ai_analysis'] = ai_text
                    except Exception:
                        report['ai_analysis'] = resp.text
                else:
                    app.logger.warning(f'Gemini request failed: {resp.status_code} {resp.text}')
                    report['ai_analysis_error'] = {'status': resp.status_code, 'text': resp.text}
            except Exception as e:
                app.logger.error(f'Error calling Gemini via HTTP: {e}', exc_info=True)
                report['ai_analysis_error'] = {'error': str(e)}
        else:
            # No gemini config detected, skip AI analysis
            pass

        return jsonify(report), 200
    except Exception as e:
        app.logger.error(f'Error generating session report: {e}', exc_info=True)
        return jsonify({'error': 'Failed to generate report', 'details': str(e)}), 500

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
