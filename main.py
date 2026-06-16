from ultralytics import YOLO
import cv2
import os
import numpy as np

# --- 1. 匯入你的字元切割類別 ---
from Segmenter import Segmenter

# ==========================================
# --- 設定區 ---
# ==========================================
# 1. 載入你的 YOLOv11 模型
model = YOLO('best_lin.pt') 

# 2. 指定輸入與輸出的資料夾路徑
input_dir = '1'     
output_dir = '1_cropped_plates'  
os.makedirs(output_dir, exist_ok=True)

# 3. 期末專案輸出 txt 設定
student_id = '412345678'  # ⚠️ 請將這裡替換成你們組長的學號！
output_txt_path = f'{student_id}.txt'

valid_extensions = ('.jpg', '.jpeg', '.png', '.bmp', '.webp')

# 實例化 Segmenter
segmenter = Segmenter()

# 打開 txt 檔案準備寫入 (使用 'w' 模式，每次執行會覆蓋舊檔)
with open(output_txt_path, 'w', encoding='utf-8') as txt_file:
    
    # --- 批次讀取與預測處理 ---
    for filename in os.listdir(input_dir):
        if filename.lower().endswith(valid_extensions):
            img_path = os.path.join(input_dir, filename)
            img = cv2.imread(img_path)
            
            if img is None:
                print(f"⚠️ 警告：無法讀取影像 {filename}")
                continue
                
            print(f"\n🔍 正在處理: {filename}")
            
            # 取得檔名 (不含副檔名，例如 "001")
            base_name = os.path.splitext(filename)[0]
            
            # 準備一個 List 來收集這張圖片中「所有」被切割出來的字元座標
            all_chars_in_image = []
            
            # 進行 YOLO 預測
            results = model(img)
            
            for i, result in enumerate(results):
                boxes = result.boxes
                
                if len(boxes) == 0:
                    print("   ❌ 未偵測到任何車牌")
                    continue
                    
                for j, box in enumerate(boxes):
                    # 取得 0-based Bounding Box 座標
                    x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                    x1_idx, y1_idx, x2_idx, y2_idx = int(x1), int(y1), int(x2), int(y2)
                    
                    # 裁切車牌並儲存
                    cropped_img = img[y1_idx:y2_idx, x1_idx:x2_idx]
                    save_path = os.path.join(output_dir, f'{base_name}_plate_{j+1}.jpg')
                    cv2.imwrite(save_path, cropped_img)
                    
                    # 計算 Segmenter 要求的寬高 (維持 0-based 給 OpenCV 運算)
                    plate_w = x2_idx - x1_idx
                    plate_h = y2_idx - y1_idx
                    location = [x1_idx, y1_idx, plate_w, plate_h]
                    
                    # 呼叫 segment 方法切割字元
                    char_bboxes = segmenter.segment(cropped_img, location)
                    
                    if len(char_bboxes) > 0:
                        # 遍歷回傳的字元座標
                        for (cx, cy, cw, ch) in char_bboxes:
                            # ⚠️ 關鍵：轉換為 1-based (左上角為 1,1)
                            cx_1based = cx + 1
                            cy_1based = cy + 1
                            
                            # 將轉換後的座標加入總表
                            all_chars_in_image.append((cx_1based, cy_1based, cw, ch))
                            
            # ==========================================
            # --- 依照專案格式寫入 txt 檔案 ---
            # ==========================================
            # 1. 寫入圖片檔名 (例如: 001) [cite: 22, 28, 33]
            txt_file.write(f"{base_name}\n")
            
            # 2. 寫入偵測到的字元數量 [cite: 23, 29, 34]
            txt_file.write(f"{len(all_chars_in_image)}\n")
            
            # 3. 逐行寫入每個字元的座標 (x1 y1 width height) [cite: 24, 25, 26, 30, 31, 32]
            for (cx, cy, cw, ch) in all_chars_in_image:
                txt_file.write(f"{cx} {cy} {cw} {ch}\n")
                
            print(f"      📝 已將 {len(all_chars_in_image)} 個字元座標寫入 {output_txt_path}")
            print("-" * 50)

print(f"\n🎉 所有照片皆已處理完畢！結果已儲存至 {output_txt_path}")