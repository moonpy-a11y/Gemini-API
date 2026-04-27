import os
import pandas as pd
from pytesseract import image_to_string
from deep_translator import GoogleTranslator
from PIL import Image

# 1. Setup local "Storage"
input_folder = './images'
output_folder = './output_text'
os.makedirs(output_folder, exist_ok=True)

results = []

print("🚀 Starting local OCR and Translation...")

# 2. Process local files
for filename in os.listdir(input_folder):
    if filename.endswith(('.png', '.jpg', '.jpeg')):
        img_path = os.path.join(input_folder, filename)
        
        # OCR Step (Local)
        print(f"Reading {filename}...")
        text_data = image_to_string(Image.open(img_path))
        
        # Save text file locally
        txt_filename = filename.split('.')[0] + '.txt'
        with open(os.path.join(output_folder, txt_filename), 'w') as f:
            f.write(text_data)

        # Translation Step (Local)
        # Using deep-translator to go to Japanese
        translated_text = GoogleTranslator(source='auto', target='ja').translate(text_data)
        
        # Store results for our "database"
        results.append({
            'original_text': text_data.strip(),
            'translated_text': translated_text,
            'file_name': filename
        })

# 3. Save to "BigQuery" (Local CSV)
df = pd.DataFrame(results)
df.to_csv('final_results.csv', index=False)

print("✅ Done! Results saved to final_results.csv")
