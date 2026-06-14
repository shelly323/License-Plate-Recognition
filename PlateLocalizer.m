classdef PlateLocalizer
    % 輸出切好的車牌圖片、車牌在原圖中的原始座標 [x, y, width, height]
    properties
        % 將原本固定的結構元素改為動態參數，並微調面積與長寬比門檻
        StructureSize = [5, 20];   % 適合將字元水平連通的矩形大小
        MinPlateArea = 1000;       % 調低門檻，以適應遠景小車牌 (如 002.jpg)
        MaxPlateArea = 60000;      % 限制上限，避免抓到整個車頭 (如 020.jpg)
        MinRatio = 2.0;            % 台灣車牌長寬比下限
        MaxRatio = 4.5;            % 台灣車牌長寬比上限
    end
    
    methods 
        function obj = PlateLocalizer()
        end

        function [img_clap, plate_location] = localizer(obj, img)
            gray_img = rgb2gray(img); 
            enhanced_img = adapthisteq(gray_img); 
    
            % 使用 Sobel 算子偵測垂直邊緣
            edge_img = edge(enhanced_img, 'sobel', 'vertical'); 
            se = strel('rectangle', obj.StructureSize);
            
            closed_img = imclose(edge_img, se);
            
            filled_img = imfill(closed_img, 'holes');
            
            % 步驟 C：使用開運算去除周圍獨立的毛邊與微小雜訊，這比單純的侵蝕更溫和
            cleaned_img = imopen(filled_img, strel('rectangle', [3, 3]));
            
            figure('Name', '車牌影像處理中間步驟', 'NumberTitle', 'off');
            subplot(2, 3, 1); imshow(gray_img); title('1. 原始灰階');
            subplot(2, 3, 2); imshow(enhanced_img); title('2. 對比度增強');
            subplot(2, 3, 3); imshow(edge_img); title('3. 垂直邊緣偵測');
            subplot(2, 3, 4); imshow(closed_img); title('4. 形態學閉合');
            subplot(2, 3, 5); imshow(filled_img); title('5. 孔洞填滿');
            subplot(2, 3, 6); imshow(cleaned_img); title('6. 開運算去雜訊');
    
            stats = regionprops(cleaned_img, 'Area', 'BoundingBox');
            
            best_score = -1;
            plate_location = [];
            
            for i = 1:length(stats)
                area = stats(i).Area;
                box = stats(i).BoundingBox; % [x, y, w, h]
                w = box(3);
                h = box(4);
                ratio = w / h;
                
                % 第一輪：放寬的基本幾何門檻過濾
                if (area >= obj.MinPlateArea) && (area <= obj.MaxPlateArea) && ...
                   (ratio >= obj.MinRatio) && (ratio <= obj.MaxRatio)
                    
                    row_start = max(1, floor(box(2)));
                    row_end = min(size(enhanced_img, 1), ceil(box(2) + box(4)));
                    col_start = max(1, floor(box(1)));
                    col_end = min(size(enhanced_img, 2), ceil(box(1) + box(3)));
                    
                    local_gray = enhanced_img(row_start:row_end, col_start:col_end);
                    
                    % 2. 對這個局部區域單獨做垂直邊緣偵測（避免受到整張圖全域閾值的干擾）
                    local_edge = edge(local_gray, 'sobel', 'vertical');
                    
                    % 3. 計算邊緣密度：白色像素總數 / 區域總像素點
                    edge_pixels = sum(local_edge(:)); % 統計矩陣中為 1 (白) 的點有幾個
                    total_pixels = numel(local_edge); % 該區域總共有幾個像素點
                    edge_density = edge_pixels / total_pixels;

                    score = 0;
                    
                    % 【特徵 A】車牌寬度評分（移除 continue 地雷，改為純加分制）
                    % 這能讓它同時適應大車牌(圖20)與小車牌(圖2)
                    if (w >= 70) && (w <= 160)
                        score = score + 40; % 中小型車牌
                    elseif (w > 160) && (w <= 300)
                        score = score + 50; % 近景大車牌（特別為圖20優化）
                    else
                        score = score + 10;
                    end
                    
                    % 【特徵 B】台灣車牌標準長寬比評分 (標準值約 2.5 ~ 3.8)
                    if (ratio >= 2.4) && (ratio <= 4.0)
                        score = score + 40; % 比例非常完美，給高分！
                    else
                        score = score + 10; 
                    end
                    
                    % 【特徵 C】Y 軸垂直位置評分（放寬標準，貼近中央的給予獎勵分）
                    img_height = size(img, 1);
                    if (box(2) > img_height * 0.2) && (box(2) < img_height * 0.8) 
                       score = score + 20; 
                    end
                    
                    if (edge_density >= 0.15) && (edge_density <= 0.38)
                        score = score + 50; % 邊緣密度非常符合車牌特徵，給予高分獎勵！
                    elseif (edge_density < 0.08)
                        % 密度太低：極有可能是商標貼紙（如運通貼紙的大塊純色背景）或板金反光
                        score = score - 40; % 扣大分，直接排除
                    else
                        score = score + 50; % 其他適中範圍給予基本分
                    end

                    % 3. 挑選評分最高的候選區塊
                    if score > best_score
                        best_score = score;
                        plate_location = box;
                    end

                end
            end

            if ~isempty(plate_location)
                % 稍微擴大裁切邊界（上下左右多留 4 像素），避免字元邊緣被切到，利於後續 OCR 辨識
                pad = 4;
                img_w = size(img, 2);
                img_h = size(img, 1);
                
                x_min = max(1, plate_location(1) - pad);
                y_min = max(1, plate_location(2) - pad);
                x_max = min(img_w, plate_location(1) + plate_location(3) + pad);
                y_max = min(img_h, plate_location(2) + plate_location(4) + pad);
                
                crop_rect = [x_min, y_min, x_max - x_min, y_max - y_min];
                img_clap = imcrop(img, crop_rect); 
                plate_location = crop_rect; % 更新 location 為裁切後的區域座標
            else
                img_clap = [];
                warning('警告：在此影像中未偵測到任何符合車牌特徵的區域！');
            end
        end
    end
end