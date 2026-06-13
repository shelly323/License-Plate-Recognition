p = PlateLocalizer();
[clap, location] = p.localizer(imread("image/sample 2026/002.jpg"));
figure, imshow(clap);