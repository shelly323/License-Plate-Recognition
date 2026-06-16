from ultralytics import YOLO
import cv2
import os
import numpy as np
from Segmenter import Segmenter

# 1. 載入你的 YOLOv11 模型
model = YOLO('best.pt') 

# 2. 指定輸入與輸出的資料夾路徑
input_dir = '10'     
output_dir = '10_cropped_plates'  
visual_output_dir = '10_visualized_results_1'

os.makedirs(output_dir, exist_ok=True)
os.makedirs(visual_output_dir, exist_ok=True)

student_id = '411285036'  
output_txt_path = f'{student_id}.txt'

valid_extensions = ('.jpg')

segmenter = Segmenter()

with open(output_txt_path, 'w', encoding='utf-8') as txt_file:
    
    for filename in os.listdir(input_dir):
        if filename.lower().endswith(valid_extensions):
            img_path = os.path.join(input_dir, filename)
            img = cv2.imread(img_path)
            
            if img is None:
                print(f"無法讀取影像 {filename}")
                continue
                
            print(f"\n正在處理: {filename}")
            
            base_name = os.path.splitext(filename)[0]
            all_chars_in_image = []
            
            # 複製一張原圖，專門用來在上面畫框（避免污染要送進辨識的原始資料）
            vis_img = img.copy()
            
            # 進行 YOLO 預測
            results = model(img)
            
            for result in results:
                boxes = result.boxes
                
                if len(boxes) == 0:
                    print("未偵測到任何車牌")
                    continue
                
                best_box = None
                max_conf = -1.0
                
                for box in boxes:
                    conf = float(box.conf[0].cpu().numpy())
                    if conf > max_conf:
                        max_conf = conf
                        best_box = box
                
                if best_box is not None:
                    # 取得 0-based Bounding Box 座標
                    x1, y1, x2, y2 = best_box.xyxy[0].cpu().numpy()
                    x1_idx, y1_idx, x2_idx, y2_idx = int(x1), int(y1), int(x2), int(y2)
                    
                    cv2.rectangle(vis_img, (x1_idx, y1_idx), (x2_idx, y2_idx), (0, 0, 255), 3)
                    cv2.putText(vis_img, f"Plate: {max_conf:.2f}", (x1_idx, max(y1_idx - 10, 15)),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
                    
                    cropped_img = img[y1_idx:y2_idx, x1_idx:x2_idx]
                    save_path = os.path.join(output_dir, f'{base_name}_best_plate.jpg')
                    cv2.imwrite(save_path, cropped_img)
                    
                    plate_w = x2_idx - x1_idx
                    plate_h = y2_idx - y1_idx

                    if plate_w < 15 or plate_h < 5:
                        continue

                    location = [x1_idx, y1_idx, plate_w, plate_h]
                    
                    char_bboxes = segmenter.segment(cropped_img, location)
                    
                    if len(char_bboxes) > 0:
                        for (cx, cy, cw, ch) in char_bboxes:
                            cx_1based = cx + 1
                            cy_1based = cy + 1
                            all_chars_in_image.append((cx_1based, cy_1based, cw, ch))
                            
                            cv2.rectangle(vis_img, (cx, cy), (cx + cw, cy + ch), (0, 255, 0), 2)
                            
                    print(f"挑選最高信心度車牌進行處理 (Conf: {max_conf:.4f})")
            
            vis_save_path = os.path.join(visual_output_dir, f'{base_name}_result.jpg')
            cv2.imwrite(vis_save_path, vis_img)
            print(f"已儲存視覺化結果至: {vis_save_path}")
                            
            txt_file.write(f"{base_name}\n")
            txt_file.write(f"{len(all_chars_in_image)}\n")
            for (cx, cy, cw, ch) in all_chars_in_image:
                txt_file.write(f"{cx} {cy} {cw} {ch}\n")
                
            print(f"已將 {len(all_chars_in_image)} 個字元座標寫入 {output_txt_path}")
            print("-" * 50)

print(f"\n所有照片皆已處理完畢！視覺化圖檔已存在 '{visual_output_dir}' 資料夾中！")