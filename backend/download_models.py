import os
import urllib.request

# 1. Create 'models' directory if it doesn't exist
os.makedirs("models", exist_ok=True)

# 2. Define the direct raw URLs for YuNet and SFace models from OpenCV Zoo
models = {
    "models/face_detection_yunet_2023mar.onnx": "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx",
    "models/face_recognition_sface_2021dec.onnx": "https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx"
}

# 3. Download files one by one with progress indicator
for path, url in models.items():
    if not os.path.exists(path):
        print(f"Downloading {path} (This may take a moment)...")
        try:
            urllib.request.urlretrieve(url, path)
            print(f"Successfully downloaded: {path}")
        except Exception as e:
            print(f"Failed to download {path}. Error: {e}")
    else:
        print(f"File already exists: {path}")

print("All model files are ready!")