---
layout: default
permalink: /security
title: Security Policy
---

<section>
    <div class="container w-container">
        <div class="width-container" markdown="1">

## Reporting a security bug in a Bytecode Alliance project

If you think you have found a security issue in a Bytecode Alliance project,
please send email to <security@bytecodealliance.org>.
This list is delivered to a small security team. We will then acknowledge receipt
of your report and prioritize initial analysis of severity.

The security team may work in private with individuals from Bytecode Alliance
member organizations, core contributors to the affected project(s), and, where
applicable, affected downstream projects and products, regardless of their
Bytecode Alliance affiliation.

After the initial reply to your report, the security team will endeavor to keep
you informed of the progress being made towards a fix and full announcement,
and may ask for additional information or guidance surrounding the reported
issue.

If you have not received a reply to your report within two days, please reach out
on our [Zulip instance](https://bytecodealliance.zulipchat.com/) by posting a
message in the [#general stream](https://bytecodealliance.zulipchat.com/#narrow/stream/206238-general).

Note that the #general stream is public, so please don't discuss details of your
issue there. Instead, simply say that you're trying to get a hold of someone from
the security team.

## Preferences

*   Please provide detailed reports with reproducible steps and a clearly defined impact.
*   Submit one vulnerability per report.
*   Social engineering (e.g. phishing, vishing, smishing) is prohibited.

## Disclosure Policy

Here is the security disclosure policy for Bytecode Alliance projects.

* The security report is received and is assigned a primary handler. This
  person will coordinate the fix and release process. The problem is confirmed
  and a list of all affected versions is determined. Code is audited to find
  any potential similar problems. Fixes are prepared for all releases which are
  still under maintenance. These fixes are not committed to the public
  repository but rather held locally pending the announcement.

* A suggested embargo date for this vulnerability is chosen and a CVE (Common
  Vulnerabilities and Exposures (CVE®)) is requested for the vulnerability.

* A prenotification may be published on the security announcements mailing list,
  providing information about affected projects, severity, and the embargo date.

* On the embargo date, the Bytecode Alliance security mailing list is sent a copy of the
  announcement. The changes are pushed to the public repository and new builds
  are deployed. Within 6 hours of the mailing list being
  notified, a copy of the advisory will be published on the Bytecode Alliance blog.

* Typically the embargo date will be set 72 hours from the time the CVE is
  issued. However, this may vary depending on the severity of the bug or
  difficulty in applying a fix.

* This process can take some time, especially when coordination is required
  with maintainers of other projects. Every effort will be made to handle the
  bug in as timely a manner as possible; however, it’s important that we follow
  the release process above to ensure that the disclosure is handled in a
  consistent manner.

## Receiving Security Updates

Security notifications will be distributed via the following methods.

* <https://groups.google.com/a/bytecodealliance.org/g/sec-announce>
* <https://bytecodealliance.org/articles/>

</div>
</div>
</section>
