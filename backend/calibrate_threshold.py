import argparse
import sys
from pathlib import Path

import cv2
import numpy as np

try:
    from insightface.app import FaceAnalysis
except ImportError:
    sys.exit("pip install insightface onnxruntime")

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def imread_any(path):
    buf = np.fromfile(str(path), dtype=np.uint8)
    if buf.size == 0:
        return None
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is None:
        return None
    h, w = img.shape[:2]
    if max(h, w) > 1600:
        s = 1600 / max(h, w)
        img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    return img


def embed_one(app, path):
    img = imread_any(path)
    if img is None:
        return None
    faces = app.get(img)
    if not faces:
        return None
    f = max(faces, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))
    v = np.asarray(f.embedding, dtype=np.float32)
    n = float(np.linalg.norm(v))
    return (v / n) if n > 1e-6 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="folder of per-identity folders")
    ap.add_argument("--min-images", type=int, default=2)
    ap.add_argument("--max-identities", type=int, default=1500)
    ap.add_argument("--gpu", action="store_true")
    ap.add_argument("--out", default="calibration.csv")
    args = ap.parse_args()

    root = Path(args.input)
    people = []
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        imgs = sorted(f for f in d.iterdir() if f.suffix.lower() in IMAGE_EXTS)
        if len(imgs) >= args.min_images:
            people.append((d.name, imgs))
    people = people[:args.max_identities]

    if len(people) < 20:
        sys.exit(f"Only {len(people)} identities with {args.min_images}+ images. "
                 "Need at least a few hundred for the false-accept rate to mean "
                 "anything.")
    print(f"{len(people)} identities\n")

    providers = (["CUDAExecutionProvider", "CPUExecutionProvider"] if args.gpu
                 else ["CPUExecutionProvider"])
    app = FaceAnalysis(name="buffalo_l", providers=providers,
                       allowed_modules=["detection", "recognition"])
    app.prepare(ctx_id=0 if args.gpu else -1, det_size=(640, 640), det_thresh=0.45)

    gallery, gallery_names = [], []
    probes, probe_owner = [], []
    failed = 0

    for i, (name, imgs) in enumerate(people, 1):
        g = embed_one(app, imgs[0])
        if g is None:
            failed += 1
            continue
        idx = len(gallery)
        gallery.append(g); gallery_names.append(name)

        for p in imgs[1:6]:                      # cap probes per identity
            v = embed_one(app, p)
            if v is None:
                failed += 1
                continue
            probes.append(v); probe_owner.append(idx)

        if i % 50 == 0:
            print(f"  {i}/{len(people)} identities, {len(probes)} probes")

    G = np.vstack(gallery).astype(np.float32)
    P = np.vstack(probes).astype(np.float32)
    owner = np.asarray(probe_owner)
    print(f"\ngallery {G.shape[0]}, probes {P.shape[0]}, failed {failed}\n")

    scores = P @ G.T                             # probes x gallery cosine matrix

    rows = np.arange(P.shape[0])
    genuine = scores[rows, owner]

    impostor_only = scores.copy()
    impostor_only[rows, owner] = -np.inf         # mask out the true identity
    top_impostor = impostor_only.max(axis=1)     # the 1:N false-accept risk
    runner_up = np.partition(impostor_only, -2, axis=1)[:, -2]

    print("genuine  : min {:.3f}  mean {:.3f}  max {:.3f}".format(
        genuine.min(), genuine.mean(), genuine.max()))
    print("impostor : min {:.3f}  mean {:.3f}  max {:.3f}".format(
        top_impostor.min(), top_impostor.mean(), top_impostor.max()))
    print()

    print(f"{'thresh':>7} {'FRR%':>7} {'FAR%':>7} {'rank1%':>8} {'correct%':>9}")
    print("-" * 42)

    best = None
    out_rows = []
    for t in np.arange(0.25, 0.76, 0.01):
        frr = float((genuine < t).mean() * 100)
        far = float((top_impostor >= t).mean() * 100)
        rank1 = float((genuine > top_impostor).mean() * 100)
        correct = float(((genuine >= t) & (genuine > top_impostor)).mean() * 100)
        out_rows.append((round(float(t), 2), frr, far, rank1, correct))
        if t * 100 % 5 < 1:
            print(f"{t:>7.2f} {frr:>7.2f} {far:>7.2f} {rank1:>8.2f} {correct:>9.2f}")
        # Pick the lowest threshold that holds false accepts under 0.1%.
        if best is None and far <= 0.1:
            best = (float(t), frr, far)

    with open(args.out, "w", encoding="utf-8") as f:
        f.write("threshold,frr_pct,far_pct,rank1_pct,correct_accept_pct\n")
        for r in out_rows:
            f.write("{},{:.4f},{:.4f},{:.4f},{:.4f}\n".format(*r))

    print("\n" + "=" * 60)
    if best:
        t, frr, far = best
        print(f"RECOMMENDED IDENTIFY_THRESHOLD = {t:.2f}")
        print(f"  at this value: FAR {far:.3f}%   FRR {frr:.2f}%")
        print(f"  measured on {G.shape[0]} identities, {P.shape[0]} probes")
    else:
        print("No threshold in 0.25-0.75 got FAR under 0.1%.")
        print("Either the gallery is too small or the images are too poor.")

    margins = genuine - runner_up
    print(f"\nSuggested MIN_MARGIN = {np.percentile(margins, 1):.3f} "
          f"(1st percentile of genuine margin)")

    print(f"\nFull curve: {args.out}")
    print("\nNOTE: these numbers describe THIS image set. If your gallery grows,")
    print("FAR rises and the threshold must be re-measured. If your operational")
    print("images are CCTV frames rather than portraits, expect FRR to be")
    print("substantially worse than measured here.")
    print("=" * 60)


if __name__ == "__main__":
    main()
