plateDetector = PlateLocalizer();  %初始化
% plateSegmenter = Segmenter();     % 還沒寫!!!!!

file_path =  '.\image\sample 2026\';% 資料夾路徑
img_path_list = dir(strcat(file_path,'*.jpg')); % jpg影像
img_num = length(img_path_list); %照片數量

if img_num > 0 
        for j = 1:img_num 
            image_name = img_path_list(j).name;
            car_image =  imread(strcat(file_path,image_name)); %strcat:將多個字串合併
            fprintf('正在處理 [%d/%d]: %s\n',j,strcat(file_path,image_name)); 
            
            %車牌偵測!!!!!!!!!!!!!!!
            [clap, location] = plateDetector.localizer(car_image);


            fid = fopen('411285036.txt', 'wt');
            % fprint(fid, image_name,'\n',) %不用.jpg   等施!!!!!!!!!!!!!!!
            fclose(fid); 
        end
else
    fprintf('在 %s 找不到任何 .jpg 檔案。\n', file_path);
end


