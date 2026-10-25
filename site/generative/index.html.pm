#lang pollen
£(define-meta title "Generative")
£(define-meta seo-title "Generative Art in Clojure & Quil — Dominik Zarzycki")
£(define-meta description "Generative art by Dominik Zarzycki, made with Clojure and the Quil library: algorithmic drawings, noise fields and an animation.")

£title{Generative}

£section-intro{
It is very different form of creating things. Usually the artist deals with the physical or virtual matter itself, should have almost total control over the piece. In the contrary, generative art puts rules and algorithms (recipes) in the first place. Here I have to define definitions for future outcome, in that sense it is possible to create artificial environments (usually very simplistic one) in which I can pull a slice of it from and make it visible. In that way at moments I can generate several slices all different to each other but similar in the light of the recipe. Below You will find a couple of them.

From the technical perspective these are made using Clojure functional language and its Quil library (which is based on Processing). Have a look at the essays of Tyler Hobbs — £ext-link["https://tylerxhobbs.com"]{tylerxhobbs.com} — to have better understanding of what is going on here. Also recommend looking at the possibilities of generative art here (from Jared Tarbell — £ext-link["http://complexification.net/gallery/"]{complexification.net/gallery}).
}

£gallery{
£fig["/generative/images/noise3.png" #:alt "Generative artwork: noise-distorted bands from purple to red"]{}
£fig["/generative/images/travelers-9978.png" #:alt "Generative artwork: olive and yellow faceted polygons traced by moving points"]{}
£fig["/generative/images/Screenshot_2023-03-08_22-21-19.png" #:alt "Generative artwork: a pale blue web of star-shaped lines"]{£ext-link["https://youtu.be/gCM0JKgifyU"]{Have a look at this animation}}
£fig["/generative/images/travelers-1785.png" #:alt "Generative artwork: an orange ring of traced lines"]{}
£fig["/generative/images/resized-slajd7.png" #:alt "Generative studies of a pixelated profile in pink, blue and grey"]{}
£fig["/generative/images/noise9.png" #:alt "Generative artwork: a dark noise field with glowing green and white streaks"]{}
}
