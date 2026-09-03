import os
import cv2
import numpy as np
import chromadb
from flask import Flask, request, jsonify
from flask_cors import CORS
import insightface
from insightface.app import FaceAnalysis

app = Flask(__name__)
CORS(app)

# -------------------------------------------------------------
# 1. Vector Database Setup (ChromaDB)
# -------------------------------------------------------------
chroma_client = chromadb.PersistentClient(path="./airport_vector_db")
passenger_collection = chroma_client.get_or_create_collection(
    name="airport_passengers",
    metadata={"hnsw:space": "cosine"}
)

# -------------------------------------------------------------
# 2. AI Engine Setup (RetinaFace + ArcFace 512-d)
# -------------------------------------------------------------
# det_thresh=0.5 මඟින් දුර්වල ආලෝකයේ හෝ ඇලවුණු මුහුණු පවා නිවැරදිව detect වේ
face_app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'])
face_app.prepare(ctx_id=0, det_size=(640, 640), det_thresh=0.5)

# -------------------------------------------------------------
# 3. Helper Functions
# -------------------------------------------------------------
def check_liveness(face_crop):
    """
    Silent Anti-Spoofing Check.
    Laplacian variance මඟින් Phone screen හෝ Printouts වලින් වන 
    Presentation attacks (2D spoofing) ප්‍රතික්ෂේප කරයි.
    """
    if face_crop is None or face_crop.size == 0:
        return False, 0.0
    gray = cv2.cvtColor(face_crop, cv2.COLOR_BGR2GRAY)
    variance = cv2.Laplacian(gray, cv2.CV_64F).var()
    is_live = bool(variance > 70.0)
    return is_live, float(variance)

def process_face(image_path):
    """
    Image එකෙන් Face එක detect කර 512-d ArcFace vector එක ලබාගනී.
    """
    if not os.path.exists(image_path):
        print(f"[Error] File not found: {image_path}")
        return None, None

    img = cv2.imread(image_path)
    if img is None:
        print(f"[Error] Failed to load image: {image_path}")
        return None, None

    # Resolution එක අධික නම් resize කර detection වේගවත් කිරීම
    h, w = img.shape[:2]
    max_dim = 1280
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        img = cv2.resize(img, (int(w * scale), int(h * scale)))

    faces = face_app.get(img)
    if not faces:
        print(f"[Warning] No face detected in: {image_path}")
        return None, None

    # විශාලතම මුහුණ (Primary face) තෝරා ගැනීම
    primary_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))

    # Bounding Box එකෙන් මුහුණ crop කර ගැනීම
    bbox = primary_face.bbox.astype(int)
    x1, y1, x2, y2 = max(0, bbox[0]), max(0, bbox[1]), min(w, bbox[2]), min(h, bbox[3])
    cropped_face = img[y1:y2, x1:x2]

    # 512-d numerical embedding
    embedding = primary_face.embedding.astype(float).tolist()
    return embedding, cropped_face

def cosine_similarity(v1, v2):
    a = np.array(v1, dtype=np.float32)
    b = np.array(v2, dtype=np.float32)
    norm_a = np.linalg.norm(a)
    norm_b = np.linalg.norm(b)
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return float(np.dot(a, b) / (norm_a * norm_b))

# -------------------------------------------------------------
# 4. API Endpoints
# -------------------------------------------------------------

# Flutter App Registration / Extraction සඳහා (Node.js එකෙන් call කරන endpoint එක)
@app.route('/extract-embedding', methods=['POST'])
@app.route('/enroll-passenger', methods=['POST'])
def extract_embedding():
    try:
        data = request.get_json(force=True)
        image_path = data.get('image_path')
        passenger_id = data.get('passenger_id')
        name = data.get('name', 'Passenger')
        flight_no = data.get('flight_no', 'N/A')

        if not image_path:
            return jsonify({"status": "error", "message": "image_path is required"}), 400

        embedding, _ = process_face(image_path)
        if embedding is None:
            return jsonify({"status": "error", "message": "No clear face detected in image"}), 400

        # Passenger ID එකක් තිබේ නම් ChromaDB එකටද ඇතුළත් කරයි
        if passenger_id:
            passenger_collection.upsert(
                ids=[str(passenger_id)],
                embeddings=[embedding],
                metadatas=[{"name": name, "flight_no": flight_no, "passenger_id": passenger_id}]
            )

        return jsonify({
            "status": "ok",
            "embedding": embedding,
            "dim": len(embedding),
            "message": "Face embedding extracted successfully"
        }), 200

    except Exception as e:
        print(f"[Exception] extract-embedding: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500


# Gate Verification සඳහා (Node.js registered list එකක් එවන ක්‍රමය)
@app.route('/match-1-to-n', methods=['POST'])
def match_1_to_n():
    try:
        data = request.get_json(force=True)
        cctv_image_path = data.get('image_path')
        registered = data.get('registered', [])

        if not cctv_image_path:
            return jsonify({"status": "error", "message": "image_path is required"}), 400

        cctv_embedding, face_crop = process_face(cctv_image_path)
        if cctv_embedding is None:
            return jsonify({"status": "ok", "matched": None, "message": "No face detected at gate"}), 200

        # Liveness verification
        is_live, _ = check_liveness(face_crop)
        if not is_live:
            return jsonify({
                "status": "security_alert",
                "gate_status": "LOCKED",
                "message": "Spoof attack detected! Screen/Paper photo rejected."
            }), 403

        scored = []
        for p in registered:
            reg_emb = p.get('embedding')
            if not reg_emb:
                continue
            sim = cosine_similarity(cctv_embedding, reg_emb)
            scored.append({
                "id": p.get("id"),
                "name": p.get("name"),
                "similarity": sim,
                "confidence_pct": round(float((sim + 1.0) / 2.0 * 100.0), 2)
            })

        if not scored:
            return jsonify({"status": "ok", "matched": None, "message": "No registered passengers to match"}), 200

        scored_sorted = sorted(scored, key=lambda x: x["similarity"], reverse=True)
        best_match = scored_sorted[0]

        # ArcFace Threshold (0.45 - 0.48 අගය 99.8% නිරවද්‍යතාවයක් ලබා දෙයි)
        MATCH_THRESHOLD = 0.45

        if best_match["similarity"] >= MATCH_THRESHOLD:
            return jsonify({
                "status": "ok",
                "gate_status": "OPEN",
                "matched": best_match,
                "all_scores": scored_sorted
            }), 200
        else:
            return jsonify({
                "status": "ok",
                "gate_status": "LOCKED",
                "matched": None,
                "message": "Face mismatch. Access denied."
            }), 200

    except Exception as e:
        print(f"[Exception] match-1-to-n: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500


# ChromaDB Vector Search මඟින් සෘජුවම Gate Match කිරීමේ විකල්ප Endpoint එක
@app.route('/verify-gate-passenger', methods=['POST'])
def verify_gate():
    try:
        data = request.get_json(force=True)
        cctv_image_path = data.get('image_path')

        if not cctv_image_path:
            return jsonify({"status": "error", "message": "image_path is required"}), 400

        cctv_embedding, face_crop = process_face(cctv_image_path)
        if cctv_embedding is None:
            return jsonify({"status": "failed", "gate_status": "LOCKED", "message": "No face detected at gate"}), 200

        is_live, _ = check_liveness(face_crop)
        if not is_live:
            return jsonify({
                "status": "security_alert",
                "gate_status": "LOCKED",
                "message": "Spoof attack detected!"
            }), 403

        query_result = passenger_collection.query(
            query_embeddings=[cctv_embedding],
            n_results=1
        )

        if not query_result['ids'] or len(query_result['ids'][0]) == 0:
            return jsonify({"status": "failed", "gate_status": "LOCKED", "message": "No passengers in Vector DB"}), 200

        metadata = query_result['metadatas'][0][0]
        cosine_distance = query_result['distances'][0][0]
        similarity = 1.0 - cosine_distance

        if similarity >= 0.48:
            return jsonify({
                "status": "success",
                "gate_status": "OPEN",
                "passenger": metadata,
                "confidence_pct": round(similarity * 100, 2)
            }), 200
        else:
            return jsonify({
                "status": "failed",
                "gate_status": "LOCKED",
                "message": "Access Denied: Face mismatch"
            }), 200

    except Exception as e:
        print(f"[Exception] verify-gate-passenger: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=False)