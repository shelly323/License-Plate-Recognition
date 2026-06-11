import cv2
import numpy as np

class PlateLocalizer:
    def __init__(self):
        a = 0

    def to_grayscale(self, image):
        """轉成灰階"""

    def prewitt_edge_detection(self, gray_img):
        """使用 Prewitt 遮罩偵測垂直邊緣"""

    def iterative_threshold(self, img):
        """動態門檻值二值化演算法""" 

    def morphology_processing(self, binary_img):
        """兩次中值濾波 -> 膨脹 -> 侵蝕 -> 再侵蝕膨脹""" 

    def filter_plate_region(self, morph_img, original_img):
        """連通域標籤化與條件篩選"""
            
    def localize(self, src_img):
        """一鍵執行的 Pipeline"""
