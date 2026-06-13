p = PlateLocalizer();

[clap, location] = p.localizer(imread("image\sample 2026\001.jpg"));

figure, imshow(clap);