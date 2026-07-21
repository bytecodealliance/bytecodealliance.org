---
layout: article
---

<ul id="articles-index">
  {% for post in site.posts %}
    <li>
      {%- comment -%} jekyll-avatar is broken for org accounts, so we can't use it {%- endcomment -%}
      <img class="avatar" alt="{{ post.github_name }}" width="75" height="75" data-proofer-ignore="true"
           src="https://github.com/{{ post.github_name }}.png?size=75"
           srcset="https://github.com/{{ post.github_name }}.png?size=150 2x,
                   https://github.com/{{ post.github_name }}.png?size=225 3x">

      <div>
        <h2><a href="{{ site.baseurl }}{{ post.url }}">{{ post.title }}</a></h2>
        {{ post.excerpt }}
        {%- assign date_format = site.minima.date_format | default: "%b %-d, %Y" -%}
        <aside>Posted on {{ post.date | date: date_format }}</aside>
      </div>
    </li>
  {% endfor %}
</ul>
