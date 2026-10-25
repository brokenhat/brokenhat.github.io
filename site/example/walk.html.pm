#lang pollen
£(define-meta layout "tiles")
£(define-meta title "Highland walk")
£(define-meta noindex "yes")

£; A route through the Highland Series, made with arrows. Map (x right, y up):
£;
£;   y=3              [Buachaille] [details]
£;   y=2   [End]    ◀ (jump back, #:to "0 2")
£;   y=1    ▼                    ▲  (skips the empty square above)
£;   y=0  [Start] ▶ [Criese]    [Rannoch details]
£;   y=-1             ▼          ▲
£;   y=-2           [Criese details] ▶ [Rannoch]
£;
£; Start → Lost on Criese → its details → When Rannoch Moor Swings → its
£; details → Buachaille Etive Mòr → End → back to Start. "Buachaille,
£; details" is off the route: reachable by clicking, not by the path.

£tile-grid{
£tile[#:x 0 #:y 0 #:title "Highland walk" #:date "start"]{
A walk through the Highland Series: three watercolours and their details.

Follow the arrows. Click an arrow to go where it points, or press the arrow keys. Inside any picture or text, use ← and → at the top to keep walking without closing it.
}

£arrow[#:x 1 #:y 0 #:dir "right"]

£tile[#:x 2 #:y 0 #:title "Lost on Criese" #:image "/example/images/highland/lost_on_criese.jpg"
      #:caption "watercolour on paper"]{
Watercolour on paper, h:132 w:115.
}

£arrow[#:x 2 #:y -1 #:dir "down"]

£tile[#:x 2 #:y -2 #:title "Lost on Criese, details"]{
£sketch-page["/example/images/highland/det1.JPG" #:alt "Lost on Criese, detail"]
£sketch-page["/example/images/highland/det2.jpg" #:alt "Lost on Criese, detail"]
}

£arrow[#:x 3 #:y -2 #:dir "right"]

£tile[#:x 4 #:y -2 #:title "When Rannoch Moor Swings" #:image "/example/images/highland/rannoch.jpg"
      #:caption "Alexander Graham Munro Travel Award 2023" #:date "2023"]{
Watercolour on fabriano paper, h:114 w:141.

Winner of the Alexander Graham Munro Travel Award 2023. Exhibited at the RSW 142nd Annual Exhibition, Royal Scottish Academy, Edinburgh.
}

£arrow[#:x 4 #:y -1 #:dir "up"]

£tile[#:x 4 #:y 0 #:title "When Rannoch Moor Swings, details"]{
£sketch-page["/example/images/highland/detail-rannoch1-small.JPG" #:alt "When Rannoch Moor Swings, detail"]
£sketch-page["/example/images/highland/detail_rannoch2-small.JPG" #:alt "When Rannoch Moor Swings, detail"]
}

£; no #:to: leads to the first tile upwards, past the empty square at 4, 2
£arrow[#:x 4 #:y 1 #:dir "up"]

£tile[#:x 4 #:y 3 #:title "Buachaille Etive Mòr" #:image "/example/images/highland/buchaille.jpg"
      #:caption "watercolour on fabriano paper"]{
Watercolour on fabriano paper, h:115 w:130.
}

£; off the route: beside Buachaille, but no arrow leads here
£tile[#:x 5 #:y 3 #:title "Buachaille, details"]{
£sketch-page["/example/images/highland/buchie-general-res.JPG" #:alt "Buachaille Etive Mòr, detail"]
£sketch-page["/example/images/highland/det1.JPG" #:alt "Buachaille Etive Mòr, detail"]
}

£; a jump across the grid; the direction (left) comes from #:to
£arrow[#:x 3 #:y 3 #:to "0 2"]

£tile[#:x 0 #:y 2 #:title "End of the walk" #:date "end"]{
That was the Highland Series. The arrow below leads back to the start.
}

£arrow[#:x 0 #:y 1 #:dir "down"]
}
