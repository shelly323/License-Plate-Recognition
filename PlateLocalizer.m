classdef PlateLocalizer
    % =========================================================================
    % 車牌擷取與定位系統 (高雜訊抗性升級版：除雨滴 + 嚴格邊緣 + 車輪防禦)
    % =========================================================================
    
    properties
        % 微調構造元素，避免在密集雜訊中過度連結導致車牌沾黏保險桿
        StructureSize = [4, 18];   
        MinPlateArea = 800;       
        MaxPlateArea = 80000;      
        MinRatio = 1.2;            
        MaxRatio = 6.0;            
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
            
            % 【關鍵優化 1】：中值濾波器，強效抹除雨滴、泥沙等點狀高頻雜訊
            smooth_img = medfilt2(enhanced_img, [3 3]);
    
            %% 2. 邊緣偵測與形態學連通
            % 【關鍵優化 2】：取得自動閾值並嚴格化 (乘上 1.25)，過濾掉微弱的保險桿紋理與水痕
            [~, thresh] = edge(smooth_img, 'sobel', 'vertical');
            edge_img = edge(smooth_img, 'sobel', 'vertical', thresh * 1.25); 
            
            se = strel('rectangle', obj.StructureSize);
            closed_img = imclose(edge_img, se);
            
            filled_img = imfill(closed_img, 'holes');
            
            cleaned_img = imopen(filled_img, strel('rectangle', [3, 3]));
            
            %% 3. 中間步驟視覺化
            if (print_img)
                figure('Name', '車牌影像處理中間步驟', 'NumberTitle', 'off');
                subplot(2, 3, 1); imshow(gray_img); title('1. 原始灰階');
                subplot(2, 3, 2); imshow(smooth_img); title('2. 對比增強與去噪');
                subplot(2, 3, 3); imshow(edge_img); title('3. 嚴格垂直邊緣');
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
                box = stats(i).BoundingBox; 
                w = box(3);
                h = box(4);
                ratio = w / h;
                
                if (area >= obj.MinPlateArea) && (area <= obj.MaxPlateArea) && ...
                   (ratio >= obj.MinRatio) && (ratio <= obj.MaxRatio)
                    
                    row_start = max(1, floor(box(2)));
                    row_end = min(size(enhanced_img, 1), ceil(box(2) + box(4)));
                    col_start = max(1, floor(box(1)));
                    col_end = min(size(enhanced_img, 2), ceil(box(1) + box(3)));
                    
                    score = 0;
                    
                    % ---------------------------------------------------------
                    % 【特徵 A & B & C】幾何與位置
                    % ---------------------------------------------------------
                    if (w >= 70) && (w <= 160)
                        score = score + 40; 
                    elseif (w > 160) && (w <= 300)
                        score = score + 50; 
                    else
                        score = score + 10; 
                    end
                    
                    if (ratio >= 2.4) && (ratio <= 4.0)
                        score = score + 40; 
                    else
                        score = score + 10; 
                    end
                    
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

                    if (edge_density >= 0.15) && (edge_density <= 0.45)
                        score = score + 50; 
                    elseif (edge_density < 0.08)
                        score = score - 40; 
                    else
                        score = score + 20; 
                    end

                    % ---------------------------------------------------------
                    % 【特徵 E】雙極性文字連通元件檢查 (防禦貼紙 + 車輪線性度測試)
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
                    best_mae = 999; 
                    local_h_best = 1;
                    
                    for b = 1:2
                        current_bin = imclearborder(bins_to_test{b});
                        char_stats = regionprops(current_bin, 'Area', 'BoundingBox', 'Centroid');
                        
                        count = 0;
                        local_h = size(current_bin, 1);
                        temp_cx = []; 
                        temp_cy = []; 
                        
                        for k = 1:length(char_stats)
                            char_h = char_stats(k).BoundingBox(4);
                            char_area = char_stats(k).Area;
                            
                            if (char_h > local_h * 0.25) && (char_h < local_h * 0.95) && (char_area > 30)
                                count = count + 1;
                                temp_cx(end+1) = char_stats(k).Centroid(1);
                                temp_cy(end+1) = char_stats(k).Centroid(2);
                            end
                        end
                        
                        current_mae = 999;
                        if count >= 3
                            % 關閉 polyfit 的警告，避免在 Command Window 洗頻
                            warning('off', 'MATLAB:polyfit:RepeatedPointsOrRescale');
                            p = polyfit(temp_cx, temp_cy, 1);
                            warning('on', 'MATLAB:polyfit:RepeatedPointsOrRescale');
                            y_fit = polyval(p, temp_cx);
                            current_mae = mean(abs(temp_cy - y_fit));
                        elseif count > 0
                            current_mae = 0; 
                        end
                        
                        if count > max_valid_char_count
                            max_valid_char_count = count;
                            best_mae = current_mae;
                            local_h_best = local_h;
                        end
                    end
                    
                    if (max_valid_char_count >= 5) && (max_valid_char_count <= 8)
                        score = score + 60;  
                    elseif (max_valid_char_count <= 2)
                        score = score - 80;  
                    else
                        score = score - 20;  
                    end
                    
                    % 車輪防禦機制
                    if max_valid_char_count >= 3 && best_mae > local_h_best * 0.15
                        score = score - 150; 
                    end

                    if score > best_score
                        best_score = score;
                        plate_location = box;
                    end
                end
            end

            %% 5. 影像裁切與安全邊際輸出
            if ~isempty(plate_location) && best_score > 0
                pad = 4;
                img_w = size(img, 2);
                img_h = size(img, 1);
                
                x_min = max(1, plate_location(1) - pad);
                y_min = max(1, plate_location(2) - pad);
                x_max = min(img_w, plate_location(1) + plate_location(3) + pad);
                y_max = min(img_h, plate_location(2) + plate_location(4) + pad);
                
                crop_rect = [x_min, y_min, x_max - x_min, y_max - y_min];
                img_clap = imcrop(img, crop_rect); 
                plate_location = crop_rect;
            else
                img_clap = [];
                warning('警告：在此影像中未偵測到任何符合車牌特徵的區域！');
            end
        end
    end
end