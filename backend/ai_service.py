import os
import cv2
import numpy as np
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/match-face', methods=['POST'])
def match_face():
    try:
        profile_image_path = request.form.get('profile_image')
        cctv_image_path = request.form.get('cctv_image')

        if not profile_image_path or not cctv_image_path:
            return jsonify({"status": "error", "message": "Image paths are missing"})

        if not os.path.exists(profile_image_path) or not os.path.exists(cctv_image_path):
            return jsonify({"status": "error", "message": "Image files not found on disk"})

        # OpenCV මඟින් පින්තූර දෙක කියවීම (Grayscale)
        img1 = cv2.imread(profile_image_path, cv2.IMREAD_GRAYSCALE)
        img2 = cv2.imread(cctv_image_path, cv2.IMREAD_GRAYSCALE)

        if img1 is None or img2 is None:
            return jsonify({"status": "error", "message": "Could not read image files"})

        # ප්‍රමාණය එකම මට්ටමකට සැකසීම
        img1 = cv2.resize(img1, (200, 200))
        img2 = cv2.resize(img2, (200, 200))

        # Histogram Comparison (cv2.HISTCMP_CORREL පාවිච්චි කිරීම)
        hist1 = cv2.calcHist([img1], [0], None, [256], [0, 256])
        hist2 = cv2.calcHist([img2], [0], None, [256], [0, 256])
        
        cv2.normalize(hist1, hist1, alpha=0, beta=1, norm_type=cv2.NORM_MINMAX)
        cv2.normalize(hist2, hist2, alpha=0, beta=1, norm_type=cv2.NORM_MINMAX)

        # මෙහි COMP_CORREL වෙනුවට HISTCMP_CORREL යොදා ඇත
        similarity = cv2.compareHist(hist1, hist2, cv2.HISTCMP_CORREL)
        
        confidence = round(similarity * 100, 2)
        if confidence < 0: confidence = 10.0

        is_match = similarity > 0.50  # ගැලපීමේ සීමාව (Threshold)

        if is_match:
            return jsonify({
                "status": "success",
                "matched": True,
                "confidence": confidence,
                "message": "Images matched successfully!"
            })
        else:
            return jsonify({
                "status": "success",
                "matched": False,
                "confidence": confidence,
                "message": "Image mismatch! The CCTV image does not match the profile."
            })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

if __name__ == '__main__':
    app.run(port=5001)