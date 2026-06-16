import cv2
import numpy as np

class Segmenter:
    def __init__(self):
        # 這裡放「參數」，代表這個類別知道的狀態與過濾條件
        self.NoiseAreaThreshold = 140 # OpenCV 裡可以自訂過濾，或用迴圈處理
        self.MinCharArea = 100        # 字元最小面積
        self.MaxCharArea = 5000       # 字元最大面積
        self.MinAspectRatio = 1.2     # 字元最小長寬比 (高/寬)
        self.MaxAspectRatio = 4.0     # 字元最大長寬比 (高/寬)

    def segment(self, clap, location):
        """
        核心切割功能
        :param clap: PlateLocalizer 切割下來的車牌影像 (numpy array)
        :param location: 車牌在原始大圖上的座標 [x_min, y_min, width, height]
        :return: 所有有效字元在「原圖」上的座標 [[x, y, w, h], ...]
        """
        # 1. 確保影像為灰階
        if len(clap.shape) == 3:
            gray_img = cv2.cvtColor(clap, cv2.COLOR_BGR2GRAY)
        else:
            gray_img = clap.copy()

        # 2. 二值化（Adaptive Method）並反轉成白字黑底
        # blockSize=15, C=5 是 OpenCV 中處理文字的常見預設值，可視情況微調
        bw = cv2.adaptiveThreshold(gray_img, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
                                   cv2.THRESH_BINARY_INV, 15, 5)

        # 1. 先做一次初步的連通物件分析 (connectivity=8 代表八方位連通)
        num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(bw, connectivity=8)

        # 2. 巡視所有初步找到的框 (忽略 index 0，因為 0 是背景)
        for i in range(1, num_labels):
            x_start = stats[i, cv2.CC_STAT_LEFT]
            y_start = stats[i, cv2.CC_STAT_TOP]
            w = stats[i, cv2.CC_STAT_WIDTH]
            h = stats[i, cv2.CC_STAT_HEIGHT]
            
            # --- 智能判斷：這個框是不是太胖了？ ---
            # 正常字元 w < h。如果 w > h * 0.85，極高機率是沾黏！
            if w > h * 0.85:
                # 把它單獨抓出來 (局部 ROI)
                roi = bw[y_start : y_start+h, x_start : x_start+w]
                
                # 計算這個框內的垂直投影 (由上往下加總白點)
                # 因為 bw 裡面的白色是 255，我們先除以 255 變成 1 方便計算
                v_proj = np.sum(roi // 255, axis=0)
                
                # 尋找「最少白點」的直行 (也就是沾黏最薄弱的地方)
                search_start = max(1, int(round(w * 0.2)))
                search_end = min(w, int(round(w * 0.8)))
                
                if search_start < search_end:
                    # np.argmin 會回傳陣列中的最小值 index
                    min_idx = np.argmin(v_proj[search_start : search_end])
                    
                    # 計算出斷點在原始影像上的 X 座標
                    cut_x_local = search_start + min_idx
                    global_cut_x = x_start + cut_x_local
                    
                    # --- 執行外科手術切割 ---
                    cut_thickness = 1 
                    safe_left = max(0, global_cut_x - cut_thickness)
                    safe_right = min(bw.shape[1], global_cut_x + cut_thickness + 1)
                    
                    # 畫一條黑色垂直線強制切斷 (OpenCV 裡黑色是 0)
                    bw[y_start : y_start+h, safe_left : safe_right] = 0

        # ------------------新方法：高度中位數過濾--------------------
        # 4. 再次取得連通物件特徵 (切割後的全新狀態)
        num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(bw, connectivity=8)
        img_height = bw.shape[0]

        # 收集所有物件的高度 (忽略背景 0)
        all_heights = stats[1:, cv2.CC_STAT_HEIGHT]

        # 排除極端值（極小的雜訊或極大的邊框），找出「中位數高度」
        valid_heights = all_heights[all_heights > img_height * 0.1]
        
        if len(valid_heights) > 0:
            median_height = np.median(valid_heights)
        else:
            median_height = 0 # 防呆

        valid_bboxes = []
        
        # 5. 迴圈過濾特徵
        for i in range(1, num_labels):
            x = stats[i, cv2.CC_STAT_LEFT]
            y = stats[i, cv2.CC_STAT_TOP]
            w = stats[i, cv2.CC_STAT_WIDTH]
            h = stats[i, cv2.CC_STAT_HEIGHT]
            area = stats[i, cv2.CC_STAT_AREA]
            
            if w == 0: continue # 避免除以 0 的錯誤
            aspect_ratio = h / w
            
            if median_height > 0:
                # --- 相對特徵篩選條件 ---
                is_similar_height = (h > median_height * 0.8) and (h < median_height * 1.2)
                is_valid_ratio = (aspect_ratio > 1.2)
                
                if is_similar_height and is_valid_ratio:
                    # 關鍵步驟：座標回推至原圖
                    # Python 是從 0 開始，所以不需要像 MATLAB 那樣減 1！
                    global_x = x + location[0]
                    global_y = y + location[1]
                    
                    valid_bboxes.append([global_x, global_y, w, h])

        # 6. 由左至右排序並格式化
        if len(valid_bboxes) > 0:
            # Python 中使用 sorted 搭配 lambda 函數，根據第 0 個元素 (x) 排序
            final_bboxes = sorted(valid_bboxes, key=lambda b: b[0])
        else:
            final_bboxes = []
            
        return final_bboxes

# 主程式呼叫範例 (相當於 MATLAB 的 main)
if __name__ == "__main__":
    # original_img = cv2.imread("001.jpg")
    # clap = original_img[y:y+h, x:x+w] # 假設這是 Localizer 給出的
    # location = [x, y, w, h]
    
    # segmenter = Segmenter()
    # bboxes = segmenter.segment(clap, location)
    # print(bboxes)
    pass