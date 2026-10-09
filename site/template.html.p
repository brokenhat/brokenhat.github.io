<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>£(or (select-from-metas 'title here) "Dominik Zarzycki")</title>
  <link rel="stylesheet" href="/css/site.css">
</head>
<body>
  <header>
    <nav class="site-nav">
      <a class="site-name" href="/">Dominik Zarzycki</a>
      <ul>
        £(apply string-append (map ->html (site-nav-items)))
      </ul>
    </nav>
  </header>

  <main>
    £(let ([bc (breadcrumb here)]) (if (string? bc) bc (->html bc)))
    £(apply string-append (map ->html (cdr doc)))
  </main>

  <footer>
    <p>£(copyright-year) Dominik Zarzycki</p>
  </footer>
  <script src="/js/viewer.js" defer></script>
</body>
</html>
