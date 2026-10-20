#lang racket/base
(require txexpr)

;; Woven Automata page: the controls, viewer and panels around the
;; Prolog generator. js/woven-automata.js runs woven_automata.pl in the
;; browser (js/woven-worker.js) and fills these in.

(provide woven-automata-app)

(define modes
  '(("random" "Random design")
    ("good" "Search + evolve")
    ("crystalline" "Crystalline (geometric)")
    ("life" "Life (emergent)")
    ("uniform" "Uniform rule + automaton")))

(define (field label name min max value hint)
  `(label [[class "wa-field"]]
          (span [[class "wa-label"]] ,label)
          (input [[type "number"] [name ,name] [min ,min] [max ,max] [step "1"]
                  [value ,value] [inputmode "numeric"] [required ""]])
          ,@(if hint (list `(span [[class "wa-hint"]] ,hint)) '())))

(define (woven-automata-app)
  `(div [[class "wa"] [data-decoded "true"]]
        (form [[class "wa-controls"] [aria-label "Design settings"]]
              (label [[class "wa-field"]]
                     (span [[class "wa-label"]] "Kind of design")
                     (select [[name "mode"]]
                             ,@(for/list ([m (in-list modes)])
                                 `(option [[value ,(car m)]] ,(cadr m))))
                     (span [[class "wa-hint"] [data-mode-hint ""]]))
              ,(field "Warp threads" "width" "20" "200" "80" #f)
              ,(field "Picks (rows)" "picks" "20" "1000" "500" #f)
              ,(field "Starting bobbins" "bobbins" "3" "20" "8" "Varies ±3 per design.")
              ,(field "Most bobbins" "max" "3" "40" "20" "Including ones born while weaving.")
              (label [[class "wa-field"]]
                     (span [[class "wa-label"]] "Borders between bobbins")
                     (select [[name "border"]]
                             (option [[value "slit"]] "Slit (gap left bare)")
                             (option [[value "interlock"]] "Interlock (shared thread)")))
              (div [[class "wa-field"]]
                   (label [[for "wa-seed"] [class "wa-label"]] "Seed")
                   (div [[class "wa-seed"]]
                        (input [[id "wa-seed"] [type "number"] [name "seed"] [min "1"] [max "999999"]
                                [step "1"] [value "1"] [inputmode "numeric"] [required ""]])
                        (button [[type "button"] [class "wa-button"] [data-act "seed"]] "New seed"))
                   (span [[class "wa-hint"]] "Same settings + seed = same design."))
              (div [[class "wa-actions"]]
                   (button [[type "submit"] [class "wa-button wa-button--primary"]] "Generate")
                   (button [[type "button"] [class "wa-button"] [data-act "cancel"] [hidden ""]] "Cancel"))
              (p [[class "wa-status"] [role "status"] [aria-live "polite"]]
                 "This page runs a Prolog program and needs JavaScript.")
              (button [[type "button"] [class "wa-button wa-download"] [data-act "pdf"] [disabled ""]]
                      "Download PDF"))
        (section [[class "wa-viewer"] [aria-label "Design"]]
                 (div [[class "wa-toolbar"]]
                      (div [[class "wa-picknav"]]
                           (button [[type "button"] [class "wa-button"] [data-act "prev"]
                                    [aria-label "Previous pick (down)"]] "↓")
                           (span [[class "wa-pickno"]] "Pick –")
                           (button [[type "button"] [class "wa-button"] [data-act "next"]
                                    [aria-label "Next pick (up)"]] "↑"))
                      (input [[type "range"] [class "wa-slider"] [min "1"] [max "1"] [value "1"]
                              [aria-label "Pick to follow"]])
                      (div [[class "wa-zoom"]]
                           (button [[type "button"] [class "wa-button"] [data-act "zoom-out"]
                                    [aria-label "Zoom out"]] "−")
                           (button [[type "button"] [class "wa-button"] [data-act "zoom-fit"]
                                    [aria-label "Fit width"]] "Fit")
                           (button [[type "button"] [class "wa-button"] [data-act "zoom-in"]
                                    [aria-label "Zoom in"]] "+"))
                      (label [[class "wa-check"]]
                             (input [[type "checkbox"] [name "shade"] [checked ""]])
                             "Shade woven picks"))
                 ;; the canvas draws only what's in view; the transparent
                 ;; scroller on top provides scrolling, clicks and keys
                 (div [[class "wa-stage"]]
                      (canvas [[class "wa-canvas"] [aria-hidden "true"]])
                      (div [[class "wa-scroller"] [tabindex "0"] [role "application"]
                            [aria-label "Woven design. Click a row, or use the up and down arrow keys, to choose the pick to follow."]]
                           (div [[class "wa-spacer"]])))
                 (p [[class "wa-hover"] [aria-hidden "true"]] " ")
                 (ul [[class "wa-legend"]]
                     (li (span [[class "wa-swatch"] [data-v "1"]]) "black, full")
                     (li (span [[class "wa-swatch"] [data-v "3"]]) "black, half")
                     (li (span [[class "wa-swatch"] [data-v "2"]]) "white, full")
                     (li (span [[class "wa-swatch"] [data-v "4"]]) "white, half")
                     (li (span [[class "wa-swatch"] [data-v "0"]]) "bare warp")))
        (section [[class "wa-pick"] [aria-label "Pick to follow"]]
                 (h2 [[class "wa-pick-title"]] "Pick")
                 (p [[class "wa-pick-sub"]] "")
                 (ol [[class "wa-steps"]]))
        (details [[class "wa-rules"]]
                 (summary "Bobbins, rules and the procedure for every pick")
                 (pre [[class "wa-rules-text"]]))))
