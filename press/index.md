---
layout: article
---

<ul id="articles-index">
  {% assign press_releases = site.press_releases | sort: 'date' | reverse %}
  {% for press_release in press_releases %}
    <li>
      <div>
        <h2><a href="{{ site.baseurl }}{{ press_release.url }}">{{ press_release.title }}</a></h2>
        {{ press_release.excerpt }}
      </div>
    </li>
  {% endfor %}
</ul>