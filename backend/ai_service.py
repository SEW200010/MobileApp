"""
Face identification microservice — SCRFD detection + ArcFace 512-D embeddings.

Architecture notes, because these are the parts that changed:

* ONE datastore. Embeddings live in MySQL (passengers.embedding_bin) and
  nowhere else. The previous version wrote enrollments to ChromaDB while
  registration wrote to MySQL, so the two search endpoints could not see each
  other's passengers.

* The index lives in this process. All embeddings are loaded once into a single
  numpy matrix, so a 1:N search is one matrix-vector product. The previous
  version had Node POST every passenger's embedding on every gate check; at
  30,000 passengers that is roughly 300 MB of JSON per request.

* Three outcomes, not two. A 1:N system that only answers open/closed will
  confidently return the wrong person whenever the frame is marginal.

    pip install flask flask-cors insightface onnxruntime mysql-connector-python numpy opencv-python
    python ai_service.py
"""

import os
import threading
from datetime import datetime

import cv2
import numpy as np
from flask import Flask, jsonify, request
from flask_cors import CORS
from mysql.connector import pooling
from insightface.app import FaceAnalysis

# ---------------------------------------------------------------------------
# Thresholds
# ---------------------------------------------------------------------------
# THESE ARE PLACEHOLDERS. Run calibrate_threshold.py against your own images
# and replace them with the measured values before quoting any accuracy figure.
#
# Two reasons the numbers must be measured rather than copied:
#   1. A 1:1 threshold does not transfer to 1:N. Comparing against N enrolled
#      people gives roughly N chances for a stranger to score high, so the
#      threshold has to rise as the gallery grows.
#   2. Thresholds are model-specific. A value quoted for a different face model
#      says nothing about buffalo_l.
IDENTIFY_THRESHOLD = float(os.environ.get("FACE_IDENTIFY_THRESHOLD", "0.50"))
REVIEW_THRESHOLD = float(os.environ.get("FACE_REVIEW_THRESHOLD", "0.40"))

# If the top two candidates score within this of each other, the system cannot
# tell them apart and must not pick one. Siblings, twins and poor frames all
# land here.
MIN_MARGIN = float(os.environ.get("FACE_MIN_MARGIN", "0.05"))

TOP_K = 5

# Probe quality floors. Below these, a match is not trustworthy enough to open
# a gate on, so the result is downgraded to "review" rather than accepted.
MIN_PROBE_FACE_PX = 70
MIN_PROBE_SHARPNESS = 25.0

DET_SIZE = (640, 640)
DET_THRESH = 0.45
MAX_SIDE = 1600
EMBEDDING_DIM = 512

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "127.0.0.1"),
    "port": int(os.environ.get("DB_PORT", "3306")),
    "user": os.environ.get("DB_USER", "root"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "database": os.environ.get("DB_NAME", "airport_db"),
}

# Images referenced by path must sit under here. Without this the service will
# read any file on disk that a caller names.
UPLOAD_ROOT = os.path.realpath(
    os.environ.get("UPLOAD_ROOT", r"D:\MobileAPP\backend\uploads")
)

app = Flask(__name__)
CORS(app)
app.config["MAX_CONTENT_LENGTH"] = 12 * 1024 * 1024

pool = pooling.MySQLConnectionPool(pool_name="faces", pool_size=5, **DB_CONFIG)


# ---------------------------------------------------------------------------
# Face engine
# ---------------------------------------------------------------------------
class Engine:
    def __init__(self):
        # allowed_modules trims the bundle to what we use. The default loads
        # landmark and gender/age models too, which is pure overhead here.
        self.app = FaceAnalysis(
            name="buffalo_l",
            providers=["CPUExecutionProvider"],
            allowed_modules=["detection", "recognition"],
        )
        # ctx_id=-1 is CPU. The old code passed ctx_id=0 (GPU device 0) while
        # requesting CPUExecutionProvider — contradictory.
        self.app.prepare(ctx_id=-1, det_size=DET_SIZE, det_thresh=DET_THRESH)
        self.lock = threading.Lock()

    def analyse(self, img):
        with self.lock:
            return self.app.get(img)


engine = Engine()


def decode_image(buf):
    img = cv2.imdecode(np.frombuffer(buf, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        return None
    h, w = img.shape[:2]
    if max(h, w) > MAX_SIDE:
        s = MAX_SIDE / max(h, w)
        img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    return img


def read_request_image():
    """Multipart upload preferred; a path is accepted but sandboxed."""
    f = request.files.get("image")
    if f is not None and f.filename:
        return decode_image(f.read()), None

    data = request.get_json(silent=True) or {}
    rel = data.get("image_path") or request.form.get("image_path")
    if not rel:
        return None, "no image supplied"

    # Accept either an absolute path already inside UPLOAD_ROOT or one relative
    # to it, but never anything that escapes it.
    candidate = rel if os.path.isabs(rel) else os.path.join(UPLOAD_ROOT, rel)
    resolved = os.path.realpath(candidate)
    if resolved != UPLOAD_ROOT and not resolved.startswith(UPLOAD_ROOT + os.sep):
        return None, "image path outside the allowed directory"
    if not os.path.isfile(resolved):
        return None, "image file not found"

    with open(resolved, "rb") as fh:
        img = decode_image(fh.read())
    return img, None if img is not None else "could not decode image"


def crop(img, bbox):
    h, w = img.shape[:2]                       # re-read AFTER any resize
    x1, y1 = max(0, int(bbox[0])), max(0, int(bbox[1]))
    x2, y2 = min(w, int(bbox[2])), min(h, int(bbox[3]))
    if x2 - x1 < 4 or y2 - y1 < 4:
        return None
    return img[y1:y2, x1:x2]


def sharpness(face_crop):
    """Laplacian variance on a size-normalised crop.

    NOTE: this is a FOCUS measure, not anti-spoofing. A sharp photograph shown
    on a phone screen scores highly and passes. Presentation-attack detection
    needs a dedicated model (MiniFASNet or similar) and is not implemented here
    — do not describe this function as a spoofing defence.
    """
    if face_crop is None or face_crop.size == 0:
        return 0.0
    small = cv2.resize(face_crop, (112, 112), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def embed(face):
    v = np.asarray(face.embedding, dtype=np.float32)
    n = float(np.linalg.norm(v))
    if n < 1e-6:
        return None
    return v / n                                # unit length -> cosine == dot


# ---------------------------------------------------------------------------
# In-memory index
# ---------------------------------------------------------------------------
class FaceIndex:
    def __init__(self):
        self._lock = threading.Lock()
        self._matrix = np.zeros((0, EMBEDDING_DIM), np.float32)
        self._meta = []
        self._loaded_at = None

    def reload(self):
        conn = pool.get_connection()
        try:
            cur = conn.cursor(dictionary=True)
            cur.execute(
                "SELECT id, full_name, passport_number, flight_number, "
                "check_in_status, embedding_bin FROM passengers "
                "WHERE embedding_bin IS NOT NULL"
            )
            rows = cur.fetchall()
            cur.close()
        finally:
            conn.close()

        vecs, meta = [], []
        for r in rows:
            v = np.frombuffer(r["embedding_bin"], dtype=np.float32)
            if v.size != EMBEDDING_DIM:
                app.logger.warning("id=%s has %d dims, skipping", r["id"], v.size)
                continue
            vecs.append(v)
            meta.append({
                "id": r["id"],
                "name": r["full_name"],
                "passport": r["passport_number"],
                "flight": r["flight_number"],
                "check_in_status": r["check_in_status"],
            })

        m = (np.vstack(vecs).astype(np.float32) if vecs
             else np.zeros((0, EMBEDDING_DIM), np.float32))
        with self._lock:
            self._matrix, self._meta = m, meta
            self._loaded_at = datetime.utcnow()
        return len(meta)

    def search(self, probe, k=TOP_K):
        with self._lock:
            m, meta = self._matrix, self._meta
        if m.shape[0] == 0:
            return []
        scores = m @ probe.astype(np.float32)
        k = min(k, scores.shape[0])
        idx = np.argpartition(-scores, k - 1)[:k]
        idx = idx[np.argsort(-scores[idx])]
        return [{**meta[i], "score": round(float(scores[i]), 4)} for i in idx]

    def stats(self):
        with self._lock:
            return {
                "enrolled": len(self._meta),
                "loaded_at": (self._loaded_at.isoformat() + "Z"
                              if self._loaded_at else None),
            }


index = FaceIndex()


def decide(cands, quality):
    """Map scores to one of: identified / review / no_match."""
    if not cands:
        return "no_match", "No passengers enrolled"

    top = cands[0]["score"]
    second = cands[1]["score"] if len(cands) > 1 else -1.0
    margin = top - second

    if top < REVIEW_THRESHOLD:
        return "no_match", "No enrolled passenger resembles this face"
    if top < IDENTIFY_THRESHOLD:
        return "review", "Weak match — needs manual confirmation"
    if margin < MIN_MARGIN:
        return "review", (f"Top two candidates differ by only {margin:.3f} — "
                          f"cannot separate them automatically")
    if quality["face_px"] < MIN_PROBE_FACE_PX:
        return "review", f"Face only {quality['face_px']}px wide"
    if quality["sharpness"] < MIN_PROBE_SHARPNESS:
        return "review", "Frame too blurry to accept automatically"
    return "identified", "Confident match"


def log_search(outcome, cands, quality):
    top = cands[0] if cands else None
    second = cands[1]["score"] if len(cands) > 1 else None
    conn = pool.get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO face_search_log (searched_at, outcome, top_passenger_id,"
            " top_score, second_score, face_px, sharpness, requester_ip)"
            " VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
            (datetime.utcnow(), outcome,
             top["id"] if top else None, top["score"] if top else None, second,
             quality.get("face_px"), quality.get("sharpness"),
             request.headers.get("X-Forwarded-For", request.remote_addr)),
        )
        conn.commit()
        cur.close()
    except Exception:                                            # noqa: BLE001
        app.logger.exception("audit log failed")
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "index": index.stats(),
        "thresholds": {"identify": IDENTIFY_THRESHOLD,
                       "review": REVIEW_THRESHOLD,
                       "min_margin": MIN_MARGIN},
        "anti_spoofing": False,
    })


@app.route("/index/reload", methods=["POST"])
def reload_index():
    return jsonify({"status": "ok", "enrolled": index.reload()})


@app.route("/extract-embedding", methods=["POST"])
def extract_embedding():
    """Called by Node during registration. Returns the vector as hex.

    Hex rather than a JSON float array: 512 floats as JSON is roughly 10 KB and
    loses precision on the round trip. Hex is 1 KB and exact, and Node writes it
    straight into a VARBINARY column with UNHEX().
    """
    img, err = read_request_image()
    if err:
        return jsonify({"status": "error", "message": err}), 400

    faces = engine.analyse(img)
    if not faces:
        return jsonify({"status": "error", "message": "No face detected"}), 422
    if len(faces) > 1:
        return jsonify({"status": "error",
                        "message": f"{len(faces)} faces found — need exactly one"}), 422

    face = faces[0]
    c = crop(img, face.bbox)
    sharp = sharpness(c)
    face_px = int(face.bbox[2] - face.bbox[0])

    if face_px < 100:
        return jsonify({"status": "error",
                        "message": f"Face only {face_px}px wide — retake closer"}), 422
    if sharp < 30.0:
        return jsonify({"status": "error",
                        "message": f"Photo too blurry (sharpness {sharp:.0f})"}), 422

    vec = embed(face)
    if vec is None:
        return jsonify({"status": "error", "message": "Degenerate embedding"}), 422

    return jsonify({
        "status": "ok",
        "embedding_hex": vec.tobytes().hex(),
        "dim": int(vec.size),
        "quality": {"face_px": face_px, "sharpness": round(sharp, 1),
                    "det_score": round(float(face.det_score), 3)},
    })


@app.route("/identify", methods=["POST"])
def identify():
    """1:N search against every enrolled passenger.

    Node sends only the image. Identity fields are returned only on a confident
    match; weaker results carry scores and ids so an operator can review without
    the service handing out passport numbers on a guess.
    """
    img, err = read_request_image()
    if err:
        return jsonify({"status": "error", "message": err}), 400

    faces = engine.analyse(img)
    if not faces:
        return jsonify({"status": "ok", "outcome": "no_face",
                        "message": "No face detected in the frame",
                        "candidates": []})

    face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
    vec = embed(face)
    if vec is None:
        return jsonify({"status": "error", "message": "Degenerate embedding"}), 422

    quality = {
        "face_px": int(face.bbox[2] - face.bbox[0]),
        "sharpness": round(sharpness(crop(img, face.bbox)), 1),
        "det_score": round(float(face.det_score), 3),
    }

    cands = index.search(vec, TOP_K)
    outcome, message = decide(cands, quality)
    log_search(outcome, cands, quality)

    payload = (cands if outcome == "identified"
               else [{"id": c["id"], "score": c["score"]} for c in cands])

    return jsonify({
        "status": "ok",
        "outcome": outcome,
        "message": message,
        "faces_in_frame": len(faces),
        "quality": quality,
        "candidates": payload,
        "thresholds": {"identify": IDENTIFY_THRESHOLD,
                       "review": REVIEW_THRESHOLD,
                       "min_margin": MIN_MARGIN},
    })


if __name__ == "__main__":
    n = index.reload()
    print(f"Loaded {n} enrolled passengers")
    if n == 0:
        print("WARNING: index is empty. Run embed_folder.py then push_to_db.py.")
    print(f"Thresholds: identify>={IDENTIFY_THRESHOLD} review>={REVIEW_THRESHOLD} "
          f"margin>={MIN_MARGIN}  (PLACEHOLDERS — calibrate before quoting)")
    app.run(host="127.0.0.1", port=5001, threaded=True)
