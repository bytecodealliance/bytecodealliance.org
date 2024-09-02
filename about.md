---
layout: default
permalink: /about
---

<section>
    <div class="container w-container">
        <div class="width-container" markdown="1">

## [Mission](#mission)
Our mission is to Provide state-of-the-art foundations to develop runtime environments and language toolchains where security, efficiency, and modularity can all coexist across a wide range of devices and architectures. We enable innovation in compilers, runtimes, and tooling, focusing on fine-grained sandboxing, capabilities-based security, modularity, and standards such as WebAssembly and WASI.
</div>
</div>
</section>

<section>
   <div class="container w-container">
      <div class="width-container">
         <h2>Board</h2>
         <p>
         Our Board is comprised of Directors elected from among our member organizations, the Technical Steering Committee, and our Recognized Contributors program. Board members are selected to a two-year term, staggered across elections every December. 
         </p>
         <div class="board-gallery">
            {% comment %}Generate gallery of Board members from list in _data/board.yml{% endcomment %}
            {% for member in site.data.board %}
            <div class="board-member">
               <img src="https://github.com/{{member.github}}.png">
               <div>
                  <h4>{{member.name}}</h4>
                  {{member.title}}<br>
                  {% if member.office %}
                     {{member.office }}<br>
                  {% endif %}
                  GitHub: <a href="https://github.com/{{member.github}}">{{member.github}}</a>
               </div>
            </div>
            {% endfor %}
         </div>
         <p>
             The Consulting Executive Director supports the Board and oversees day-to-day operations as well as member relations.
          </p>
         <h2>Technical Steering Committee</h2>
         <p>
            The Bytecode Alliance <a href="https://github.com/bytecodealliance/governance/blob/main/TSC/charter.md">Technical Steering Committee</a> ("TSC") acts as the top-level governing body for projects and Special Interest Groups hosted by the Alliance, ensuring they further the Alliance's mission and are conducted in accordance with our <a href="#social-values">values and principles</a>.  The TSC also oversees the Bytecode Alliance <a href="https://github.com/bytecodealliance/governance/blob/main/TSC/charter.md#recognized-contributors">Recognized Contributor</a> program to encourage and engage individual contributors as participants in Alliance projects and groups.
         </p>
         <div class="board-gallery">
           {% comment %}Generate gallery of TSC members from list in _data/tsc.yml{% endcomment %}
           {% for member in site.data.tsc %}
            <div class="board-member">
               <img src="https://github.com/{{member.github}}.png">
               <div>
                  <h4>{{member.name}}</h4>
                  {{member.title}}<br>
                  {% if member.office %}
                     {{member.office }}<br>
                  {% endif %}
                  GitHub: <a href="https://github.com/{{member.github}}">{{member.github}}</a>
               </div>
            </div>
            {% endfor %}
        </div>
      </div>
   </div>
</section>

<section>
    <div class="container w-container">
        <div class="width-container" markdown="1">

## [Values](#values)

### [Social Values](#social-values)
1. Collaboration<br>
   Our alliance facilitates collaborative development.
2. Inclusiveness<br>
   Our alliance fosters welcoming, inclusive, and non-discriminatory environments.
3. Openness<br>
   What we develop is Free and Open Source, and available for everyone, not just our members. We accept all contributors who are willing and able to collaborate and adhere to our alliance’s values.

### [Technical Values](#technical-values)
1. Thoughtful balance<br>
   We recognize that many technical principles stand in tension with each other. We will make thoughtful, explicit trade-offs when necessary, but strive for creative solutions that allow those values to all coexist. In particular, we hold the technical principles of Security, Efficiency, Modularity, and Portability as key concerns to balance in all designs and their implementations.
2. Documentation and Testing<br>
   We consider documentation and tests a core part of maintainable, sustainable development.

### [Process Values](#process-values)
1. Influence through effort<br>
   We grant influence and decision-making authority through ongoing efforts towards our alliance’s vision and goals, not through monetary contributions.
2. Sustainable velocity<br>
   In all design and implementation decisions, we will take care to balance short-term velocity with stability and maintainability, to sustain a healthy velocity in the long term.
3. Localized governance wherever possible<br>
   We localize decision-making processes into individual projects where possible. We lift decisions to a higher governance level only when necessary, such as to mediate deadlocks or facilitate cross-project design and implementation decisions.
4. Disagree and commit<br>
   We may re-examine decisions given new evidence or new ideas, and we may document disagreement and trade-offs, but we will not undermine each other’s work.
5. Lightweight processes<br>
   We introduce processes as-needed, and make them as lightweight as possible.

</div>
</div>
</section>