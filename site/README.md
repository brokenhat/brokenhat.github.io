# Pollen Portfolio Site

Static portfolio site built with [Pollen](https://docs.racket-lang.org/pollen/) (Racket). Every page is a small Racket program. Git history becomes a visible process journal for textile pieces.

## Prerequisites

- [Racket](https://racket-lang.org/) v9.3+
- Pollen: `raco pkg install --auto pollen`
- [ImageMagick](https://imagemagick.org/) (`magick` or `convert`) for tile thumbnails. Without it pages still build, using full-size images.

## Project structure

```
site/
  pollen.rkt               root config (setup, decoder, helpers)
  index.ptree               navigation hierarchy
  template.html.p           the one HTML template (layout chosen per page)

  index.html.pm             homepage
  about.html.pm             artist statement
  cv.html.pm                CV

  paintings/index.html.pm   section indexes
  generative/index.html.pm
  drawings/index.html.pm
  highland-series/
    index.html.pm
    rannoch-moor-swings.html.pm
    buachaille-etive-mor.html.pm
    lost-on-criese.html.pm
  textiles/
    index.html.pm
    sofreh-interlace/       piece folder (git-as-journal unit)
      index.html.pm
      images/
    blue-stem/
      index.html.pm
      images/
    untitled-2024/
      index.html.pm
      images/

  lib/
    tags.rkt                all custom tag functions
    tiles.rkt               tile-grid tags
    thumbs.rkt              resized image copies (ImageMagick)
    git-timeline.rkt        reads git log per piece folder

  css/site.css              stylesheet
  css/tiles.css             tile-grid styles
  js/nav.js                 collapses the menu when it doesn't fit
  js/tile-grid.js           tile-grid pan/zoom + viewers
  images/                   shared images
  scripts/migrate.py        content migration from Flask DB
```

## Command character

This project uses `£` as the Pollen command character (instead of the default `◊`).

To write a literal £ sign in content, double it: `££`.

## Available tags

### Page structure

| Tag | Usage |
|-----|-------|
| `£title{Page Title}` | Main page heading |
| `£section-intro{text}` | Intro paragraph block with smart typography |

### Piece pages

```
£piece[#:title "Sofreh Interlace"
       #:year "2023"
       #:technique "mixed media tapestry"
       #:fibre "wool, silk on cotton warp"
       #:medium "watercolour, pigments, paper, wool, silk"
       #:dimensions "100cm x 110cm"
       #:exhibition "RSW 143rd Annual Exhibition"
       #:award "Some Award"
       #:status "finished"]{

Body content here.

}
```

All `#:` keyword arguments are optional.

### Images

| Tag | Usage |
|-----|-------|
| `£gallery{ £fig[...]{} ... }` | Grid of figures |
| `£fig["path.jpg" #:alt "desc"]{caption}` | Figure with lazy-loaded image |
| `£image["path.jpg" #:alt "desc" #:class "hero"]{}` | Standalone image |

### Tile grid pages

A tile page shows your work as squares on a grid you can drag around and zoom, like blog-tile. The site menu stays at the top; the grid fills the rest of the page.

See it working: `example/tiles.html.pm` → http://localhost:8080/example/tiles.html

#### Make a new tile page

1. Create a file, e.g. `textiles/grid.html.pm`, starting with:

   ```
   #lang pollen
   £(define-meta layout "tiles")
   £(define-meta title "Grid")

   £tile-grid{

   }
   ```

2. Put tiles between the `£tile-grid{` and `}` lines (see below).

3. Add the page to `index.ptree` under its section so it shows in the menu:

   ```
   textiles/index.html
     textiles/grid.html
   ```

4. Save and reload the browser.

#### Kinds of tile

**Image** — give it `#:image`:

```
£tile[#:x 0 #:y 0 #:title "Sofreh Interlace" #:image "/images/sofreh.png"]{}
```

**Image with text** — same, with text inside `{ }`. Clicking it shows the text beside the picture (on phones and portrait tablets: picture on top, text below). The ⤢ button or a click on the picture opens it full screen.

```
£tile[#:x 1 #:y 0 #:title "Studio" #:image "/images/studio.jpg"]{
Text shown beside the image.
}
```

**Text** — no image, just text. Blank lines start new paragraphs; links work.

```
£tile[#:x 0 #:y 1 #:title "On the loom"]{
First paragraph.

Second paragraph with a £link["/cv.html"]{link}.
}
```

**Sketchbook** — a list of pages. The first page is the cover.

```
£tile[#:x -1 #:y 0 #:title "Sketchbook 2024"]{
£sketch-page["/images/page1.jpg"]
£sketch-page["/images/page2.jpg"]
£sketch-page["/images/page3.jpg"]
}
```

#### Where a tile goes

`#:x` and `#:y` are the tile's square on the grid. `x` goes right, `y` goes **up**:

```
          y=1
  x=-1   [0,0]   x=1
          y=-1
```

Empty squares next to your tiles are drawn automatically. To move a tile, change its numbers; to remove it, delete its line.

#### Optional settings

| Setting | What it does | Example |
|---------|--------------|---------|
| `#:title` | Name shown on hover and in the viewer | `#:title "Blue Stem"` |
| `#:caption` | Short line under the title | `#:caption "detail"` |
| `#:date` | Small label at the top of the tile | `#:date "2024"` |
| `#:focus` | Which part of the image the square shows | `#:focus "30% 50%"` |
| `#:zoom` | Zoom into the image inside the square | `#:zoom 1.3` |
| `#:bg` | Tile background colour | `#:bg "#eee"` |

#### Using the page

| To… | Mouse / keyboard | Phone |
|-----|------------------|-------|
| Move around | Drag, or arrow keys | Drag |
| Zoom | Scroll wheel, `+` `-`, or the buttons | Pinch |
| See everything | `0` or the ⤢ button | ⤢ button |
| Open a tile | Click, or Enter | Tap |

Images open full screen: scroll or `+` `-` to zoom, `1` for actual size, `0` to fit, drag to look around, `Esc` to close; on a phone pinch to zoom and swipe down to close. Sketchbooks open as a two-page book (arrow keys or swipe to turn pages); click a page to enlarge it.

#### Image sizes

You only ever point tiles at your original images. When the page renders, `lib/thumbs.rkt` makes smaller copies in `thumbs/` (ignored by git, rebuilt by CI):

| Copy | Used for |
|------|----------|
| `thumbs/400f/…`, `thumbs/800f/…` | The square tile (800 on sharp/retina screens) |
| `thumbs/1600/…` | Side-by-side view, full-screen view, sketchbook pages |
| the original | Only when you press `1:1` |

Copies are remade when the original changes. Image paths must start with `/` (e.g. `/images/a.jpg`) to be resized. If you edit files in `lib/`, run `raco pollen reset` so pages re-render.

#### Files

| File | Role |
|------|------|
| `lib/tiles.rkt` | The `£tile-grid`, `£tile`, `£sketch-page` tags |
| `lib/thumbs.rkt` | Makes the resized image copies |
| `template.html.p` | With `layout "tiles"`: full-height grid, loads the tile CSS/JS |
| `css/tiles.css` | Look of tiles and viewers |
| `js/tile-grid.js` | Dragging, zooming, opening tiles |

### Process journal

| Tag | Usage |
|-----|-------|
| `£process-note[#:date "2023-09-15"]{text}` | Timestamped note |
| `£git-timeline["textiles/sofreh-interlace"]` | Auto-generated timeline from git commits |

### CV

| Tag | Usage |
|-----|-------|
| `£cv-section["Education"]{entries}` | CV section with heading |
| `£cv-entry[#:year "2023"]{description}` | Year + description row |
| `£exhibition["Show" #:year "2024" #:venue "RSA"]` | Exhibition entry |
| `£award["Award Name" #:year "2023"]` | Award entry |

### Typography

| Tag | Usage |
|-----|-------|
| `£lede{text}` | Lead paragraph |
| `£aside{text}` | Side note |
| `£smallcaps{text}` | Small caps span |
| `£blockquote{text}` | Block quote |
| `£link["url"]{text}` | Internal link |
| `£ext-link["url"]{text}` | External link (opens in new tab) |

## Adding content

### New section

1. Create `newsection/index.html.pm`:
   ```
   #lang pollen
   £(define-meta title "New Section")

   £title{New Section}

   £section-intro{Description here.}
   ```
2. Add to `index.ptree`:
   ```
   newsection/index.html
   ```

### New piece (subpage)

1. Create the `.pm` file (or folder with `index.html.pm` for pieces with process images)
2. Add to `index.ptree` indented under its parent section

### New textile piece with git-as-journal

```bash
mkdir -p site/textiles/new-piece/images
# Write site/textiles/new-piece/index.html.pm with £piece tag
# Add to index.ptree indented under textiles/index.html
cp ~/photo.jpg site/textiles/new-piece/images/01-concept.jpg
git add site/textiles/new-piece/ && git commit -m "sketch: initial concept for new-piece"
```

### Sub-subpages

Nest deeper in `index.ptree`:
```
textiles/index.html
  textiles/sofreh-interlace/index.html
    textiles/sofreh-interlace/studies.html
```

## Commit conventions for process journal

Each commit to a piece folder becomes a timeline entry on the published site.

| Prefix | Meaning |
|--------|---------|
| `sketch:` | Initial concept or sketch |
| `swatch:` | Colour/material sample |
| `warp:` | Warping the loom |
| `weave:` | Weaving progress |
| `note:` | Written reflection |
| `photo:` | Process photograph |
| `finish:` | Completion or finishing step |

Example: `git commit -m "warp: cotton warp set up, 12 epi"`

## Building locally

Development server (live reload):
```bash
cd site
raco pollen start
# → http://localhost:8080
```

Static render:
```bash
cd site
raco pollen render -r .
```

## Publishing

Push to `main` branch. GitHub Actions will:
1. Check out the full git history (for `£git-timeline`)
2. Install Racket + Pollen
3. Render all pages
4. Deploy to GitHub Pages

The site is live at https://brokenhat.github.io/ (repository `brokenhat/brokenhat.github.io`).

## Page layouts

Every page uses `template.html.p`. Pick a layout near the top of the page:

```
£(define-meta layout "piece")   ← a single work (adds class content--piece)
£(define-meta layout "tiles")   ← a tile grid page (full-height grid + tile scripts)
```

Without a `layout` line the page is a plain page. This works the same at any folder depth.
