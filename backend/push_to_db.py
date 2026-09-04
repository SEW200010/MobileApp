"""
Load embeddings.npz into passengers.embedding_bin.

Kept separate from embedding on purpose: if this step fails, the embedding work
does not have to be repeated, and the two failure modes stay distinguishable.

    python push_to_db.py --dry-run
    python push_to_db.py --min-quality 35

What changed and why:

* duplicate_of is now honoured. embed_folder.py already detects byte-identical
  source photos and records the twin in that column, but this script ignored it
  and wrote every copy. Two passengers holding the same vector make the top-2
  margin exactly zero, so both of them land in review at the gate forever and no
  threshold tuning can help. 23 of the 100 rows in the current report are
  flagged this way.

* Near-duplicate vectors are caught too. Two different photos of the same person
  enrolled under two passenger ids produce the same collision without being
  byte-identical.

* low_quality and embedding_model are populated. Both columns exist in
  passengers and were never written, so the service could not tell a 7px face
  from a good one.
"""

import argparse
import csv
import os
from datetime import datetime, timezone

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
EMBEDDING_MODEL = "buffalo_l"

# Cosine similarity above which two enrolled vectors are treated as the same
# face. Measured on the current gallery, unrelated people sit at 0.02 mean and
# 0.20 at the 99th percentile, so 0.90 only ever catches genuine collisions.
NEAR_DUPLICATE_SIM = 0.90


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--npz", default="embeddings.npz")
    ap.add_argument("--report", default="embedding_report.csv")
    ap.add_argument("--min-quality", type=float, default=0.0,
                    help="reject anything below this composite score outright")
    ap.add_argument("--low-quality-below", type=float, default=50.0,
                    help="still enrol, but flag passengers.low_quality so the "
                         "service can keep them out of the search index")
    ap.add_argument("--allow-duplicates", action="store_true",
                    help="write colliding vectors anyway (debugging only)")
    ap.add_argument("--reset", action="store_true",
                    help="clear every existing embedding before writing, so the "
                         "gallery ends up exactly matching this npz")
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

    quality, ids, dup_of = {}, {}, {}
    with open(args.report, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["status"] == "ok":
                quality[row["file"]] = float(row["quality"] or 0)
                ids[row["file"]] = int(row["id"]) if row["id"] else None
                dup_of[row["file"]] = (row.get("duplicate_of") or "").strip()

    db = mysql.connector.connect(**DB_CONFIG)
    cur = db.cursor()
    cur.execute("SELECT id FROM passengers")
    known = {r[0] for r in cur.fetchall()}
    print(f"{len(known)} passenger rows in DB\n")

    written = skipped = flagged = 0
    reasons = {}
    accepted = []            # (normalised vector, file, pid) already written

    def skip(why):
        nonlocal skipped
        skipped += 1
        reasons[why] = reasons.get(why, 0) + 1

    now = datetime.now(timezone.utc).replace(tzinfo=None)

    if args.reset and not args.dry_run:
        cur.execute(
            "UPDATE passengers SET embedding_bin=NULL, face_quality=NULL, "
            "face_enrolled_at=NULL, embedding_model=NULL, low_quality=0 "
            "WHERE embedding_bin IS NOT NULL"
        )
        print(f"--reset: cleared {cur.rowcount} existing embeddings\n")

    for name, vec in zip(files, vectors):
        pid = ids.get(name)
        if pid is None:
            skip("filename has no leading id"); continue
        if pid not in known:
            skip("no passenger row with that id"); continue

        # Byte-identical source photo, already flagged during embedding.
        twin = dup_of.get(name)
        if twin and not args.allow_duplicates:
            print(f"  DUPLICATE FILE: {name} is identical to {twin} — skipping")
            skip("byte-identical duplicate of another photo"); continue

        q = quality.get(name, 0.0)
        if q < args.min_quality:
            skip(f"quality below {args.min_quality}"); continue

        v = np.asarray(vec, dtype=np.float32)
        n = float(np.linalg.norm(v))
        if n < 1e-6:
            skip("degenerate vector"); continue
        v = (v / n).astype(np.float32)

        # Different files, same face. Same consequence as above.
        if accepted and not args.allow_duplicates:
            M = np.vstack([a[0] for a in accepted])
            sims = M @ v
            j = int(np.argmax(sims))
            if float(sims[j]) >= NEAR_DUPLICATE_SIM:
                print(f"  DUPLICATE FACE: {name} (id={pid}) matches "
                      f"{accepted[j][1]} (id={accepted[j][2]}) at "
                      f"{sims[j]:.4f} — skipping")
                skip("same face as an already-enrolled passenger"); continue

        low = 1 if q < args.low_quality_below else 0
        if low:
            flagged += 1

        if args.dry_run:
            accepted.append((v, name, pid))
            written += 1
            continue

        blob = v.tobytes()

        # Release the vector from any other row still holding it.
        #
        # embed_folder.py sorts filenames as strings, so "100.jpg" sorts before
        # "19.jpg" and becomes the keeper for that pair — while a cleanup that
        # kept the lowest numeric id left the vector on passenger 19. Writing it
        # to passenger 100 then trips the uq_embedding_sig unique index. The
        # index is doing its job; the two sides simply disagreed on which twin
        # to keep. Whoever the npz names is the winner, so clear the other row
        # first. Without this the whole push aborts on one collision.
        cur.execute(
            "UPDATE passengers SET embedding_bin=NULL, face_quality=NULL, "
            "face_enrolled_at=NULL, embedding_model=NULL, low_quality=0 "
            "WHERE embedding_bin=%s AND id<>%s",
            (blob, pid),
        )
        if cur.rowcount:
            print(f"  released {name}'s vector from {cur.rowcount} other "
                  f"passenger row(s) before writing to id={pid}")

        cur.execute(
            "UPDATE passengers SET embedding_bin=%s, face_quality=%s, "
            "face_enrolled_at=%s, embedding_model=%s, low_quality=%s "
            "WHERE id=%s",
            (blob, q, now, EMBEDDING_MODEL, low, pid),
        )
        accepted.append((v, name, pid))
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
    cur.execute(
        "SELECT COUNT(*) FROM passengers a WHERE a.embedding_bin IS NOT NULL "
        "AND EXISTS (SELECT 1 FROM passengers b WHERE b.embedding_bin = "
        "a.embedding_bin AND b.id <> a.id)"
    )
    colliding = cur.fetchone()[0]
    cur.close(); db.close()

    print(f"\n{'Would write' if args.dry_run else 'Written'}: {written}")
    print(f"  of which flagged low_quality (< {args.low_quality_below}): {flagged}")
    print(f"Skipped: {skipped}")
    for why, n in sorted(reasons.items(), key=lambda kv: -kv[1]):
        print(f"  {n:>4}  {why}")

    print(f"\nRows with an embedding in DB: {in_db}")
    if truncated:
        print(f"WARNING: {truncated} rows are not exactly {EXPECTED_DIM * 4} bytes.")
        print("The embedding_bin column is probably too small. It must be "
              "VARBINARY(2048).")
    if colliding:
        print(f"WARNING: {colliding} rows still share an embedding with another "
              f"row — left over from an earlier run.")
        print("Clear them with the query in migration.sql, then re-run this "
              "script.")
    if not args.dry_run:
        print("\nNow reload the service index:")
        print("  curl -X POST http://127.0.0.1:5001/index/reload")


if __name__ == "__main__":
    main()