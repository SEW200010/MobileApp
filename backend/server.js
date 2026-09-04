/**
 * Airport passenger backend.
 *
 * Changes from the previous version that matter:
 *
 *  - /verify_face no longer ships every passenger's embedding to Python. It
 *    sends the image only; Python holds the index and does the search. The old
 *    flow serialised the whole gallery as JSON on every single gate check.
 *
 *  - Embeddings are stored as VARBINARY(2048), written with UNHEX(). The old
 *    TEXT column held the same 512 floats as ~10 KB of JSON per passenger.
 *
 *  - The gate handles three outcomes. A "review" result does not open the gate
 *    and does not check anyone in.
 *
 *  - OTPs expire, are attempt-limited, and a verify against a non-existent
 *    passenger now fails. Previously it returned "OTP verified successfully"
 *    with no passenger attached, which a client could read as success.
 */

const express = require('express');
const mysql = require('mysql2');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const axios = require('axios');
const FormData = require('form-data');

const AI_SERVICE = process.env.AI_SERVICE || 'http://127.0.0.1:5001';
const PORT = 5000;

const OTP_TTL_MS = 5 * 60 * 1000;   // 5 minutes
const OTP_MAX_ATTEMPTS = 3;

const app = express();
app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use('/admin', express.static(path.join(__dirname, 'public')));

// A pool, not a single connection: one connection serialises every query and
// dies permanently on a network blip with no reconnect.
const db = mysql.createPool({
    host: 'localhost',
    user: 'root',
    password: '',
    database: 'airport_db',
    waitForConnections: true,
    connectionLimit: 10,
});

const db2 = mysql.createPool({
    host: 'localhost',
    user: 'root',
    password: '',
    database: 'cctv_logs_db',
    waitForConnections: true,
    connectionLimit: 5,
});

const activeOtps = new Map();   // identifier -> { otp, expires, attempts }

// ---------------------------------------------------------------------------
function mapRowToPassenger(row) {
    if (!row) return null;
    let faceImageUrl = row.face_image_url || '';
    if (faceImageUrl && !faceImageUrl.startsWith('http')) {
        faceImageUrl = `http://localhost:${PORT}/${faceImageUrl.replace(/^\/+/, '')}`;
    }
    return {
        id: row.id,
        full_name: row.full_name || '',
        flight_number: row.flight_number || '',
        passport_number: row.passport_number || '',
        email: row.email || '',
        phone_number: row.phone_number || '',
        face_image_url: faceImageUrl,
        face_enrolled: row.embedding_bin != null,
        face_quality: row.face_quality ?? null,
        check_in_status: row.check_in_status || 'Pending',
        created_at: row.created_at || null,
    };
}

const storage = multer.diskStorage({
    destination: './uploads/',
    filename: (req, file, cb) => cb(null, Date.now() + path.extname(file.originalname)),
});
const upload = multer({ storage, limits: { fileSize: 12 * 1024 * 1024 } });

/** POST a file to the Python service as multipart. */
async function postImage(endpoint, filePath, timeout = 30000) {
    const form = new FormData();
    form.append('image', fs.createReadStream(filePath));
    const res = await axios.post(`${AI_SERVICE}${endpoint}`, form, {
        headers: form.getHeaders(),
        timeout,
        maxBodyLength: Infinity,
    });
    return res.data;
}

// ---------------------------------------------------------------------------
// 1. Register
// ---------------------------------------------------------------------------
app.post('/register', upload.single('face_image'), async (req, res) => {
    const { full_name, flight_number, passport_number, email, phone_number } = req.body;

    if (!full_name || !flight_number || !passport_number) {
        return res.status(400).json({
            status: 'error',
            message: 'full_name, flight_number and passport_number are required',
        });
    }
    if (!req.file) {
        return res.status(400).json({ status: 'error', message: 'face_image is required' });
    }

    const faceImageUrl = `uploads/${req.file.filename}`;
    let embeddingHex = null;
    let quality = null;
    let faceWarning = null;

    try {
        const ai = await postImage('/extract-embedding', path.resolve(req.file.path));
        embeddingHex = ai.embedding_hex;
        quality = ai.quality;
    } catch (err) {
        // Registration still succeeds so the passenger record exists, but the
        // response says plainly that face matching will not work for them yet.
        // Silently storing a null embedding is how a passenger ends up
        // permanently unmatchable with nobody noticing.
        faceWarning = err.response?.data?.message || err.message;
        console.error('Embedding extraction failed:', faceWarning);
    }

    const sql = `
        INSERT INTO passengers
            (full_name, flight_number, passport_number, face_image_url,
             embedding_bin, face_quality, face_enrolled_at, email, phone_number,
             check_in_status)
        VALUES (?, ?, ?, ?, ${embeddingHex ? 'UNHEX(?)' : 'NULL'}, ?, ?, ?, ?, 'Pending')`;

    const values = [full_name, flight_number, passport_number, faceImageUrl];
    if (embeddingHex) values.push(embeddingHex);
    values.push(quality?.sharpness ?? null,
                embeddingHex ? new Date() : null,
                email || null, phone_number || null);

    db.query(sql, values, async (err, result) => {
        if (err) return res.status(500).json({ status: 'error', message: err.message });

        if (embeddingHex) {
            // Make the new passenger searchable immediately.
            try { await axios.post(`${AI_SERVICE}/index/reload`, {}, { timeout: 30000 }); }
            catch (e) { console.error('Index reload failed:', e.message); }
        }

        res.json({
            status: 'success',
            passenger_id: result.insertId,
            face_enrolled: Boolean(embeddingHex),
            quality,
            message: embeddingHex
                ? 'Passenger registered and face enrolled.'
                : `Passenger registered, but face enrollment FAILED: ${faceWarning}. ` +
                  'This passenger cannot be matched at the gate until a usable photo is uploaded.',
        });
    });
});

// ---------------------------------------------------------------------------
// 2. OTP
// ---------------------------------------------------------------------------
app.post('/send_otp', (req, res) => {
    const { identifier, is_registration } = req.body;
    if (!identifier) {
        return res.status(400).json({ status: 'error', message: 'identifier is required' });
    }

    const issue = () => {
        const otp = String(Math.floor(100000 + Math.random() * 900000));
        activeOtps.set(identifier, {
            otp, expires: Date.now() + OTP_TTL_MS, attempts: 0,
        });
        console.log(`[SMS simulation] OTP for ${identifier}: ${otp}`);
        // The OTP is echoed only because there is no SMS gateway wired up. In
        // anything resembling production this field must be removed — returning
        // it over the API defeats the purpose of having an OTP at all.
        res.json({ status: 'success', otp, expires_in_seconds: OTP_TTL_MS / 1000 });
    };

    if (is_registration === true || is_registration === 'true') return issue();

    db.query(
        'SELECT id FROM passengers WHERE passport_number = ? OR phone_number = ?',
        [identifier, identifier],
        (err, rows) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });
            if (!rows.length) {
                return res.json({ status: 'error', message: 'Passenger profile not found.' });
            }
            issue();
        }
    );
});

app.post('/verify_otp', (req, res) => {
    const { identifier, otp } = req.body;
    if (!identifier || !otp) {
        return res.status(400).json({ status: 'error', message: 'identifier and otp are required' });
    }

    const entry = activeOtps.get(identifier);
    if (!entry) {
        return res.json({ status: 'error', message: 'No active OTP. Request a new one.' });
    }
    if (Date.now() > entry.expires) {
        activeOtps.delete(identifier);
        return res.json({ status: 'error', message: 'OTP expired. Request a new one.' });
    }
    entry.attempts += 1;
    if (entry.attempts > OTP_MAX_ATTEMPTS) {
        activeOtps.delete(identifier);
        return res.json({ status: 'error', message: 'Too many attempts. Request a new OTP.' });
    }
    if (entry.otp !== otp) {
        return res.json({
            status: 'error',
            message: `Invalid OTP. ${OTP_MAX_ATTEMPTS - entry.attempts} attempt(s) left.`,
        });
    }

    activeOtps.delete(identifier);

    db.query(
        'SELECT * FROM passengers WHERE passport_number = ? OR phone_number = ?',
        [identifier, identifier],
        (err, rows) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });
            if (!rows.length) {
                // Previously this returned success with no passenger attached.
                return res.json({ status: 'error', message: 'Passenger profile not found.' });
            }
            res.json({
                status: 'success',
                message: 'OTP verified.',
                data: mapRowToPassenger(rows[0]),
            });
        }
    );
});

// ---------------------------------------------------------------------------
// 3. Profiles
// ---------------------------------------------------------------------------
app.post('/login', (req, res) => {
    const { passport_number } = req.body;
    if (!passport_number) {
        return res.status(400).json({ status: 'error', message: 'passport_number is required' });
    }
    db.query('SELECT * FROM passengers WHERE passport_number = ?', [passport_number],
        (err, rows) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });
            if (!rows.length) {
                return res.json({ status: 'error', message: 'Passenger profile not found.' });
            }
            res.json({ status: 'success', data: mapRowToPassenger(rows[0]) });
        });
});

app.get('/get_profiles', (req, res) => {
    // Column list is explicit: SELECT * would ship 2 KB of binary embedding
    // per passenger to the client for no reason.
    db.query(
        `SELECT id, full_name, flight_number, passport_number, face_image_url,
                email, phone_number, check_in_status, face_quality, created_at,
                embedding_bin IS NOT NULL AS enrolled
         FROM passengers ORDER BY id DESC`,
        (err, rows) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });
            res.json({
                status: 'success',
                data: rows.map(r => mapRowToPassenger({ ...r, embedding_bin: r.enrolled ? 1 : null })),
            });
        });
});

app.get('/get_profile/:id', (req, res) => {
    db.query(
        `SELECT id, full_name, flight_number, passport_number, face_image_url,
                email, phone_number, check_in_status, face_quality, created_at,
                embedding_bin IS NOT NULL AS enrolled
         FROM passengers WHERE id = ?`,
        [req.params.id],
        (err, rows) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });
            if (!rows.length) return res.status(404).json({ status: 'error', message: 'Not found' });
            const r = rows[0];
            res.json({ status: 'success',
                       data: mapRowToPassenger({ ...r, embedding_bin: r.enrolled ? 1 : null }) });
        });
});

app.post('/check_in/:id', (req, res) => {
    const { status } = req.body;
    db.query('UPDATE passengers SET check_in_status = ? WHERE id = ?',
        [status, req.params.id], (err, r) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });
            if (!r.affectedRows) return res.status(404).json({ status: 'error', message: 'Not found' });
            res.json({ status: 'success', message: `Status updated to ${status}` });
        });
});

app.get('/cctv_logs', (req, res) => {
    db2.query('SELECT * FROM cctv_logs ORDER BY id DESC LIMIT 200', (err, rows) => {
        if (err) return res.status(500).json({ status: 'error', message: err.message });
        res.json({ status: 'success', data: rows });
    });
});

// ---------------------------------------------------------------------------
// 4. Gate verification
// ---------------------------------------------------------------------------
app.post(['/verify_face', '/api/simulate-cctv'], upload.single('cctv_image'), async (req, res) => {
    if (!req.file) {
        return res.status(400).json({ status: 'error', message: 'cctv_image is required' });
    }
    const imageUrl = `uploads/${req.file.filename}`;

    let ai;
    try {
        ai = await postImage('/identify', path.resolve(req.file.path));
    } catch (err) {
        console.error('AI service error:', err.message);
        return res.status(502).json({
            status: 'error',
            message: 'Face service unavailable: ' + (err.response?.data?.message || err.message),
        });
    }

    const logGate = (status, name, passport, confidence) => {
        db2.query(
            `INSERT INTO cctv_logs (passport_number, matched_name, cctv_image_url,
                                    confidence, status) VALUES (?, ?, ?, ?, ?)`,
            [passport || '-', name || '-', imageUrl, confidence || 0, status]
        );
    };

    // Anything other than a confident identification leaves the gate shut and
    // checks nobody in. "review" in particular means the system found a plausible
    // candidate but cannot separate it from the runner-up, or the frame was too
    // poor — acting on that is exactly how the wrong passenger gets through.
    if (ai.outcome !== 'identified') {
        logGate(ai.outcome === 'review' ? 'Review' : 'Denied', null, null,
                ai.candidates?.[0]?.score ?? 0);
        return res.json({
            status: 'ok',
            gate_status: ai.outcome === 'review' ? 'REVIEW' : 'LOCKED',
            outcome: ai.outcome,
            message: ai.message,
            quality: ai.quality,
            top_score: ai.candidates?.[0]?.score ?? null,
        });
    }

    const match = ai.candidates[0];

    db.query('UPDATE passengers SET check_in_status = ? WHERE id = ?',
        ['Checked-In', match.id], (err) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });

            logGate('Checked-In', match.name, match.passport, match.score);

            res.json({
                status: 'success',
                gate_status: 'OPEN',
                outcome: 'identified',
                similarity: match.score,
                margin: ai.candidates.length > 1
                    ? Number((match.score - ai.candidates[1].score).toFixed(4))
                    : null,
                message: 'Face verified. Checked in.',
                data: {
                    id: match.id,
                    full_name: match.name,
                    passport_number: match.passport,
                    flight_number: match.flight,
                    check_in_status: 'Checked-In',
                },
            });
        });
});

// ---------------------------------------------------------------------------
app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    axios.get(`${AI_SERVICE}/health`, { timeout: 5000 })
        .then(r => console.log(`AI service OK — ${r.data.index.enrolled} passengers enrolled`))
        .catch(() => console.warn(`AI service NOT reachable at ${AI_SERVICE}. Start ai_service.py.`));
});
