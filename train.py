from ultralytics import YOLO

# 1. 載入 YOLOv11 的預訓練模型 (n代表nano，適合一般辨識與邊緣運算，速度最快)
model = YOLO('yolo11n.pt')

# 2. 開始訓練
# 請確保 data='...' 這裡的路徑指向你剛剛下載下來的 data.yaml 檔案
results = model.train(
    data="D:/User/Downloads/platerecognition.yolov11/data.yaml", 
    epochs=100,         # 訓練的總回合數 (可依需求調整，通常 100-300)
    imgsz=640,          # 圖片輸入大小
    batch=16,           # 每次處理的圖片數量 (若顯卡記憶體不夠可調降為 8 或 4)
    name='plate_model', # 訓練結果存檔的資料夾名稱
    device='cpu'      # 指定使用第 0 張 GPU (如果是用 CPU 則填寫 'cpu')
)

print("🎉 訓練完成！")