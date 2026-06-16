p = PlateLocalizer();

[clap, location] = p.localizer(imread("1\370.jpg"), true);

figure, imshow(clap)