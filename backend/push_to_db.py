"""
Load embeddings.npz into passengers.embedding_bin.

Kept separate from embedding on purpose: if this step fails, the embedding work
does not have to be repeated, and the two failure modes stay distinguishable.

    python push_to_db.py --dry-run
    python push_to_db.py --min-quality 35
"""

import argparse
import csv
import os
from datetime import datetime

import numpy as np
import mysql.connector

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "127.0.0.1"),
    "port": int(os.environ.get("DB_PORT", "3306")),
    "user": os.environ.get("DB_USER", "root"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "database": os.environ.get("DB_NAME", "airport_db"),
}

EXPECTED_DIM = 512


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--npz", default="embeddings.npz")
    ap.add_argument("--report", default="embedding_report.csv")
    ap.add_argument("--min-quality", type=float, default=0.0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    data = np.load(args.npz, allow_pickle=True)
    files = [str(f) for f in data["files"]]
    vectors = data["vectors"]
    print(f"{len(files)} embeddings, {vectors.shape[1]} dimensions")

    if vectors.shape[1] != EXPECTED_DIM:
        raise SystemExit(
            f"Expected {EXPECTED_DIM}-D vectors, got {vectors.shape[1]}. "
            "The service reads a fixed width from a VARBINARY(2048) column; a "
            "mismatch here means every row would be unreadable."
        )

    quality, ids = {}, {}
    with open(args.report, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["status"] == "ok":
                quality[row["file"]] = float(row["quality"] or 0)
                ids[row["file"]] = int(row["id"]) if row["id"] else None

    db = mysql.connector.connect(**DB_CONFIG)
    cur = db.cursor()
    cur.execute("SELECT id FROM passengers")
    known = {r[0] for r in cur.fetchall()}
    print(f"{len(known)} passenger rows in DB\n")

    written = skipped = 0
    reasons = {}

    def skip(why):
        nonlocal skipped
        skipped += 1
        reasons[why] = reasons.get(why, 0) + 1

    for name, vec in zip(files, vectors):
        pid = ids.get(name)
        if pid is None:
            skip("filename has no leading id"); continue
        if pid not in known:
            skip("no passenger row with that id"); continue
        q = quality.get(name, 0.0)
        if q < args.min_quality:
            skip(f"quality below {args.min_quality}"); continue

        # Re-normalise defensively. The search treats a dot product as cosine
        # similarity, which is only true for unit vectors.
        v = np.asarray(vec, dtype=np.float32)
        n = float(np.linalg.norm(v))
        if n < 1e-6:
            skip("degenerate vector"); continue
        v = (v / n).astype(np.float32)

        if args.dry_run:
            written += 1
            continue

        cur.execute(
            "UPDATE passengers SET embedding_bin=%s, face_quality=%s, "
            "face_enrolled_at=%s WHERE id=%s",
            (v.tobytes(), q, datetime.utcnow(), pid),
        )
        written += 1
        if written % 100 == 0:
            db.commit()
            print(f"  ...{written}")

    if not args.dry_run:
        db.commit()

    cur.execute("SELECT COUNT(*) FROM passengers WHERE embedding_bin IS NOT NULL")
    in_db = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM passengers WHERE LENGTH(embedding_bin) <> %s "
                "AND embedding_bin IS NOT NULL", (EXPECTED_DIM * 4,))
    truncated = cur.fetchone()[0]
    cur.close(); db.close()

    print(f"\n{'Would write' if args.dry_run else 'Written'}: {written}")
    print(f"Skipped: {skipped}")
    for why, n in sorted(reasons.items(), key=lambda kv: -kv[1]):
        print(f"  {n:>4}  {why}")

    print(f"\nRows with an embedding in DB: {in_db}")
    if truncated:
        # Silent truncation is the failure mode to watch for here: MySQL will
        # cut an oversized value down to fit and carry on without an error.
        print(f"WARNING: {truncated} rows are not exactly {EXPECTED_DIM * 4} bytes.")
        print("The embedding_bin column is probably too small. It must be "
              "VARBINARY(2048).")


if __name__ == "__main__":
    main()
