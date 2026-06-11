import cv2
import numpy as np

class PlateRecognizer:
    def __init__(self, template_dataset=None):
        a = 0

    def preprocess_plate(self, plate_img):
        """車牌辨識的前處理：灰階 -> 中值濾波 -> 均值二值化""" 
    def crop_boundaries(self, binary_plate):
        """切除上下左右非字元邊界"""

    def segment_characters(self, cropped_plate):
        """依序切割出 6 個字元並處理『-』與『1』的特殊情況""" 

    def recognize(self, plate_img):
        """一鍵辨識的 Pipeline"""
        