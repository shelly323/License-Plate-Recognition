clc; clear; close all;

% p = PlateLocalizer();
% [clap, location] = p.localizer(imread("C:\\Users\\hello\\Desktop\\影像處理\\sample 2026\\sample 2026\\002.jpg"));
% figure, imshow(clap);



% 讀取原圖
img_path = "C:\Users\hello\Desktop\影像處理\sample 2026\sample 2026\004.jpg";
original_img = imread(img_path);

% 實例化 (Instantiate) 兩個類別
localizer = PlateLocalizer();
segmenter = Segmenter();

% --- 如果需要微調參數，可以直接在這裡修改，不用動到 Class 裡面 ---
% segmenter.NoiseAreaThreshold = 150; 
% segmenter.MinAspectRatio = 1.5;

% 步驟 1: 找出車牌位置與影像
[clap, location] = localizer.localizer(original_img);

% 步驟 2: 執行字元切割與過濾
char_bboxes = segmenter.segment(clap, location);

% --- 驗證與繪圖 ---
figure;
imshow(original_img);
title('最終字元 Bounding Box (原圖座標)');
hold on;

% 畫出車牌大框 (藍色)
rectangle('Position', location, 'EdgeColor', 'b', 'LineWidth', 2);

% 畫出字元小框 (紅色)
for i = 1:size(char_bboxes, 1)
    rectangle('Position', char_bboxes(i, :), 'EdgeColor', 'r', 'LineWidth', 2);
    % 在框的上方標示字元順序編號
    % text(char_bboxes(i, 1), char_bboxes(i, 2)-10, num2str(i), 'Color', 'r', 'FontSize', 12);
end
hold off;

% 依照規定輸出
fprintf('找到 %d 個字元\n', size(char_bboxes, 1));
for i = 1:size(char_bboxes, 1)
    fprintf('%.f %.f %.f %.f\n', char_bboxes(i, 1), char_bboxes(i, 2), char_bboxes(i, 3), char_bboxes(i, 4));
end