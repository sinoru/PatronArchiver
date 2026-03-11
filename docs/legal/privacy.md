---
permalink: /legal/privacy
layout: none
---
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Privacy Policy - PatronArchiver</title>
  <script>
    (function() {
      var lang = (navigator.language || navigator.userLanguage || 'en').toLowerCase();
      var base = '{{ site.baseurl }}';
      if (lang.indexOf('ko') === 0) {
        window.location.replace(base + '/ko/legal/privacy');
      } else {
        window.location.replace(base + '/en/legal/privacy');
      }
    })();
  </script>
</head>
<body>
  <noscript>
    <h1>Privacy Policy - PatronArchiver</h1>
    <p>Please select your language:</p>
    <ul>
      <li><a href="{{ site.baseurl }}/en/legal/privacy">English</a></li>
      <li><a href="{{ site.baseurl }}/ko/legal/privacy">한국어</a></li>
    </ul>
  </noscript>
</body>
</html>
