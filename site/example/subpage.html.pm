#lang pollen
£(define-meta layout "piece")
£(define-meta title "Example Subpage")
£(define-meta noindex "yes")

£piece[#:title "Example Subpage"
       #:year "2024"
       #:technique "mixed media"
       #:medium "oil, acrylic, found objects"
       #:dimensions "120cm x 80cm"
       #:status "in-progress"]{

£image["/images/DSC_0793.JPG" #:alt "Example piece" #:class "hero"]{}

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae. Nulla facilisi. Sed euismod, nisl eget ultricies tincidunt, nisl nisl aliquam nisl, eget aliquam nisl nisl sit amet nisl.

Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.

£process-note[#:date "2024-03-15"]{Started with initial sketches exploring the relationship between woven texture and painted surface. The warp threads suggest a rhythm that the brush strokes try to follow.}

£process-note[#:date "2024-04-02"]{Second pass — introduced found objects from the studio floor. The piece is starting to assert its own logic.}

£youtube["dQw4w9WgXcQ"]

£gallery{
£fig["/generative/images/noise2.png"]{Detail of surface texture — note the interplay of warp and pigment}
£fig["/generative/images/noise3.png"]{Side view showing dimensional quality of the mixed media layers}
£fig["/paintings/images/banana.jpg"]{Studio view during the second working session}
}

}
