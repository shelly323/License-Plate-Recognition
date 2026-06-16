p = PlateLocalizer();

[clap, location] = p.localizer(imread("10\001.jpg"), true);

figure, imshow(clap)