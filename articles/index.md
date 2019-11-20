---
layout: article
---

<ul id="articles-index">
  {% for post in site.posts %}
    <li>
      {% avatar user=post.github_name size=75 %}
      <div>
        <h2><a href="{{ post.url }}">{{ post.title }}</a></h2>
        {{ post.excerpt }}
        {%- assign date_format = site.minima.date_format | default: "%b %-d, %Y" -%}
        <aside>Posted on {{ post.date | date: date_format }}</aside>
      </div>
    </li>
  {% endfor %}
</ul>