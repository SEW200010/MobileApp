"""
Face identification microservice — SCRFD detection + ArcFace 512-D embeddings.

Architecture notes, because these are the parts that changed:

* ONE datastore. Embeddings live in MySQL (passengers.embedding_bin) and
  nowhere else.

* The index lives in this process. All embeddings are loaded once into a single
  numpy matrix, so a 1:N search is one matrix-vector product.

* Three outcomes, not two. A 1:N system that only answers open/closed will
  confidently return the wrong person whenever the frame is marginal.

* cctv_logs is a sightings table, not an event stream. A row is written only
  when a real candidate was found. no_face and no_match write nothing, so the
  operator view never fills with placeholder rows.

* Only this service writes cctv_logs. Node must not insert there as well, or
  every gate check produces two rows that disagree with each other.

    pip install flask flask-cors insightface onnxruntime mysql-connector-python numpy opencv-python
    python ai_service.py
"""

import os
import threading
from datetime import date, datetime, timezone
from decimal import Decimal
from functools import wraps

import cv2
import numpy as np
from flask import Flask, jsonify, request
from flask_cors import CORS
from mysql.connector import pooling
from insightface.app import FaceAnalysis

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
IDENTIFY_THRESHOLD = float(os.environ.get("FACE_IDENTIFY_THRESHOLD", "0.40"))
REVIEW_THRESHOLD = float(os.environ.get("FACE_REVIEW_THRESHOLD", "0.30"))
MIN_MARGIN = float(os.environ.get("FACE_MIN_MARGIN", "0.05"))

TOP_K = 5
MIN_PROBE_FACE_PX = int(os.environ.get("FACE_MIN_PROBE_PX", "70"))
MIN_PROBE_SHARPNESS = float(os.environ.get("FACE_MIN_PROBE_SHARPNESS", "25.0"))

# Enrolment gates, previously hard-coded inside the route.
MIN_ENROL_FACE_PX = int(os.environ.get("FACE_MIN_ENROL_PX", "100"))
MIN_ENROL_SHARPNESS = float(os.environ.get("FACE_MIN_ENROL_SHARPNESS", "30.0"))

DET_SIZE = (640, 640)
DET_THRESH = 0.45
MAX_SIDE = 1600
EMBEDDING_DIM = 512
EMBEDDING_MODEL = "buffalo_l"

# Rows flagged low_quality are excluded from the searchable index. They stay in
# the table so you can see who needs a better photo. Set to 1 to include them.
INCLUDE_LOW_QUALITY = os.environ.get("FACE_INCLUDE_LOW_QUALITY", "0") == "1"

# The index is rebuilt on demand after this many seconds, so a passenger
# enrolled by another process becomes searchable without a manual reload.
INDEX_TTL_SECONDS = int(os.environ.get("FACE_INDEX_TTL", "300"))

# Shared secret between Node and this service. When empty, the service runs
# unauthenticated and says so loudly at startup.
API_KEY = os.environ.get("FACE_API_KEY", "")

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "127.0.0.1"),
    "port": int(os.environ.get("DB_PORT", "3306")),
    "user": os.environ.get("DB_USER", "root"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "database": os.environ.get("DB_NAME", "airport_db"),
}
UPLOAD_ROOT = os.path.realpath(
    os.environ.get("UPLOAD_ROOT", r"D:\MobileAPP\backend\uploads")
)

# Frames posted as multipart are stored here. Node normally sends image_path
# instead, in which case its own file is used and nothing is copied.
CCTV_SAVE_DIR = os.path.join(UPLOAD_ROOT, "cctv")

# Stored paths are web paths under Express's /uploads static mount, so the
# admin page can render them directly.
CCTV_URL_PREFIX = os.environ.get("CCTV_URL_PREFIX", "uploads/")

# cctv_logs lives in its own schema on the same server. The DB user needs
# INSERT on it.
CCTV_LOG_DB = os.environ.get("CCTV_LOG_DB", "cctv_logs_db")
CCTV_LOG_TABLE = os.environ.get("CCTV_LOG_TABLE", "cctv_logs")
CCTV_LOG_FQN = f"`{CCTV_LOG_DB}`.`{CCTV_LOG_TABLE}`"

# Only these outcomes produce a cctv_logs row.
# Set FACE_CCTV_LOG_OUTCOMES=identified to log confident matches only.
CCTV_LOG_OUTCOMES = {
    o.strip() for o in
    os.environ.get("FACE_CCTV_LOG_OUTCOMES", "identified,review").split(",")
    if o.strip()
}

# Columns of `passengers` that must never reach an API response.
# `embedding` is the legacy TEXT column: ~10 KB of JSON per passenger, and it
# is the same biometric data as embedding_bin. It has no business leaving the
# service even though it is still in the schema.
HIDDEN_COLUMNS = {
    "embedding", "embedding_bin", "embedding_model",
    "face_quality", "face_enrolled_at", "enrolled_at", "low_quality",
    "password",
}

app = Flask(__name__)
CORS(app)
app.config["MAX_CONTENT_LENGTH"] = 12 * 1024 * 1024

pool = pooling.MySQLConnectionPool(pool_name="faces", pool_size=8, **DB_CONFIG)


def utcnow():
    """Timezone-aware UTC. datetime.utcnow() is naive and deprecated in 3.12."""
    return datetime.now(timezone.utc)


def require_key(fn):
    """Reject unauthenticated calls when FACE_API_KEY is configured."""
    @wraps(fn)
    def wrapper(*a, **kw):
        if API_KEY and request.headers.get("X-API-Key") != API_KEY:
            return jsonify({"status": "error", "message": "unauthorized"}), 401
        return fn(*a, **kw)
    return wrapper


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
# A face detector needs room around the head to place a box. In a portrait
# cropped to the jawline the face touches all four edges and SCRFD misses it
# outright — on the 256x256 gallery, half the files failed raw detection and
# every one of them was found after padding, at 135-149px.
#
# Replicating the border does not rescale anything, so face_px stays
# comparable with an unpadded frame and the quality thresholds keep their
# meaning. Only small images are padded; a wide CCTV frame already has context
# and padding it would just add pixels to scan.
PAD_BELOW_PX = int(os.environ.get("FACE_PAD_BELOW_PX", "512"))
PAD_RATIO = float(os.environ.get("FACE_PAD_RATIO", "0.4"))


def pad_for_detection(img):
    h, w = img.shape[:2]
    if min(h, w) > PAD_BELOW_PX:
        return img
    p = int(min(h, w) * PAD_RATIO)
    return cv2.copyMakeBorder(img, p, p, p, p, cv2.BORDER_REPLICATE)


class Engine:
    def __init__(self):
        self.app = FaceAnalysis(
            name=EMBEDDING_MODEL,
            providers=["CPUExecutionProvider"],
            allowed_modules=["detection", "recognition"],
        )
        self.app.prepare(ctx_id=-1, det_size=DET_SIZE, det_thresh=DET_THRESH)
        self.lock = threading.Lock()

    def analyse(self, img):
        """Returns (faces, work_img).

        work_img is the image the bounding boxes belong to. Every measurement
        and crop afterwards must use it — measuring on the original while the
        boxes came from the padded copy puts the crop in the wrong place.
        """
        padded = pad_for_detection(img)
        with self.lock:
            if padded is not img:
                faces = self.app.get(padded)
                if faces:
                    return faces, padded
            return self.app.get(img), img


engine = Engine()


# ---------------------------------------------------------------------------
# Image handling
# ---------------------------------------------------------------------------
def decode_image(buf):
    img = cv2.imdecode(np.frombuffer(buf, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        return None
    h, w = img.shape[:2]
    if max(h, w) > MAX_SIDE:
        s = MAX_SIDE / max(h, w)
        img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    return img


def to_web_path(resolved):
    """Absolute path inside UPLOAD_ROOT -> web path Express can serve."""
    rel = os.path.relpath(resolved, UPLOAD_ROOT).replace(os.sep, "/")
    return CCTV_URL_PREFIX + rel


def read_request_image():
    """Multipart upload preferred; a path is accepted but sandboxed.

    Returns (img, err, image_ref, owned). `image_ref` is a web path suitable
    for cctv_logs.cctv_image_url. `owned` is True only when this request
    created the file, which is the only case where deleting it is allowed.
    """
    f = request.files.get("image")
    if f is not None and f.filename:
        buf = f.read()
        img = decode_image(buf)
        ref, owned = None, False
        if img is not None:
            try:
                os.makedirs(CCTV_SAVE_DIR, exist_ok=True)
                fname = f"{utcnow():%Y%m%d_%H%M%S_%f}.jpg"
                with open(os.path.join(CCTV_SAVE_DIR, fname), "wb") as fh:
                    fh.write(buf)
                ref, owned = f"{CCTV_URL_PREFIX}cctv/{fname}", True
            except OSError:                                      # noqa: BLE001
                app.logger.exception("could not persist CCTV frame")
        return img, (None if img is not None else "could not decode image"), ref, owned

    data = request.get_json(silent=True) or {}
    rel = data.get("image_path") or request.form.get("image_path")
    if not rel:
        return None, "no image supplied", None, False

    # Accept either an absolute path already inside UPLOAD_ROOT or one relative
    # to it, but never anything that escapes it.
    candidate = rel if os.path.isabs(rel) else os.path.join(UPLOAD_ROOT, rel)
    resolved = os.path.realpath(candidate)
    if resolved != UPLOAD_ROOT and not resolved.startswith(UPLOAD_ROOT + os.sep):
        return None, "image path outside the allowed directory", None, False
    if not os.path.isfile(resolved):
        return None, "image file not found", None, False

    with open(resolved, "rb") as fh:
        img = decode_image(fh.read())
    # A caller-supplied file belongs to the caller — never delete it.
    return (img, (None if img is not None else "could not decode image"),
            to_web_path(resolved), False)


def discard_frame(image_ref, owned):
    """Remove a frame this request saved but never logged."""
    if not owned or not image_ref:
        return
    rel = image_ref[len(CCTV_URL_PREFIX):] if image_ref.startswith(CCTV_URL_PREFIX) \
        else image_ref
    path = os.path.realpath(os.path.join(UPLOAD_ROOT, rel))
    if not path.startswith(CCTV_SAVE_DIR + os.sep):
        return
    try:
        os.remove(path)
    except OSError:                                              # noqa: BLE001
        app.logger.warning("could not remove unused frame %s", image_ref)


def crop(img, bbox):
    h, w = img.shape[:2]                       # re-read AFTER any resize
    x1, y1 = max(0, int(bbox[0])), max(0, int(bbox[1]))
    x2, y2 = min(w, int(bbox[2])), min(h, int(bbox[3]))
    if x2 - x1 < 4 or y2 - y1 < 4:
        return None
    return img[y1:y2, x1:x2]


def sharpness(face_crop):
    if face_crop is None or face_crop.size == 0:
        return 0.0
    small = cv2.resize(face_crop, (112, 112), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def brightness_stats(img, bbox):
    x1, y1, x2, y2 = [int(v) for v in bbox]
    x1, y1 = max(x1, 0), max(y1, 0)
    x2, y2 = min(x2, img.shape[1]), min(y2, img.shape[0])
    if x2 - x1 < 4 or y2 - y1 < 4:
        return 0.0, 0.0
    g = cv2.cvtColor(img[y1:y2, x1:x2], cv2.COLOR_BGR2GRAY)
    return float(g.mean()), float(g.std())


def yaw_ratio(kps):
    """Head turn from the 5 keypoints. Frontal ~1.0, hard profile ~3.0."""
    if kps is None or len(kps) < 3:
        return 1.0
    leye, reye, nose = kps[0], kps[1], kps[2]
    eye_span = abs(float(reye[0] - leye[0]))
    if eye_span < 1e-3:
        return 1.0
    mid = (float(leye[0]) + float(reye[0])) / 2.0
    return 1.0 + abs(float(nose[0]) - mid) / eye_span * 4.0


def quality_score(face_px, sharp, det_score, yaw, contrast):
    """0-100 composite. Identical formula to embed_folder.py.

    Both enrolment paths — the bulk script and /register — must produce the
    same number, otherwise passengers.face_quality means two different things
    depending on how the passenger was enrolled and cannot be compared.
    """
    s_size = min(face_px / 120.0, 1.0)
    s_sharp = min(sharp / 60.0, 1.0)
    s_det = min(max((det_score - 0.3) / 0.6, 0.0), 1.0)
    s_yaw = min(max((2.5 - yaw) / 1.5, 0.0), 1.0)
    s_con = min(contrast / 45.0, 1.0)
    return round(100 * (0.30 * s_size + 0.30 * s_sharp +
                        0.20 * s_det + 0.10 * s_yaw + 0.10 * s_con), 1)


def measure(img, face):
    """Every quality number for one detected face, in one place."""
    c = crop(img, face.bbox)
    sharp = sharpness(c)
    _, contrast = brightness_stats(img, face.bbox)
    yaw = yaw_ratio(getattr(face, "kps", None))
    face_px = int(face.bbox[2] - face.bbox[0])
    det = float(face.det_score)
    return {
        "face_px": face_px,
        "sharpness": round(sharp, 1),
        "det_score": round(det, 3),
        "yaw": round(yaw, 2),
        "contrast": round(contrast, 1),
        "score": quality_score(face_px, sharp, det, yaw, contrast),
    }


def embed(face):
    v = np.asarray(face.embedding, dtype=np.float32)
    n = float(np.linalg.norm(v))
    if n < 1e-6:
        return None
    return v / n


# ---------------------------------------------------------------------------
# Index
# ---------------------------------------------------------------------------
class FaceIndex:
    def __init__(self):
        self._lock = threading.Lock()
        self._reload_lock = threading.Lock()
        self._matrix = np.zeros((0, EMBEDDING_DIM), np.float32)
        self._meta = []
        self._loaded_at = None
        self._skipped_low_quality = 0

    def reload(self):
        where = "embedding_bin IS NOT NULL"
        if not INCLUDE_LOW_QUALITY:
            where += " AND (low_quality IS NULL OR low_quality = 0)"

        conn = pool.get_connection()
        try:
            cur = conn.cursor(dictionary=True)
            cur.execute(
                "SELECT id, full_name, passport_number, flight_number, "
                f"check_in_status, embedding_bin FROM passengers WHERE {where}"
            )
            rows = cur.fetchall()
            cur.execute("SELECT COUNT(*) AS n FROM passengers "
                        "WHERE embedding_bin IS NOT NULL AND low_quality = 1")
            low = cur.fetchone()["n"]
            cur.close()
        finally:
            conn.close()

        vecs, meta, seen = [], [], {}
        for r in rows:
            v = np.frombuffer(r["embedding_bin"], dtype=np.float32)
            if v.size != EMBEDDING_DIM:
                app.logger.warning("id=%s has %d dims, skipping", r["id"], v.size)
                continue

            # Two passengers sharing one vector make the top-2 margin zero, so
            # every gate check involving either of them lands in review and no
            # amount of threshold tuning helps. Refuse to index the collision
            # and name both rows so it can actually be fixed.
            key = v.tobytes()
            if key in seen:
                app.logger.error(
                    "id=%s has the same embedding as id=%s — both excluded from "
                    "the index. Re-enrol them from different photos.",
                    r["id"], seen[key])
                continue
            seen[key] = r["id"]

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
            self._loaded_at = utcnow()
            self._skipped_low_quality = low
        return len(meta)

    def ensure_fresh(self):
        """Rebuild if the index has aged past its TTL."""
        with self._lock:
            loaded = self._loaded_at
        if loaded is not None and \
                (utcnow() - loaded).total_seconds() < INDEX_TTL_SECONDS:
            return
        # One rebuild at a time; other threads keep serving the old matrix.
        if self._reload_lock.acquire(blocking=False):
            try:
                self.reload()
            except Exception:                                    # noqa: BLE001
                app.logger.exception("scheduled index reload failed")
            finally:
                self._reload_lock.release()

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
                "excluded_low_quality": self._skipped_low_quality,
                "loaded_at": (self._loaded_at.isoformat()
                              if self._loaded_at else None),
                "ttl_seconds": INDEX_TTL_SECONDS,
            }


index = FaceIndex()


# ---------------------------------------------------------------------------
# Decision
# ---------------------------------------------------------------------------
def decide(cands, quality, index_empty):
    """Map scores to one of: identified / review / no_match.

    `index_empty` is separate from "nothing matched": an empty gallery is a
    deployment fault, not a rejected passenger, and conflating the two sends
    you looking in the wrong place.
    """
    if index_empty:
        return "no_match", ("Index is empty — no passenger has a usable "
                            "embedding. Check enrolment.")
    if not cands:
        return "no_match", "No enrolled passenger resembles this face"

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


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------
def jsonable(v):
    """Make a raw MySQL value safe for jsonify()."""
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (bytes, bytearray)):
        return None
    return v


def fetch_passenger(pid):
    """Full passengers row for a confirmed match, minus internal columns."""
    conn = pool.get_connection()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute("SELECT * FROM passengers WHERE id = %s", (pid,))
        row = cur.fetchone()
        cur.close()
    finally:
        conn.close()
    if not row:
        return None
    return {k: jsonable(v) for k, v in row.items() if k not in HIDDEN_COLUMNS}


_cctv_cols = None
_cctv_cols_lock = threading.Lock()


def cctv_columns():
    """Which columns cctv_logs actually has, so the optional passenger_id
    from the migration is used when present and skipped when it is not."""
    global _cctv_cols
    if _cctv_cols is not None:
        return _cctv_cols
    with _cctv_cols_lock:
        if _cctv_cols is not None:
            return _cctv_cols
        cols = set()
        conn = pool.get_connection()
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema = %s AND table_name = %s",
                (CCTV_LOG_DB, CCTV_LOG_TABLE),
            )
            cols = {r[0].lower() for r in cur.fetchall()}
            cur.close()
        except Exception:                                        # noqa: BLE001
            app.logger.exception("could not read cctv_logs schema")
        finally:
            conn.close()
        _cctv_cols = cols
        return cols


def log_search(outcome, cands, quality):
    """Technical audit trail — every request lands here, matched or not."""
    top = cands[0] if cands else None
    second = cands[1]["score"] if len(cands) > 1 else None
    conn = pool.get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO face_search_log (searched_at, outcome, top_passenger_id,"
            " top_score, second_score, face_px, sharpness, requester_ip)"
            " VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
            (utcnow().replace(tzinfo=None), outcome,
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


def log_cctv(outcome, cands, image_ref, details):
    """Operator-facing sighting row. Written only for a real match.

    Returns True if a row was inserted. Nothing is written for no_face or
    no_match, when there is no candidate, when the candidate has neither a
    passport number nor a name, or when the frame was not stored — every
    column here is NOT NULL, so a placeholder row would be pure noise.

    created_at is written explicitly in UTC. The column default is MySQL's
    local clock while face_search_log.searched_at is UTC, so leaving it to the
    default puts the two tables 5.5 hours apart and makes them impossible to
    correlate.
    """
    if outcome not in CCTV_LOG_OUTCOMES:
        return False

    top = cands[0] if cands else None
    if not top:
        return False

    passport = str((details or {}).get("passport_number")
                   or top.get("passport") or "").strip()
    name = str((details or {}).get("full_name") or top.get("name") or "").strip()
    if not passport and not name:
        app.logger.warning("skipping cctv_logs row: candidate id=%s has no "
                           "passport or name", top.get("id"))
        return False
    if not image_ref:
        app.logger.warning("skipping cctv_logs row: frame was not stored")
        return False

    cols = ["passport_number", "matched_name", "cctv_image_url",
            "confidence", "status", "created_at"]
    vals = [passport[:50], name[:255], image_ref[:65535],
            float(top["score"]), outcome[:100], utcnow().replace(tzinfo=None)]

    if "passenger_id" in cctv_columns():
        cols.append("passenger_id")
        vals.append(top.get("id"))

    placeholders = ",".join(["%s"] * len(cols))
    conn = pool.get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            f"INSERT INTO {CCTV_LOG_FQN} ({','.join(cols)}) "
            f"VALUES ({placeholders})",
            tuple(vals),
        )
        conn.commit()
        cur.close()
        return True
    except Exception:                                            # noqa: BLE001
        app.logger.exception("cctv log failed")
        return False
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
        "model": EMBEDDING_MODEL,
        "thresholds": {"identify": IDENTIFY_THRESHOLD,
                       "review": REVIEW_THRESHOLD,
                       "min_margin": MIN_MARGIN,
                       "min_probe_px": MIN_PROBE_FACE_PX,
                       "min_probe_sharpness": MIN_PROBE_SHARPNESS},
        "cctv_log_outcomes": sorted(CCTV_LOG_OUTCOMES),
        "authenticated": bool(API_KEY),
        "anti_spoofing": False,
    })


@app.route("/index/reload", methods=["POST"])
@require_key
def reload_index():
    return jsonify({"status": "ok", "enrolled": index.reload()})


@app.route("/extract-embedding", methods=["POST"])
@require_key
def extract_embedding():
    img, err, ref, owned = read_request_image()
    # Enrolment never belongs in the sighting folder.
    discard_frame(ref, owned)
    if err:
        return jsonify({"status": "error", "message": err}), 400

    faces, work = engine.analyse(img)
    if not faces:
        return jsonify({"status": "error", "message": "No face detected"}), 422
    if len(faces) > 1:
        return jsonify({"status": "error",
                        "message": f"{len(faces)} faces found — need exactly one"}), 422

    face = faces[0]
    q = measure(work, face)

    if q["face_px"] < MIN_ENROL_FACE_PX:
        return jsonify({
            "status": "error",
            "message": f"Face only {q['face_px']}px wide — need at least "
                       f"{MIN_ENROL_FACE_PX}px. Use a full-size photo, not a "
                       f"thumbnail.",
            "quality": q,
        }), 422
    if q["sharpness"] < MIN_ENROL_SHARPNESS:
        return jsonify({"status": "error",
                        "message": f"Photo too blurry (sharpness {q['sharpness']})",
                        "quality": q}), 422

    vec = embed(face)
    if vec is None:
        return jsonify({"status": "error", "message": "Degenerate embedding"}), 422

    return jsonify({
        "status": "ok",
        "embedding_hex": vec.tobytes().hex(),
        "dim": int(vec.size),
        "model": EMBEDDING_MODEL,
        "quality": q,
    })


@app.route("/identify", methods=["POST"])
@require_key
def identify():
    img, err, image_ref, owned = read_request_image()
    if err:
        discard_frame(image_ref, owned)
        return jsonify({"status": "error", "message": err}), 400

    index.ensure_fresh()

    faces, work = engine.analyse(img)
    if not faces:
        discard_frame(image_ref, owned)
        return jsonify({"status": "ok", "outcome": "no_face",
                        "message": "No face detected in the frame",
                        "passenger": None, "logged": False, "candidates": []})

    face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
    vec = embed(face)
    if vec is None:
        discard_frame(image_ref, owned)
        return jsonify({"status": "error", "message": "Degenerate embedding"}), 422

    quality = measure(work, face)
    cands = index.search(vec, TOP_K)
    outcome, message = decide(cands, quality,
                              index_empty=index.stats()["enrolled"] == 0)

    # The full record is released only once the match is confident. A "review"
    # stays redacted until an operator confirms it, so a stream of probe images
    # cannot be used to read out the passenger list.
    details = fetch_passenger(cands[0]["id"]) if (outcome == "identified" and cands) else None

    log_search(outcome, cands, quality)
    logged = log_cctv(outcome, cands, image_ref, details)
    if not logged:
        discard_frame(image_ref, owned)
        image_ref = None

    payload = (cands if outcome == "identified"
               else [{"id": c["id"], "score": c["score"]} for c in cands])

    return jsonify({
        "status": "ok",
        "outcome": outcome,
        "message": message,
        "passenger": details,
        "logged": logged,
        "image_ref": image_ref,
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
    print(f"cctv_logs rows written for: {sorted(CCTV_LOG_OUTCOMES)}")
    if not API_KEY:
        print("WARNING: FACE_API_KEY is not set — every endpoint is open to "
              "anyone who can reach this port.")
    app.run(host="127.0.0.1", port=5001, threaded=True)