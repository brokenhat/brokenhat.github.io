#lang pollen
£(define-meta template "../template-tiles.html.p")
£(define-meta title "Tiles")

£tile-grid{
£tile[#:x 0 #:y 0 #:title "Sofreh Interlace" #:image "/images/Sofreh_Interlaceresi.png"
      #:caption "mixed media tapestry" #:date "2023"]{}

£tile[#:x 1 #:y 0 #:title "Studio" #:image "/images/DSC_0793.JPG" #:focus "30% 50%"
      #:caption "work table"]{
Image tiles with text open side by side with it. Click the picture there for the full-screen view.
}

£tile[#:x 0 #:y 1 #:title "On the loom" #:date "2024-03"]{
Notes on a work in progress. Warp is cotton, the weft a mix of wool and silk offcuts from the previous piece.

Text tiles show a clipped preview; click to read the rest. Paragraphs, £link["/textiles/index.html"]{links} and other inline tags work here.
}

£tile[#:x -1 #:y 0 #:title "Untitled 2024" #:date "2024"]{
£sketch-page["/textiles/untitled-2024/images/PXL_20240219_1758503232.jpg"]
£sketch-page["/textiles/untitled-2024/images/PXL_20240227_184821884.MP.jpg"]
£sketch-page["/textiles/untitled-2024/images/PXL_20240228_150243480.jpg"]
£sketch-page["/textiles/untitled-2024/images/PXL_20240313_1025208852.jpg"]
£sketch-page["/textiles/untitled-2024/images/PXL_20240315_125448530.jpg"]
}

£tile[#:x 2 #:y -1 #:title "Blue Stem" #:image "/textiles/blue-stem/images/PXL_20240219_175905460.jpg"
      #:caption "detail"]{}
}
