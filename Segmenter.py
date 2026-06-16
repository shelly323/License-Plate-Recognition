import cv2
import numpy as np

class Segmenter:
    def __init__(self):
        # 調整合理的字元特徵參數
        self.MinAspectRatio = 1.1     # 台灣新式/舊式車牌字元長寬比
        self.MaxAspectRatio = 4.5

    def segment(self, clap, location):
        """
        強化版字元切割功能
        :param clap: 經由 YOLO 裁切下來的車牌影像
        :param location: 車牌在原始大圖上的座標 [x_min, y_min, width, height]
        :return: 所有有效字元在「原圖」上的座標 [[x, y, w, h], ...]
        """
        if clap is None or clap.size == 0:
            return []

        h_plate, w_plate = clap.shape[:2]

        # 1. 影像預處理：灰階 -> 高斯模糊
        if len(clap.shape) == 3:
            gray_img = cv2.cvtColor(clap, cv2.COLOR_BGR2GRAY)
        else:
            gray_img = clap.copy()
            
        gray_img = cv2.GaussianBlur(gray_img, (3, 3), 0)

        # 2. 自適應二值化 (白字黑底)
        bw = cv2.adaptiveThreshold(gray_img, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
                                   cv2.THRESH_BINARY_INV, 15, 5)

        # 💡 強化點 1：邊緣去噪 (Border Removal)
        # 車牌外框、螺絲常在邊緣，我們將四周邊緣塗黑，避免它們與字元沾連
        border_y = int(h_plate * 0.08)
        border_x = int(w_plate * 0.04)
        bw[0:border_y, :] = 0
        bw[h_plate-border_y:, :] = 0
        bw[:, 0:border_x] = 0
        bw[:, w_plate-border_x:] = 0

        # 💡 強化點 2：形態學閉合運算 (Closing)
        # 連接可能因為反光或雜訊而微幅斷裂的字元結構
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 3))
        bw = cv2.morphologyEx(bw, cv2.MORPH_CLOSE, kernel)

        # 3. 連通物件分析
        num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(bw, connectivity=8)

        # 💡 強化點 3：智能動態中位數估算
        # 先粗篩出「像字元」的物件高度，再來算中位數，避免背景大雜訊干擾
        potential_heights = []
        for i in range(1, num_labels):
            h = stats[i, cv2.CC_STAT_HEIGHT]
            w = stats[i, cv2.CC_STAT_WIDTH]
            # 字元高度通常佔車牌總高的 45% ~ 90% 之間
            if (h > h_plate * 0.4) and (h < h_plate * 0.95) and (h > w):
                potential_heights.append(h)

        if len(potential_heights) > 0:
            median_height = np.median(potential_heights)
        else:
            median_height = h_plate * 0.7  # 預估防呆值

        valid_bboxes = []
        
        # 4. 核心字元篩選與動態切分
        for i in range(1, num_labels):
            x = stats[i, cv2.CC_STAT_LEFT]
            y = stats[i, cv2.CC_STAT_TOP]
            w = stats[i, cv2.CC_STAT_WIDTH]
            h = stats[i, cv2.CC_STAT_HEIGHT]
            
            if w == 0 or h == 0: 
                continue
                
            aspect_ratio = h / w

            # 💡 強化點 4：更具彈性的字元高度與比例篩選
            is_good_height = (h > median_height * 0.7) and (h < median_height * 1.3)
            is_good_ratio = (aspect_ratio >= self.MinAspectRatio) and (aspect_ratio <= self.MaxAspectRatio)

            if is_good_height and is_good_ratio:
                # 收集正常字元
                global_x = x + location[0]
                global_y = y + location[1]
                valid_bboxes.append([global_x, global_y, w, h])
                
            # 💡 強化點 5：升級版沾黏處理（如果物件高度對，但寬度太寬）
            elif is_good_height and (w > median_height * 0.85):
                # 這代表有 2 個或以上的字元橫向黏在一起了
                num_chars_nested = max(2, int(round(w / (median_height * 0.55))))
                sub_w = int(w / num_chars_nested)
                
                for n in range(num_chars_nested):
                    local_x = x + (n * sub_w)
                    global_x = local_x + location[0]
                    global_y = y + location[1]
                    # 防邊界溢出
                    if (n * sub_w) + sub_w <= w:
                        valid_bboxes.append([global_x, global_y, sub_w, h])

        # 💡 強化點 6：由左至右排序，並透過非極大值抑制（NMS）概念排除重疊錯誤的框
        if len(valid_bboxes) > 0:
            final_bboxes = sorted(valid_bboxes, key=lambda b: b[0])
            
            # 排除重複或嚴重重疊的框
            filtered_bboxes = []
            for box in final_bboxes:
                if not filtered_bboxes:
                    filtered_bboxes.append(box)
                    continue
                # 如果目前的框跟上一個框的 X 座標太接近(重疊度高)，視為雜訊排除
                last_box = filtered_bboxes[-1]
                if abs(box[0] - last_box[0]) < (median_height * 0.2):
                    # 保留高度較接近中位數的那個
                    if abs(box[3] - median_height) < abs(last_box[3] - median_height):
                        filtered_bboxes[-1] = box
                else:
                    filtered_bboxes.append(box)
            return filtered_bboxes
            
        return []