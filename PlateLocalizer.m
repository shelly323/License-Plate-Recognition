classdef PlateLocalizer
    % =========================================================================
    % 車牌擷取與定位系統 (License Plate Localizer)
    % 輸出：切好的車牌圖片 (img_clap)、車牌在原圖中的原始座標 [x, y, width, height]
    % 核心技術：自適應直方圖均衡化 + 垂直邊緣形態學 + 五維度特徵評分機制 + 雙極性檢測
    % =========================================================================
    
    properties
        % --- 基礎幾何與形態學參數 ---
        StructureSize = [5, 20];   
        MinPlateArea = 1000;       
        MaxPlateArea = 60000;      
        % 【關鍵修改 1】：大幅放寬長寬比下限，以容忍「傾斜/側拍」導致的 BoundingBox 變形
        MinRatio = 1.2;            % 從 2.0 降至 1.2
        MaxRatio = 5.0;            % 微調上限
    end
    
    methods 
        function obj = PlateLocalizer()
        end

        function [img_clap, plate_location] = localizer(obj, img, print_img)
            if nargin < 3
                print_img = false;
            end
            
            %% 1. 影像預處理與對比度增強
            if size(img, 3) == 3
                gray_img = rgb2gray(img); 
            else
                gray_img = img;
            end
            
            enhanced_img = adapthisteq(gray_img); 
    
            %% 2. 邊緣偵測與形態學連通
            edge_img = edge(enhanced_img, 'sobel', 'vertical'); 
            
            se = strel('rectangle', obj.StructureSize);
            closed_img = imclose(edge_img, se);
            
            filled_img = imfill(closed_img, 'holes');
            
            cleaned_img = imopen(filled_img, strel('rectangle', [3, 3]));
            
            %% 3. 中間步驟視覺化
            if (print_img)
                figure('Name', '車牌影像處理中間步驟', 'NumberTitle', 'off');
                subplot(2, 3, 1); imshow(gray_img); title('1. 原始灰階');
                subplot(2, 3, 2); imshow(enhanced_img); title('2. 局部對比度增強');
                subplot(2, 3, 3); imshow(edge_img); title('3. 垂直邊緣偵測');
                subplot(2, 3, 4); imshow(closed_img); title('4. 形態學閉合');
                subplot(2, 3, 5); imshow(filled_img); title('5. 孔洞填滿');
                subplot(2, 3, 6); imshow(cleaned_img); title('6. 開運算去雜訊');
            end
    
            %% 4. 提取連通元件特徵與五維度評分
            stats = regionprops(cleaned_img, 'Area', 'BoundingBox');
            
            best_score = -1;
            plate_location = [];
            
            for i = 1:length(stats)
                area = stats(i).Area;
                box = stats(i).BoundingBox; % [x, y, w, h]
                w = box(3);
                h = box(4);
                ratio = w / h;
                
                % 第一道防線：放寬後的基礎幾何門檻過濾
                if (area >= obj.MinPlateArea) && (area <= obj.MaxPlateArea) && ...
                   (ratio >= obj.MinRatio) && (ratio <= obj.MaxRatio)
                    
                    row_start = max(1, floor(box(2)));
                    row_end = min(size(enhanced_img, 1), ceil(box(2) + box(4)));
                    col_start = max(1, floor(box(1)));
                    col_end = min(size(enhanced_img, 2), ceil(box(1) + box(3)));
                    
                    score = 0;
                    
                    % ---------------------------------------------------------
                    % 【特徵 A】車牌寬度自適應評分
                    % ---------------------------------------------------------
                    if (w >= 70) && (w <= 160)
                        score = score + 40; 
                    elseif (w > 160) && (w <= 300)
                        score = score + 50; 
                    else
                        score = score + 10; 
                    end
                    
                    % ---------------------------------------------------------
                    % 【特徵 B】標準長寬比評分
                    % ---------------------------------------------------------
                    if (ratio >= 2.4) && (ratio <= 4.0)
                        score = score + 40; 
                    else
                        score = score + 10; 
                    end
                    
                    % ---------------------------------------------------------
                    % 【特徵 C】Y 軸垂直位置評分
                    % ---------------------------------------------------------
                    img_height = size(img, 1);
                    if (box(2) > img_height * 0.2) && (box(2) < img_height * 0.8) 
                       score = score + 20;  
                    end
                    
                    % ---------------------------------------------------------
                    % 【特徵 D】邊緣密度分析
                    % ---------------------------------------------------------
                    local_gray = enhanced_img(row_start:row_end, col_start:col_end);
                    local_edge = edge(local_gray, 'sobel', 'vertical');
                    edge_density = sum(local_edge(:)) / numel(local_edge);

                    if (edge_density >= 0.15) && (edge_density <= 0.38)
                        score = score + 50; 
                    elseif (edge_density < 0.08)
                        score = score - 40; 
                    else
                        score = score + 50; 
                    end

                    % ---------------------------------------------------------
                    % 【特徵 E】雙極性文字連通元件檢查
                    % ---------------------------------------------------------
                    pad_cc = 2;
                    row_start_cc = max(1, floor(box(2)) - pad_cc);
                    row_end_cc = min(size(gray_img, 1), ceil(box(2) + box(4)) + pad_cc);
                    col_start_cc = max(1, floor(box(1)) - pad_cc);
                    col_end_cc = min(size(gray_img, 2), ceil(box(1) + box(3)) + pad_cc);

                    local_gray_raw = gray_img(row_start_cc:row_end_cc, col_start_cc:col_end_cc);
                    
                    bin_dark_text = ~imbinarize(local_gray_raw, 'adaptive', 'Sensitivity', 0.4);
                    bin_light_text = imbinarize(local_gray_raw, 'adaptive', 'Sensitivity', 0.4);
                    
                    bins_to_test = {bin_dark_text, bin_light_text};
                    max_valid_char_count = 0; 
                    
                    for b = 1:2
                        current_bin = imclearborder(bins_to_test{b});
                        char_stats = regionprops(current_bin, 'Area', 'BoundingBox');
                        
                        count = 0;
                        local_h = size(current_bin, 1);
                        
                        for k = 1:length(char_stats)
                            char_h = char_stats(k).BoundingBox(4);
                            char_area = char_stats(k).Area;
                            % 【關鍵修改 2】：將高度比例從 0.4 降至 0.3，面積限制從 50 降至 30
                            % 用以包容傾斜導致的包圍盒高度膨脹與字元變形
                            if (char_h > local_h * 0.3) && (char_h < local_h * 0.95) && (char_area > 30)
                                count = count + 1;
                            end
                        end
                        
                        if count > max_valid_char_count
                            max_valid_char_count = count;
                        end
                    end
                    
                    if (max_valid_char_count >= 5) && (max_valid_char_count <= 8)
                        score = score + 60;  
                    elseif (max_valid_char_count <= 2)
                        score = score - 80;  
                    else
                        score = score - 20;  
                    end
                    % ---------------------------------------------------------

                    if score > best_score
                        best_score = score;
                        plate_location = box;
                    end
                end
            end

            %% 5. 影像裁切與安全邊際輸出
            if ~isempty(plate_location)
                pad = 4;
                img_w = size(img, 2);
                img_h = size(img, 1);
                
                x_min = max(1, plate_location(1) - pad);
                y_min = max(1, plate_location(2) - pad);
                x_max = min(img_w, plate_location(1) + plate_location(3) + pad);
                y_max = min(img_h, plate_location(2) + plate_location(4) + pad);
                
                crop_rect = [x_min, y_min, x_max - x_min, y_max - y_min];
                img_clap = imcrop(img, crop_rect); 
            else
                img_clap = [];
                warning('警告：在此影像中未偵測到任何符合車牌特徵的區域！');
            end
        end
    end
end