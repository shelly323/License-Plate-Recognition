classdef Segmenter
    properties
        % 這裡放「參數」，代表這個類別知道的狀態與過濾條件
        % 將原本寫死的數值變成屬性，方便外部動態調整
        NoiseAreaThreshold = 140; % bwareaopen 去除雜訊的門檻值
        MinCharArea = 100;        % 字元最小面積
        MaxCharArea = 5000;       % 字元最大面積
        MinAspectRatio = 1.2;     % 字元最小長寬比 (高/寬)
        MaxAspectRatio = 4.0;     % 字元最大長寬比 (高/寬)
    end
    
    methods
        % 類別的建構子 (Constructor)
        function obj = Segmenter()
            % 建立物件時執行，目前使用預設屬性即可
        end
        
        % 核心切割功能
        function final_bboxes = segment(obj, clap, location)
            % 輸入:
            %   clap: PlateLocalizer 切割下來的車牌影像 (RGB 或灰階皆可)
            %   location: 車牌在原始大圖上的座標 [x_min, y_min, width, height]
            % 輸出:
            %   final_bboxes: 所有有效字元在「原圖」上的座標 [x, y, w, h]，N x 4 二維陣列
            
            % 1. 確保影像為灰階
            if size(clap, 3) == 3
                gray_img = rgb2gray(clap);
            else
                gray_img = clap;
            end
            % figure, imshow(gray_img); % 顯示灰階圖，方便調整參數

            % 2. 二值化 (Otsu's method) 並反轉成白字黑底
            % level = graythresh(gray_img);
            % bw = imbinarize(gray_img, level);

            % 2. 二值化（adaptive method）
            bw = imbinarize(gray_img, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.5);
            bw = ~bw; 
            figure, imshow(bw); % 顯示二值化結果，方便調整參數

            % bw = imopen(bw, strel('rectangle', [3, 3])); % 開運算去除小毛邊
            % figure, imshow(bw); % 顯示開運算結果，方便調
            % 假設你的原始二值化圖存在變數 bw 中

            % 3. 消除細小雜訊
            % bw = bwareaopen(bw, obj.NoiseAreaThreshold);
            figure, imshow(bw); % 顯示去除雜訊後的結果，方便調整 NoiseAreaThreshold

            % 假設你已經做完基礎的去雜訊： bw = bwareaopen(bw, obj.NoiseAreaThreshold);

            % 1. 先做一次初步的連通物件分析
            cc_temp = bwconncomp(bw);
            stats_temp = regionprops(cc_temp, 'BoundingBox');

            % 2. 巡視所有初步找到的框
            for i = 1:length(stats_temp)
                bbox = stats_temp(i).BoundingBox;
                x_start = round(bbox(1));
                y_start = round(bbox(2));
                w = round(bbox(3));
                h = round(bbox(4));
                
                % --- 智能判斷：這個框是不是太胖了？ ---
                % 正常字元 w < h。如果 w > h * 0.85，極高機率是沾黏！
                if w > h * 0.85
                    % fprintf('發現一個可能沾黏的框: [x=%d, y=%d, w=%d, h=%d]\n', x_start, y_start, w, h);
                    % 把它單獨抓出來 (局部 ROI)
                    roi = bw(y_start : y_start+h-1, x_start : x_start+w-1);
                    
                    % 計算這個框內的垂直投影 (由上往下加總白點)
                    v_proj = sum(roi, 1);
                    
                    % 尋找「最少白點」的直行 (也就是沾黏最薄弱的地方)
                    % 為了避免切到字元的左右邊緣，我們只在框的「中間 60%」區域尋找斷點
                    search_start = max(1, round(w * 0.2));
                    search_end = min(w, round(w * 0.8));
                    
                    [~, min_idx] = min(v_proj(search_start : search_end));
                    
                    % 計算出斷點在原始影像上的 X 座標
                    cut_x_local = search_start + min_idx - 1;
                    global_cut_x = x_start + cut_x_local - 1;
                    
                    % --- 執行外科手術切割 ---
                    % 在原始二值化圖上，沿著這個斷點畫一條粗度為 2~3 像素的「黑色垂直線」
                    % 這樣就能強制把黏在一起的字元一分為二！
                    cut_thickness = 1; % 往左往右擴張的像素，總寬 3 像素
                    safe_left = max(1, global_cut_x - cut_thickness);
                    safe_right = min(size(bw, 2), global_cut_x + cut_thickness);
                    
                    bw(y_start : y_start+h-1, safe_left : safe_right) = 0; 
                end
            end

            % 4. 取得連通物件特徵
            cc = bwconncomp(bw);
            stats = regionprops(cc, 'BoundingBox', 'Area');
            
            % valid_bboxes = []; 

            %  % 5. 迴圈過濾特徵
            % for i = 1:length(stats)
            %     bbox = stats(i).BoundingBox; % 局部座標 [x_local, y_local, width, height]
            %     area = stats(i).Area;
                
            %     w = bbox(3);
            %     h = bbox(4);
            %     aspect_ratio = h / w;
                
            %     % 利用物件自身的 properties 進行條件判斷
            %     if (area > obj.MinCharArea) && (area < obj.MaxCharArea) && ...
            %        (aspect_ratio > obj.MinAspectRatio) && (aspect_ratio < obj.MaxAspectRatio)
                    
            %         % --- 關鍵步驟：座標回推至原圖 ---
            %         % bbox(1) 與 bbox(2) 是在 clap 上的局部 x, y
            %         % location(1) 與 location(2) 是 clap 在原圖上的 x, y
            %         % 兩者相加並減 1 (因為 MATLAB 座標從 1 開始) 即可還原回絕對座標
            %         global_x = bbox(1) + location(1) - 1;
            %         global_y = bbox(2) + location(2) - 1;
                    
            %         global_bbox = [global_x, global_y, w, h];
            %         valid_bboxes = [valid_bboxes; global_bbox];
            %     end
            
            % ------------------新方法--------------------
            img_height = size(bw, 1);

            % 收集所有物件的高度
            all_heights = zeros(length(stats), 1);
            for i = 1:length(stats)
                all_heights(i) = stats(i).BoundingBox(4);
            end

            % 排除極端值（極小的雜訊或極大的邊框），找出「中位數高度」
            median_height = median(all_heights(all_heights > img_height * 0.1));

            valid_bboxes = []; 
            
            % 5. 迴圈過濾特徵
            for i = 1:length(stats)
                bbox = stats(i).BoundingBox; % 局部座標 [x_local, y_local, width, height]
                area = stats(i).Area;
                
                w = bbox(3);
                h = bbox(4);
                aspect_ratio = h / w;
                
                % --- 相對特徵篩選條件 ---
                % 1. 高度必須與「中位數高度」相近 (例如誤差在正負 20% 以內)
                is_similar_height = (h > median_height * 0.8) && (h < median_height * 1.2);
                
                % 2. 長寬比落在合理範圍 (這依然可以使用，因為比例是相對的，不受解析度影響)
                % is_valid_ratio = (aspect_ratio > 1.2) && (aspect_ratio < 4.0);
                is_valid_ratio = (aspect_ratio > 1.2);
                
                if is_similar_height 
                    if is_valid_ratio
                    global_x = bbox(1) + location(1) - 1;
                    global_y = bbox(2) + location(2) - 1;
                    
                    global_bbox = [global_x, global_y, w, h];
                    valid_bboxes = [valid_bboxes; global_bbox];
                    else
                        % fprintf('過濾掉一個物件: 高度=%.2f, 長寬比=%.2f\n', h, aspect_ratio);
                    end
                else
                    % fprintf('過濾掉一個物件: 高度=%.2f, 長寬比=%.2f\n', h, aspect_ratio);
                end
                % -------------------------------------------

                % 利用物件自身的 properties 進行條件判斷
                % if (area > obj.MinCharArea) && (area < obj.MaxCharArea) && ...
                %    (aspect_ratio > obj.MinAspectRatio) && (aspect_ratio < obj.MaxAspectRatio)
                    
                %     % --- 關鍵步驟：座標回推至原圖 ---
                %     % bbox(1) 與 bbox(2) 是在 clap 上的局部 x, y
                %     % location(1) 與 location(2) 是 clap 在原圖上的 x, y
                %     % 兩者相加並減 1 (因為 MATLAB 座標從 1 開始) 即可還原回絕對座標
                %     global_x = bbox(1) + location(1) - 1;
                %     global_y = bbox(2) + location(2) - 1;
                    
                %     global_bbox = [global_x, global_y, w, h];
                %     valid_bboxes = [valid_bboxes; global_bbox];
                % end

                % 可以用來檢驗他抓到哪些物件，以及為什麼被過濾掉了
                for j = 1:size(bbox, 1)
                    rectangle('Position', bbox(j, :), 'EdgeColor', 'r', 'LineWidth', 2);
                    % 在框的上方標示字元順序編號
                    % text(char_bboxes(i, 1), char_bboxes(i, 2)-10, num2str(i), 'Color', 'r', 'FontSize', 12);
                end 

                % if (area > obj.MinCharArea) && (area < obj.MaxCharArea) 
                %    if (aspect_ratio > obj.MinAspectRatio) && (aspect_ratio < obj.MaxAspectRatio)
                %         % --- 關鍵步驟：座標回推至原圖 ---
                %         % bbox(1) 與 bbox(2) 是在 clap 上的局部 x, y
                %         % location(1) 與 location(2) 是 clap 在原圖上的 x, y
                %         % 兩者相加並減 1 (因為 MATLAB 座標從 1 開始) 即可還原回絕對座標
                %         global_x = bbox(1) + location(1) - 1;
                %         global_y = bbox(2) + location(2) - 1;
                    
                %         global_bbox = [global_x, global_y, w, h];
                %         valid_bboxes = [valid_bboxes; global_bbox];
                %    else
                %         fprintf('過濾掉一個物件: 面積=%.2f, 長寬比=%.2f\n', area, aspect_ratio);
                %    end
                % else
                %     fprintf('過濾掉一個物件: 面積=%.2f, 長寬比=%.2f\n', area, aspect_ratio);
                % end
            end 
            
            % 6. 由左至右排序並格式化
            if ~isempty(valid_bboxes)
                % 根據 x 座標 (第一欄) 進行排序，確保字元順序正確
                sorted_bboxes = sortrows(valid_bboxes, 1);
                % 像素座標必須為整數
                final_bboxes = sorted_bboxes;
            else
                final_bboxes = []; % 沒找到東西時回傳空陣列防呆
            end
            
            
            % ==================================================
            % 新增的程式碼：直接在 class 內部畫出局部圖 (clap) 的框
            % ==================================================
            % if ~isempty(final_bboxes)
            %     figure('Name', 'Segmenter 內部檢視');
            %     imshow(clap); % 直接使用傳進來的局部影像
            %     title('Segmenter 內部切割結果 (局部座標)');
            %     hold on;
                
            %     for i = 1:size(final_bboxes, 1)
            %         % 因為 final_bboxes 已經是原圖座標，要畫在 clap 上必須減回去
            %         loc_x = final_bboxes(i, 1) - location(1) + 1;
            %         loc_y = final_bboxes(i, 2) - location(2) + 1;
            %         loc_w = final_bboxes(i, 3);
            %         loc_h = final_bboxes(i, 4);
                    
            %         % 畫上綠色的 Bounding Box 與字元順序編號
            %         rectangle('Position', [loc_x, loc_y, loc_w, loc_h], 'EdgeColor', 'g', 'LineWidth', 2);
            %         text(loc_x, loc_y - 8, num2str(i), 'Color', 'g', 'FontSize', 12, 'FontWeight', 'bold');
            %     end
            %     hold off;
            % end
            % ==================================================
            
        end
    end
end