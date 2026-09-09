import os
import requests

TARGET_DIR = r"D:\MobileAPP\backend\dataset_faces"
os.makedirs(TARGET_DIR, exist_ok=True)

print("Display ok")

res = requests.get("https://randomuser.me/api/?results=100&inc=picture&noinfo", timeout=20)
results = res.json().get("results", [])

for idx, person in enumerate(results, start=1):
    img_url = person["picture"]["large"]
    img_data = requests.get(img_url, timeout=10).content
    
    file_path = os.path.join(TARGET_DIR, f"{idx}.jpg")
    with open(file_path, "wb") as f:
        f.write(img_data)
        
    print(f"[+] [{idx:03d}/100] Saved viewable photo: {idx}.jpg")

print(f"\n success {TARGET_DIR}")