plateDetector = PlateLocalizer();  %初始化
plateSegmenter = Segmenter(); 

file_path =  '.\1\';% 資料夾路徑
img_path_list = dir(strcat(file_path,'*.jpg')); % jpg影像
img_num = length(img_path_list); %照片數量

if img_num > 0 
    txt_filename = '411285036.txt';
    fid = fopen(txt_filename, 'wt');
    for j = 1:img_num 
        image_name = img_path_list(j).name;
        car_image =  imread(strcat(file_path,image_name)); %strcat:將多個字串合併
        fprintf('正在處理 [%d/%d]: %s\n',j,strcat(file_path,image_name)); 
            
        %車牌偵測!!!!!!!!!!!!!!!
        [clap, location] = plateDetector.localizer(car_image, false);
        bboxes = plateSegmenter.segment(clap, location, false);   %等施!!!!!!!!!!!!!!!

        % 3. 計算這張圖片真正找到了幾個字元!!!!!!!!!!
        % size(bboxes, 1) 會回傳矩陣有幾列（也就是幾個字元框）
        char_num = size(bboxes, 1);

%% 3. 寫入資料到 TXT 檔案
        % 【修正 2】去掉檔名尾巴的 .jpg，只保留主檔名 (如 001.jpg -> 001)
        pure_image_name = strrep(image_name, '.jpg', '');
        fprintf(fid, '%s\n', pure_image_name);
        fprintf(fid, '%d\n', char_num); % 寫入偵測到的字元數量;  等施!!!!!!!!!!!!!!!
        for k = 1:char_num
            % 依序將整數座標以「x y width height」格式寫入，數值間空格，結尾換行
            % 使用 round 確保座標小數點被捨入為整數
            fprintf(fid, '%d %d %d %d\n', round(bboxes(k,1)), round(bboxes(k,2)), round(bboxes(k,3)), round(bboxes(k,4)));
        end
       
        % for k = 1:char_num
        %     % bboxes(k,1)是x, (k,2)是y, (k,3)是width, (k,4)是height
        %     fprintf(fid, '%d %d %d %d\n', bboxes(k,1), bboxes(k,2), bboxes(k,3), bboxes(k,4));  %等施!!!!!!!!!!!!!!!
        % end 
    end
    fclose(fid); 
    fprintf('====== 檔案輸出成功！已生成 %s ======\n', txt_filename);
else
    fprintf('在 %s 找不到任何 .jpg 檔案。\n', file_path);
end


