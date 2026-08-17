const express = require('express');
const mysql = require('mysql2');
const multer = require('multer');
const path = require('path');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// MySQL Database Connection
const db = mysql.createConnection({
    host: 'localhost',
    user: 'root',
    password: '',
    database: 'airport_db'
});

let dbColumns = [];

db.connect((err) => {
    if (err) {
        console.error('Database connection failed:', err);
        return;
    }
    console.log('Connected to MySQL Database!');

    // Fetch column names dynamically to handle spaces and specific spelling variations
    db.query("DESCRIBE passengers", (err, results) => {
        if (err) {
            console.error('Error verifying passengers table schema:', err.message);
            return;
        }
        dbColumns = results.map(row => row.Field);
        console.log('Detected database columns:', dbColumns);
    });
});

// Helper function to map database rows with arbitrary naming to standard API structure
function mapRowToPassenger(row) {
    if (!row) return null;
    
    const fullName = row['full name'] || row['full_name'] || row['fullname'] || '';
    const flightNumber = row['flight number'] || row['flight_number'] || row['flightnumber'] || '';
    const passportNumber = row['passport number'] || row['passport_number'] || row['passportnumber'] || '';
    
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
    const { full_name, flight_number, passport_number } = req.body;
    const face_image_url = req.file ? `uploads/${req.file.filename}` : '';

    // Find the correct column names in the database
    const nameCol = dbColumns.find(c => ['full_name', 'full name', 'fullname'].includes(c.toLowerCase())) || 'full_name';
    const flightCol = dbColumns.find(c => ['flight_number', 'flight number', 'flightnumber'].includes(c.toLowerCase())) || 'flight_number';
    const passportCol = dbColumns.find(c => ['passport_number', 'passport number', 'passportnumber'].includes(c.toLowerCase())) || 'passport_number';
    const faceCol = dbColumns.find(c => ['face_image_url', 'face image url', 'faceimageurl', 'facr_image_url', 'facr image url'].includes(c.toLowerCase())) || 'face_image_url';
    const statusCol = dbColumns.find(c => ['check_in_status', 'check in status', 'checkinstatus'].includes(c.toLowerCase()));

    const fields = [`\`${nameCol}\``, `\`${flightCol}\``, `\`${passportCol}\``, `\`${faceCol}\``];
    const values = [full_name, flight_number, passport_number, face_image_url];
    const placeholders = ['?', '?', '?', '?'];

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

app.listen(5000, () => {
    console.log('Server running on port 5000');
});