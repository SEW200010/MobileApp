const express = require('express');
const mysql = require('mysql2');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const axios = require('axios');
const FormData = require('form-data');

const AI_SERVICE = process.env.AI_SERVICE || 'http://127.0.0.1:5001';
const AI_API_KEY = process.env.FACE_API_KEY || '';
const PORT = Number(process.env.PORT || 5000);
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_USER = process.env.DB_USER || 'root';
const DB_PASSWORD = process.env.DB_PASSWORD || '';
const DB_NAME = process.env.DB_NAME || 'airport_db';
const CCTV_DB_NAME = process.env.CCTV_DB_NAME || 'cctv_logs_db';

const OTP_TTL_MS = 5 * 60 * 1000;
const OTP_MAX_ATTEMPTS = 3;
const LOW_QUALITY_BELOW = Number(process.env.LOW_QUALITY_BELOW || 50);

const GOOGLE_APPS_SCRIPT_URL = 'https://script.google.com/macros/s/AKfycbx4IYyuY6qZgtRC5yo0HUpi8xSiW7BWsVrIMfEZxEY5fPhDs5zAp1uYusWlCfgNEGW6/exec';

const app = express();
app.use(cors());
app.use(express.json());
app.use('/admin', express.static(path.join(__dirname, 'public')));

const db = mysql.createPool({
    host: DB_HOST,
    user: DB_USER,
    password: DB_PASSWORD,
    database: DB_NAME,
    waitForConnections: true,
    connectionLimit: 10,
});

const db2 = mysql.createPool({
    host: DB_HOST,
    user: DB_USER,
    password: DB_PASSWORD,
    database: CCTV_DB_NAME,
    waitForConnections: true,
    connectionLimit: 5,
});

const activeOtps = new Map(); 

const aiHeaders = () => (AI_API_KEY ? { 'X-API-Key': AI_API_KEY } : {});

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

const storage = multer.memoryStorage();
const upload = multer({ storage, limits: { fileSize: 12 * 1024 * 1024 } });

async function postImageBuffer(endpoint, fileBuffer, timeout = 30000) {
    const formData = new FormData();
    formData.append('image', fileBuffer, { filename: 'probe.jpg', contentType: 'image/jpeg' });
    
    const res = await axios.post(`${AI_SERVICE}${endpoint}`, formData, {
        headers: { ...aiHeaders(), ...formData.getHeaders() },
        timeout
    });
    return res.data;
}

async function uploadImageToDriveViaScript(fileBuffer, originalname) {
    try {
        const base64Image = fileBuffer.toString('base64');
        const payload = {
            base64: base64Image,
            mimeType: 'image/jpeg',
            filename: `passenger_${Date.now()}_${originalname}`
        };

        const response = await axios.post(GOOGLE_APPS_SCRIPT_URL, payload);
        if (response.data && response.data.status === 'success') {
            return response.data.url; 
        }
        return null;
    } catch (error) {
        console.error('Drive Upload Error:', error.message);
        return null;
    }
}

async function postImagePath(endpoint, filename, timeout = 30000) {
    const res = await axios.post(`${AI_SERVICE}${endpoint}`,
        { image_path: filename },
        { headers: aiHeaders(), timeout });
    return res.data;
}

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

    let embeddingHex = null;
    let quality = null;
    let ai_model = null;
    let faceWarning = null;

    try {
        const ai = await postImageBuffer('/extract-embedding', req.file.buffer);
        embeddingHex = ai.embedding_hex;
        quality = ai.quality;
        ai_model = ai.model;
    } catch (err) {
        faceWarning = err.response?.data?.message || err.message;
        console.error('Embedding extraction failed:', faceWarning);
    }

    console.log('Uploading photo to Google Drive via Apps Script...');
    let driveImageUrl = await uploadImageToDriveViaScript(req.file.buffer, req.file.originalname);
    
    if (!driveImageUrl) {
        driveImageUrl = ''; 
    }

    const sql = `
        INSERT INTO passengers
            (full_name, flight_number, passport_number, face_image_url,
             embedding_bin, face_quality, face_enrolled_at, embedding_model,
             low_quality, email, phone_number, check_in_status)
        VALUES (?, ?, ?, ?, ${embeddingHex ? 'UNHEX(?)' : 'NULL'}, ?, ?, ?, ?, ?, ?, 'Pending')`;

    const values = [full_name, flight_number, passport_number, driveImageUrl];
    if (embeddingHex) values.push(embeddingHex);
    values.push(
        quality?.score ?? null,
        embeddingHex ? new Date() : null,
        embeddingHex ? (ai_model || 'buffalo_l') : null,
        embeddingHex && (quality?.score ?? 100) < LOW_QUALITY_BELOW ? 1 : 0,
        email || null, 
        phone_number || null
    );

    db.query(sql, values, async (err, result) => {
        if (err) {
            return res.status(500).json({ status: 'error', message: err.message });
        }

        if (embeddingHex) {
            try {
                await axios.post(`${AI_SERVICE}/index/reload`, {}, { headers: aiHeaders(), timeout: 30000 });
            } catch (e) { 
                console.error('Index reload failed:', e.message); 
            }
        }

        res.json({
            status: 'success',
            passenger_id: result.insertId,
            face_enrolled: Boolean(embeddingHex),
            quality,
            google_drive_url: driveImageUrl,
            message: embeddingHex
                ? 'Passenger registered, face enrolled, and photo saved to Google Drive.'
                : `Passenger registered, but face enrollment FAILED: ${faceWarning}`,
        });
    });
});

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
    const { identifier, otp, is_registration } = req.body;
    if (!identifier || !otp) {
        return res.status(400).json({ status: 'error', message: 'identifier and otp are required' });
    }
    const isRegistration = is_registration === true || is_registration === 'true';

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
    if (isRegistration) {
        return res.json({
            status: 'success',
            message: 'OTP verified. Continue with registration.',
            data: null,
        });
    }

    db.query(
        'SELECT * FROM passengers WHERE passport_number = ? OR phone_number = ?',
        [identifier, identifier],
        (err, rows) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });
            if (!rows.length) {
                return res.json({
                    status: 'success',
                    message: 'OTP verified. Continue with registration.',
                    data: null,
                });
            }
            res.json({
                status: 'success',
                message: 'OTP verified.',
                data: mapRowToPassenger(rows[0]),
            });
        }
    );
});

app.post('/login', (req, res) => {
    const { passport_number } = req.body;
    if (!passport_number) {
        return res.status(400).json({ status: 'error', message: 'passport_number is required' });
    }
    db.query(
        `SELECT id, full_name, flight_number, passport_number, face_image_url,
                email, phone_number, check_in_status, face_quality, created_at,
                embedding_bin IS NOT NULL AS enrolled
         FROM passengers WHERE passport_number = ?`,
        [passport_number],
        (err, rows) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });
            if (!rows.length) {
                return res.json({ status: 'error', message: 'Passenger profile not found.' });
            }
            const r = rows[0];
            res.json({ status: 'success',
                       data: mapRowToPassenger({ ...r, embedding_bin: r.enrolled ? 1 : null }) });
        });
});

app.get('/get_profiles', (req, res) => {
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

app.post(['/verify_face', '/api/simulate-cctv'], upload.single('cctv_image'), async (req, res) => {
    if (!req.file) {
        return res.status(400).json({ status: 'error', message: 'cctv_image is required' });
    }

    let ai;
    try {
        ai = await postImagePath('/identify', req.file.filename);
    } catch (err) {
        console.error('AI service error:', err.message);
        return res.status(502).json({
            status: 'error',
            message: 'Face service unavailable: ' + (err.response?.data?.message || err.message),
        });
    }
    if (ai.outcome !== 'identified') {
        return res.json({
            status: 'ok',
            gate_status: ai.outcome === 'review' ? 'REVIEW' : 'LOCKED',
            outcome: ai.outcome,
            message: ai.message,
            quality: ai.quality,
            logged: Boolean(ai.logged),
            top_score: ai.candidates?.[0]?.score ?? null,
        });
    }

    const match = ai.candidates[0];

    db.query('UPDATE passengers SET check_in_status = ? WHERE id = ?',
        ['Checked-In', match.id], (err) => {
            if (err) return res.status(500).json({ status: 'error', message: err.message });
            const full = ai.passenger || {
                id: match.id,
                full_name: match.name,
                passport_number: match.passport,
                flight_number: match.flight,
            };

            res.json({
                status: 'success',
                gate_status: 'OPEN',
                outcome: 'identified',
                similarity: match.score,
                margin: ai.candidates.length > 1
                    ? Number((match.score - ai.candidates[1].score).toFixed(4))
                    : null,
                quality: ai.quality,
                logged: Boolean(ai.logged),
                message: 'Face verified. Checked in.',
                data: { ...full, check_in_status: 'Checked-In' },
            });
        });
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    if (!AI_API_KEY) {
        console.warn('FACE_API_KEY is not set — the face service is unauthenticated.');
    }
    axios.get(`${AI_SERVICE}/health`, { headers: aiHeaders(), timeout: 5000 })
        .then(r => console.log(`AI service OK — ${r.data.index.enrolled} passengers enrolled`))
        .catch(() => console.warn(`AI service NOT reachable at ${AI_SERVICE}. Start ai_service.py.`));
});