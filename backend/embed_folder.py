"""
Folder of images -> face embeddings. No database involved.

Designed for messy input: mixed sizes, low resolution, blur, bad lighting,
unicode filenames. Detection escalates through several scales and a contrast
pass before giving up.

Nothing is rejected for quality. Every face that can be found is embedded, and
its measured quality is recorded alongside it, so the decision about what is
good enough happens later — with the numbers in front of you — instead of being
hard-coded here.

    python embed_folder.py --input dataset_faces
    python embed_folder.py --input dataset_faces --gpu
    python embed_folder.py --input dataset_faces --resume

Output:
    embeddings.npz          ids, vectors, quality columns
    embedding_report.csv    one row per input file, human readable
"""

import argparse
import hashlib
import os
import re
import sys
import time
from pathlib import Path

import cv2
import numpy as np

try:
    from insightface.app import FaceAnalysis
except ImportError:
    sys.exit("pip install insightface onnxruntime")

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}
ID_PATTERN = re.compile(r"^(\d+)")

# Detection cascade, cheapest first. A larger det_size means the detector sees
# more pixels of a small face — this, not pre-upscaling the image, is what
# actually recovers low-resolution faces. Pre-upscaling gets undone the moment
# the detector resizes its input back down to det_size.
DET_STAGES = [
    ((640, 640), 0.50, "det640"),
    ((1024, 1024), 0.50, "det1024"),
    ((1600, 1600), 0.40, "det1600"),
    ((2048, 2048), 0.30, "det2048"),
]

MAX_SIDE = 4000          # guard against a 12000px scan eating all the RAM

# A face detector needs room around the head to place a box. In a portrait
# cropped to the jawline the face touches all four edges, and SCRFD either
# misses it entirely or returns a spurious 10px box after escalating to 2048.
# Replicating the border by 40% costs nothing and fixes both: measured on the
# 256x256 gallery, raw detection failed on half the files while padded
# detection found every one of them at 135-149px.
#
# Only small images are padded. A wide CCTV frame already has plenty of
# context and padding it would just add pixels to scan.
PAD_BELOW_PX = 512
PAD_RATIO = 0.4


def pad_for_detection(img):
    """Give a tightly cropped face somewhere to sit. Scale is unchanged, so
    face_px stays comparable with an unpadded image."""
    h, w = img.shape[:2]
    if min(h, w) > PAD_BELOW_PX:
        return img
    p = int(min(h, w) * PAD_RATIO)
    return cv2.copyMakeBorder(img, p, p, p, p, cv2.BORDER_REPLICATE)


# --------------------------------------------------------------------------
def imread_any(path):
    """Reads through numpy so non-ASCII Windows paths work.

    cv2.imread silently returns None on a path with Sinhala or accented
    characters — it fails as though the file were corrupt, which is very hard
    to diagnose from the outside.
    """
    try:
        buf = np.fromfile(str(path), dtype=np.uint8)
    except OSError:
        return None
    if buf.size == 0:
        return None
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        return None

    h, w = img.shape[:2]
    if max(h, w) > MAX_SIDE:
        s = MAX_SIDE / max(h, w)
        img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    return img


def clahe_bgr(img):
    """Local contrast equalisation on the L channel.

    Recovers back-lit and under-exposed faces that the detector misses at every
    scale because the face has almost no local contrast to work with.
    """
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    l = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(l)
    return cv2.cvtColor(cv2.merge((l, a, b)), cv2.COLOR_LAB2BGR)


def sharpness(img, bbox):
    """Laplacian variance on a 112x112 normalised crop.

    Resizing to a fixed size first is essential: a large face has more
    high-frequency content simply by being large, so raw variance would measure
    image size rather than focus and every big blurry photo would score well.
    """
    x1, y1, x2, y2 = [int(v) for v in bbox]
    x1, y1 = max(x1, 0), max(y1, 0)
    x2, y2 = min(x2, img.shape[1]), min(y2, img.shape[0])
    if x2 - x1 < 8 or y2 - y1 < 8:
        return 0.0
    crop = cv2.resize(img[y1:y2, x1:x2], (112, 112), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
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
    """Head turn from the 5 keypoints: eyes, nose, mouth corners.

    Measured as the nose's horizontal offset from the eye midpoint, scaled by
    the eye separation. Frontal gives ~1.0, a hard profile ~3.0.

    The earlier version divided the two nose-to-eye distances by each other,
    which blew up to 20-90 whenever the nose passed close to one eye — the
    denominator went to zero for reasons that had nothing to do with head pose.
    """
    if kps is None or len(kps) < 3:
        return 1.0
    leye, reye, nose = kps[0], kps[1], kps[2]
    eye_span = abs(float(reye[0] - leye[0]))
    if eye_span < 1e-3:
        return 1.0
    mid = (float(leye[0]) + float(reye[0])) / 2.0
    offset = abs(float(nose[0]) - mid) / eye_span
    return 1.0 + offset * 4.0


def quality_score(face_px, sharp, det_score, yaw, contrast):
    """A single 0-100 number combining the individual measurements.

    Deliberately a blunt instrument — it exists so you can sort the report and
    see the worst inputs immediately, not to make accept/reject decisions.
    Look at the individual columns for that.
    """
    s_size = min(face_px / 120.0, 1.0)
    s_sharp = min(sharp / 60.0, 1.0)
    s_det = min(max((det_score - 0.3) / 0.6, 0.0), 1.0)
    s_yaw = min(max((2.5 - yaw) / 1.5, 0.0), 1.0)
    s_con = min(contrast / 45.0, 1.0)
    return round(100 * (0.30 * s_size + 0.30 * s_sharp +
                        0.20 * s_det + 0.10 * s_yaw + 0.10 * s_con), 1)


# --------------------------------------------------------------------------
class Embedder:
    def __init__(self, use_gpu=False, model="buffalo_l"):
        providers = (["CUDAExecutionProvider", "CPUExecutionProvider"]
                     if use_gpu else ["CPUExecutionProvider"])
        # allowed_modules trims the bundle to detection + recognition; the
        # landmark and gender/age models are loaded by default and are pure
        # overhead here.
        self.app = FaceAnalysis(name=model, providers=providers,
                                allowed_modules=["detection", "recognition"])
        self.ctx = 0 if use_gpu else -1
        self._state = None
        self._set(DET_STAGES[0][0], DET_STAGES[0][1])

    def _set(self, size, thresh):
        if (size, thresh) != self._state:
            self.app.prepare(ctx_id=self.ctx, det_size=size, det_thresh=thresh)
            self._state = (size, thresh)

    def detect(self, img):
        """Escalate until a face turns up.

        Returns (faces, method, work_img). work_img is whichever image the
        boxes belong to — every measurement afterwards must use it, or the
        crop coordinates land in the wrong place.

        Padding is tried first because it is the cheapest and by far the most
        effective step on cropped portraits, and it succeeds at det640 so the
        expensive 1024/1600/2048 escalation never runs.
        """
        padded = pad_for_detection(img)
        if padded is not img:
            for size, thresh, label in DET_STAGES[:2]:
                self._set(size, thresh)
                faces = self.app.get(padded)
                if faces:
                    return faces, "pad+" + label, padded

        for size, thresh, label in DET_STAGES:
            self._set(size, thresh)
            faces = self.app.get(img)
            if faces:
                return faces, label, img

        enhanced = clahe_bgr(padded)
        for size, thresh, label in DET_STAGES[:3]:
            self._set(size, thresh)
            faces = self.app.get(enhanced)
            if faces:
                return faces, "clahe+" + label, enhanced

        # Horizontal flip. Some detectors are mildly asymmetric on strongly
        # profiled faces; this occasionally recovers one for free.
        self._set(DET_STAGES[2][0], 0.30)
        flipped = cv2.flip(enhanced, 1)
        faces = self.app.get(flipped)
        if faces:
            return faces, "flip", flipped

        return [], "none", img


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="folder of images")
    ap.add_argument("--out", default="embeddings.npz")
    ap.add_argument("--report", default="embedding_report.csv")
    ap.add_argument("--model", default="buffalo_l",
                    help="buffalo_l (512-D, accurate) or buffalo_s (faster)")
    ap.add_argument("--gpu", action="store_true")
    ap.add_argument("--resume", action="store_true",
                    help="skip files already present in an existing --out")
    args = ap.parse_args()

    folder = Path(args.input)
    if not folder.is_dir():
        sys.exit(f"Not a directory: {folder}")

    files = sorted(p for p in folder.rglob("*") if p.suffix.lower() in IMAGE_EXTS)
    if not files:
        sys.exit(f"No images found under {folder}")
    print(f"{len(files)} image files found")

    done = {}
    if args.resume and os.path.exists(args.out):
        prev = np.load(args.out, allow_pickle=True)
        for i, name in enumerate(prev["files"]):
            done[str(name)] = prev["vectors"][i]
        print(f"resuming: {len(done)} already embedded")

    print(f"loading {args.model} ...")
    emb = Embedder(use_gpu=args.gpu, model=args.model)
    print("ready\n")

    rows, vectors, names = [], [], []
    seen_bytes = {}
    started = time.time()
    n_ok = n_fail = 0

    for idx, path in enumerate(files, 1):
        rel = str(path.relative_to(folder))

        if rel in done:
            vectors.append(done[rel]); names.append(rel)
            continue

        m = ID_PATTERN.match(path.stem)
        pid = int(m.group(1)) if m else None

        img = imread_any(path)
        if img is None:
            rows.append(dict(file=rel, id=pid, status="unreadable"))
            n_fail += 1
            print(f"[{idx}/{len(files)}] [-] {rel} — unreadable")
            continue

        # Byte-identical duplicates: recorded, not dropped. Two files with the
        # same bytes are one photo, and if they carry different ids that is a
        # data problem you need to see rather than have silently resolved.
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        dup_of = seen_bytes.get(digest)
        seen_bytes.setdefault(digest, rel)

        faces, method, work = emb.detect(img)
        if not faces:
            rows.append(dict(file=rel, id=pid, status="no_face",
                             width=img.shape[1], height=img.shape[0]))
            n_fail += 1
            print(f"[{idx}/{len(files)}] [-] {rel} — no face at any scale")
            continue

        face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
        vec = np.asarray(face.embedding, dtype=np.float32)
        norm = float(np.linalg.norm(vec))
        if norm < 1e-6:
            rows.append(dict(file=rel, id=pid, status="degenerate"))
            n_fail += 1
            continue
        vec = vec / norm                      # unit length -> cosine is a dot product

        # Measure on `work`, the image the boxes came from.
        face_px = int(face.bbox[2] - face.bbox[0])
        sharp = sharpness(work, face.bbox)
        mean_b, contrast = brightness_stats(work, face.bbox)
        yaw = yaw_ratio(face.kps)
        q = quality_score(face_px, sharp, float(face.det_score), yaw, contrast)

        vectors.append(vec); names.append(rel)
        rows.append(dict(
            file=rel, id=pid, status="ok", n_faces=len(faces), method=method,
            width=img.shape[1], height=img.shape[0], face_px=face_px,
            det_score=round(float(face.det_score), 3), sharpness=round(sharp, 1),
            brightness=round(mean_b, 1), contrast=round(contrast, 1),
            yaw=round(yaw, 2), quality=q, duplicate_of=dup_of or "",
        ))
        n_ok += 1

        flag = ""
        if len(faces) > 1:
            flag += f"  [{len(faces)} faces]"
        if q < 40:
            flag += "  [LOW QUALITY]"
        if dup_of:
            flag += f"  [dup of {dup_of}]"
        print(f"[{idx}/{len(files)}] [+] {rel:<34} {face_px}px  "
              f"sharp={sharp:>5.0f}  q={q:>5.1f}  {method}{flag}")

        if n_ok % 100 == 0:
            save(args.out, names, vectors, rows, args.report)

    save(args.out, names, vectors, rows, args.report)

    elapsed = time.time() - started
    print("\n" + "=" * 64)
    print(f"Embedded : {n_ok}")
    print(f"Failed   : {n_fail}")
    print(f"Time     : {elapsed:.0f}s  ({elapsed / max(len(files), 1):.2f}s per image)")

    ok = [r for r in rows if r["status"] == "ok"]
    if ok:
        qs = np.array([r["quality"] for r in ok])
        px = np.array([r["face_px"] for r in ok])
        print(f"\nQuality  : min {qs.min():.0f}  median {np.median(qs):.0f}  "
              f"max {qs.max():.0f}")
        print(f"Face size: min {px.min()}px  median {np.median(px):.0f}px  "
              f"max {px.max()}px")
        for lo, hi in [(0, 30), (30, 50), (50, 70), (70, 101)]:
            n = int(((qs >= lo) & (qs < hi)).sum())
            if n:
                print(f"  quality {lo:>3}-{hi-1:<3} : {n}")

    bad = {}
    for r in rows:
        if r["status"] != "ok":
            bad[r["status"]] = bad.get(r["status"], 0) + 1
    for k, v in bad.items():
        print(f"  {k}: {v}")

    print(f"\nEmbeddings: {args.out}")
    print(f"Report    : {args.report}")
    print("=" * 64)


def save(out, names, vectors, rows, report):
    if vectors:
        np.savez_compressed(out,
                            files=np.array(names, dtype=object),
                            vectors=np.vstack(vectors).astype(np.float32))
    if rows:
        import csv
        keys = ["file", "id", "status", "n_faces", "method", "width", "height",
                "face_px", "det_score", "sharpness", "brightness", "contrast",
                "yaw", "quality", "duplicate_of"]
        with open(report, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)


if __name__ == "__main__":
    main()