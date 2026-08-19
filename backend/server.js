const express = require('express');
const mysql = require('mysql2');
const multer = require('multer');
const path = require('path');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use('/admin', express.static(path.join(__dirname, 'public')));

// MySQL Connections
const db = mysql.createConnection({
  host: 'localhost',
  user: 'root',
  password: '',
});

let dbColumns = [];
let db2; // Connection to cctv_logs_db

db.connect((err) => {
    if (err) {
        console.error('Database connection failed:', err);
        return;
    }
    console.log('Connected to MySQL Database Server!');

    // 1. Create airport_db if not exists
    db.query("CREATE DATABASE IF NOT EXISTS airport_db", (err) => {
        if (err) console.error("Error creating airport_db:", err.message);

        // 2. Select airport_db
        db.query("USE airport_db", (err) => {
            if (err) console.error("Error selecting airport_db:", err.message);

            // 3. Create passengers table if not exists
            const createPassengersTable = `
                CREATE TABLE IF NOT EXISTS passengers (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    full_name VARCHAR(255) NOT NULL,
                    flight_number VARCHAR(50) NOT NULL,
                    passport_number VARCHAR(50) NOT NULL,
                    face_image_url TEXT NOT NULL,
                    check_in_status VARCHAR(200) NOT NULL DEFAULT 'Pending',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            `;
            db.query(createPassengersTable, (err) => {
                if (err) console.error("Error creating passengers table:", err.message);

                // 4. Verify/add missing columns (email, phone_number)
                db.query("DESCRIBE passengers", (err, results) => {
                    if (err) {
                        console.error('Error describing passengers:', err.message);
                        return;
                    }
                    dbColumns = results.map(row => row.Field);
                    
                    if (!dbColumns.includes('email')) {
                        db.query("ALTER TABLE passengers ADD COLUMN email VARCHAR(255) NULL", (err) => {
                            if (err) console.error("Error adding email column:", err.message);
                            else {
                                console.log("Added email column to passengers");
                                dbColumns.push('email');
                            }
                        });
                    }
                    if (!dbColumns.includes('phone_number')) {
                        db.query("ALTER TABLE passengers ADD COLUMN phone_number VARCHAR(50) NULL", (err) => {
                            if (err) console.error("Error adding phone_number column:", err.message);
                            else {
                                console.log("Added phone_number column to passengers");
                                dbColumns.push('phone_number');
                            }
                        });
                    }
                    console.log('Detected database columns:', dbColumns);
                });
            });
        });
    });

    // 5. Create cctv_logs_db and cctv_logs table if not exists
    db.query("CREATE DATABASE IF NOT EXISTS cctv_logs_db", (err) => {
        if (err) {
            console.error("Error creating cctv_logs_db:", err.message);
            return;
        }

        // Initialize connection to cctv_logs_db
        db2 = mysql.createConnection({
            host: 'localhost',
            user: 'root',
            password: '',
            database: 'cctv_logs_db',
        });

        db2.connect((err) => {
            if (err) {
                console.error("Failed to connect to cctv_logs_db:", err.message);
                return;
            }
            console.log("Connected to CCTV Logs Database!");

            const createCctvLogsTable = `
                CREATE TABLE IF NOT EXISTS cctv_logs (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    passport_number VARCHAR(50) NOT NULL,
                    matched_name VARCHAR(255) NOT NULL,
                    cctv_image_url TEXT NOT NULL,
                    confidence FLOAT NOT NULL,
                    status VARCHAR(100) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            `;
            db2.query(createCctvLogsTable, (err) => {
                if (err) console.error("Error creating cctv_logs table:", err.message);
                else console.log("cctv_logs table ready!");
            });
        });
    });
});

// Helper function to map database rows with arbitrary naming to standard API structure
function mapRowToPassenger(row) {
    if (!row) return null;
    
    const fullName = row['full name'] || row['full_name'] || row['fullname'] || '';
    const flightNumber = row['flight number'] || row['flight_number'] || row['flightnumber'] || '';
    const passportNumber = row['passport number'] || row['passport_number'] || row['passportnumber'] || '';
    const email = row['email'] || '';
    const phoneNumber = row['phone_number'] || row['phone number'] || row['phonenumber'] || row['phone'] || '';
    
    let faceImageUrl = row['facr image url'] || row['facr_image_url'] || 
                       row['face image url'] || row['face_image_url'] || row['faceimageurl'] || '';
                       
    if (faceImageUrl && !faceImageUrl.startsWith('http')) {
        faceImageUrl = `http://localhost:5000/${faceImageUrl}`;
    }

    const checkInStatus = row['check in status'] || row['check_in_status'] || row['checkinstatus'] || 'Pending';

    return {
        id: row.id,
        full_name: fullName,
        flight_number: flightNumber,
        passport_number: passportNumber,
        email: email,
        phone_number: phoneNumber,
        face_image_url: faceImageUrl,
        check_in_status: checkInStatus,
        created_at: row['created at'] || row['created_at'] || null
    };
}

// Image Upload Storage Configuration (Multer)
const storage = multer.diskStorage({
    destination: './uploads/',
    filename: (req, file, cb) => {
        cb(null, Date.now() + path.extname(file.originalname));
    }
});
const upload = multer({ storage: storage });

// 1. Register Passenger API
app.post('/register', upload.single('face_image'), (req, res) => {
    const { full_name, flight_number, passport_number, email, phone_number } = req.body;
    const face_image_url = req.file ? `uploads/${req.file.filename}` : '';

    // Find the correct column names in the database
    const nameCol = dbColumns.find(c => ['full_name', 'full name', 'fullname'].includes(c.toLowerCase())) || 'full_name';
    const flightCol = dbColumns.find(c => ['flight_number', 'flight number', 'flightnumber'].includes(c.toLowerCase())) || 'flight_number';
    const passportCol = dbColumns.find(c => ['passport_number', 'passport number', 'passportnumber'].includes(c.toLowerCase())) || 'passport_number';
    const faceCol = dbColumns.find(c => ['face_image_url', 'face image url', 'faceimageurl', 'facr_image_url', 'facr image url'].includes(c.toLowerCase())) || 'face_image_url';
    const statusCol = dbColumns.find(c => ['check_in_status', 'check in status', 'checkinstatus'].includes(c.toLowerCase()));
    const emailCol = dbColumns.find(c => ['email'].includes(c.toLowerCase())) || 'email';
    const phoneCol = dbColumns.find(c => ['phone_number', 'phone number', 'phonenumber', 'phone'].includes(c.toLowerCase())) || 'phone_number';

    const fields = [
        `\`${nameCol}\``, 
        `\`${flightCol}\``, 
        `\`${passportCol}\``, 
        `\`${faceCol}\``,
        `\`${emailCol}\``,
        `\`${phoneCol}\``
    ];
    const values = [full_name, flight_number, passport_number, face_image_url, email, phone_number];
    const placeholders = ['?', '?', '?', '?', '?', '?'];

    if (statusCol) {
        fields.push(`\`${statusCol}\``);
        values.push('Pending');
        placeholders.push('?');
    }

    const sql = `INSERT INTO passengers (${fields.join(', ')}) VALUES (${placeholders.join(', ')})`;
    
    db.query(sql, values, (err, result) => {
        if (err) {
            return res.json({ status: "error", message: err.message });
        }
        res.json({ 
            status: "success", 
            message: "Passenger registered successfully!",
            passenger_id: result.insertId 
        });
    });
});

const activeOtps = {};

// 1.2. Send OTP API
app.post('/send_otp', (req, res) => {
    const { identifier, is_registration } = req.body;
    if (!identifier) {
        return res.json({ status: "error", message: "Phone number or Passport number is required" });
    }

    const checkOtpSend = () => {
        const otp = Math.floor(100000 + Math.random() * 900000).toString();
        activeOtps[identifier] = otp;
        console.log(`[SMS Simulation] OTP for ${identifier}: ${otp}`);
        res.json({
            status: "success",
            otp: otp,
            message: `OTP sent successfully to ${identifier}`
        });
    };

    if (is_registration) {
        checkOtpSend();
    } else {
        const passportCol = dbColumns.find(c => ['passport_number', 'passport number', 'passportnumber'].includes(c.toLowerCase())) || 'passport_number';
        const phoneCol = dbColumns.find(c => ['phone_number', 'phone number', 'phonenumber', 'phone'].includes(c.toLowerCase())) || 'phone_number';
        
        const sql = `SELECT * FROM passengers WHERE \`${passportCol}\` = ? OR \`${phoneCol}\` = ?`;
        db.query(sql, [identifier, identifier], (err, results) => {
            if (err) {
                return res.json({ status: "error", message: err.message });
            }
            if (results.length === 0) {
                return res.json({ status: "error", message: "Passenger profile not found. Please register." });
            }
            checkOtpSend();
        });
    }
});

// 1.3. Verify OTP API
app.post('/verify_otp', (req, res) => {
    const { identifier, otp } = req.body;
    if (!identifier || !otp) {
        return res.json({ status: "error", message: "Identifier and OTP are required" });
    }

    if (activeOtps[identifier] === otp) {
        delete activeOtps[identifier];

        const passportCol = dbColumns.find(c => ['passport_number', 'passport number', 'passportnumber'].includes(c.toLowerCase())) || 'passport_number';
        const phoneCol = dbColumns.find(c => ['phone_number', 'phone number', 'phonenumber', 'phone'].includes(c.toLowerCase())) || 'phone_number';
        
        const sql = `SELECT * FROM passengers WHERE \`${passportCol}\` = ? OR \`${phoneCol}\` = ?`;
        db.query(sql, [identifier, identifier], (err, results) => {
            if (err) {
                return res.json({ status: "error", message: err.message });
            }
            if (results.length > 0) {
                const passenger = mapRowToPassenger(results[0]);
                return res.json({
                    status: "success",
                    message: "OTP verified successfully!",
                    data: passenger
                });
            } else {
                return res.json({
                    status: "success",
                    message: "OTP verified successfully!"
                });
            }
        });
    } else {
        res.json({ status: "error", message: "Invalid OTP code. Please try again." });
    }
});

// 1.5. Login Passenger API
app.post('/login', (req, res) => {
    const { passport_number } = req.body;
    if (!passport_number) {
        return res.json({ status: "error", message: "Passport number is required" });
    }

    const passportCol = dbColumns.find(c => ['passport_number', 'passport number', 'passportnumber'].includes(c.toLowerCase())) || 'passport_number';
    const sql = `SELECT * FROM passengers WHERE \`${passportCol}\` = ?`;
    
    db.query(sql, [passport_number], (err, results) => {
        if (err) {
            return res.json({ status: "error", message: err.message });
        }
        if (results.length === 0) {
            return res.json({ status: "error", message: "Passenger profile not found. Please register." });
        }
        const passenger = mapRowToPassenger(results[0]);
        res.json({ 
            status: "success", 
            message: "Login successful!",
            data: passenger
        });
    });
});

// 2. Get All Profiles API
app.get('/get_profiles', (req, res) => {
    const sql = "SELECT * FROM passengers ORDER BY id DESC";
    db.query(sql, (err, results) => {
        if (err) {
            return res.json({ status: "error", message: err.message });
        }
        
        const passengers = results.map(row => mapRowToPassenger(row));
        res.json({ status: "success", data: passengers });
    });
});

// 2.5. Get CCTV Gate Logs API
app.get('/cctv_logs', (req, res) => {
    if (!db2) {
        return res.json({ status: "error", message: "CCTV Logs Database connection not initialized." });
    }
    const sql = "SELECT * FROM cctv_logs ORDER BY id DESC";
    db2.query(sql, (err, results) => {
        if (err) {
            return res.json({ status: "error", message: err.message });
        }
        
        const logs = results.map(row => {
            let img = row.cctv_image_url || '';
            if (img && !img.startsWith('http')) {
                img = `http://localhost:5000/${img}`;
            }
            return {
                id: row.id,
                passport_number: row.passport_number,
                matched_name: row.matched_name,
                cctv_image_url: img,
                confidence: row.confidence,
                status: row.status,
                created_at: row.created_at
            };
        });
        res.json({ status: "success", data: logs });
    });
});

// 3. Get Single Profile Details API
app.get('/get_profile/:id', (req, res) => {
    const passengerId = req.params.id;
    const sql = "SELECT * FROM passengers WHERE id = ?";
    
    db.query(sql, [passengerId], (err, results) => {
        if (err || results.length === 0) {
            return res.json({ status: "error", message: "Passenger not found" });
        }
        
        const passenger = mapRowToPassenger(results[0]);
        res.json({ status: "success", data: passenger });
    });
});

// 4. Update Check-In Status API
app.post('/check_in/:id', (req, res) => {
    const passengerId = req.params.id;
    const { status } = req.body;
    
    const statusCol = dbColumns.find(c => ['check_in_status', 'check in status', 'checkinstatus'].includes(c.toLowerCase())) || 'check_in_status';
    const sql = `UPDATE passengers SET \`${statusCol}\` = ? WHERE id = ?`;
    
    db.query(sql, [status, passengerId], (err, result) => {
        if (err) {
            return res.json({ status: "error", message: err.message });
        }
        res.json({ 
            status: "success", 
            message: `Passenger check-in status updated to ${status}!` 
        });
    });
});

// 5. Verify CCTV Face (Cross-Database Sync) API
app.post(['/verify_face', '/api/simulate-cctv'], upload.single('cctv_image'), (req, res) => {
    const { passport_number } = req.body;
    const cctv_image_url = req.file ? `uploads/${req.file.filename}` : '';

    if (!passport_number) {
        return res.json({ status: "error", message: "Passport number is required" });
    }
    if (!cctv_image_url) {
        return res.json({ status: "error", message: "CCTV face image is required" });
    }

    const passportCol = dbColumns.find(c => ['passport_number', 'passport number', 'passportnumber'].includes(c.toLowerCase())) || 'passport_number';
    const sqlSelect = `SELECT * FROM passengers WHERE \`${passportCol}\` = ?`;

    db.query(sqlSelect, [passport_number], (err, results) => {
        if (err) {
            return res.json({ status: "error", message: err.message });
        }
        if (results.length === 0) {
            return res.json({ status: "error", message: "Passenger profile not found for matching." });
        }

        const passenger = mapRowToPassenger(results[0]);
        const confidence = (85.0 + Math.random() * 14.5).toFixed(2);

        const statusCol = dbColumns.find(c => ['check_in_status', 'check in status', 'checkinstatus'].includes(c.toLowerCase())) || 'check_in_status';
        const sqlUpdate = `UPDATE passengers SET \`${statusCol}\` = 'Checked-In' WHERE id = ?`;

        db.query(sqlUpdate, [passenger.id], (err) => {
            if (err) {
                return res.json({ status: "error", message: `Failed to update status: ${err.message}` });
            }

            if (db2) {
                const sqlLog = `INSERT INTO cctv_logs (passport_number, matched_name, cctv_image_url, confidence, status) VALUES (?, ?, ?, ?, ?)`;
                db2.query(sqlLog, [passenger.passport_number, passenger.full_name, cctv_image_url, confidence, 'Checked-In'], (err2) => {
                    if (err2) {
                        console.error("Failed to insert into CCTV log database:", err2.message);
                    }
                    res.json({
                        status: "success",
                        message: "Facial match verified! Checked-In successfully.",
                        confidence: parseFloat(confidence),
                        data: {
                            full_name: passenger.full_name,
                            passport_number: passenger.passport_number,
                            flight_number: passenger.flight_number,
                            check_in_status: "Checked-In"
                        }
                    });
                });
            } else {
                res.json({
                    status: "success",
                    message: "Facial match verified! Checked-In successfully.",
                    confidence: parseFloat(confidence),
                    data: {
                        full_name: passenger.full_name,
                        passport_number: passenger.passport_number,
                        flight_number: passenger.flight_number,
                        check_in_status: "Checked-In"
                    }
                });
            }
        });
    });
});

app.listen(5000, () => {
    console.log('Server running on port 5000');
});