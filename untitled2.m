p = PlateLocalizer();

[clap, location] = p.localizer(imread("image\sample 2026\020.jpg"));

figure, imshow(clap)