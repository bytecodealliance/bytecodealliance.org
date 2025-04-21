---
title: "Wasmtime LTS Releases"
author: "Alex Crichton"
date: "2025-04-22"
github_name: "alexcrichton"
excerpt_separator: <!--end_excerpt-->
---

[Wasmtime](https://wasmtime.dev/) is a lightweight WebAssembly runtime built for
speed, security, and standards-compliance. Wasmtime now supports
long-term-support (LTS) releases that are maintained with security fixes for 2
years after their initial release.

<!--end_excerpt-->

The Wasmtime project releases a new version once a month with new features, bug
fixes, and performance improvements. Previously though these releases were only
supported for 2 months meaning that embedders needed to follow the Wasmtime
project pretty closely to receive security updates. This rate of change can be
too fast for users so Wasmtime now supports [LTS
releases](https://github.com/bytecodealliance/rfcs/blob/main/accepted/wasmtime-lts.md).

Every 12th version of Wasmtime will now be considered an LTS release and will
receive security fixes for 2 years, or 24 months. This means that users can now
update Wasmtime once-a-year instead of once-a-month and be guaranteed that they
will always receive security updates. Wasmtime's 24.0.0 release has been
retroactively classified as a LTS release and will be supported until August 20,
2026. Wasmtime's upcoming 36.0.0 release on August 20, 2025 will be supported
until August 20, 2027, meaning that users will have one year starting in August
to upgrade from 24.0.0 to 36.0.0.

You can view a table of Wasmtime's releases [in the documentation
book](https://docs.wasmtime.dev/stability-release.html) which has information on
all currently supported releases, upcoming releases, and information about
previously supported releases. The high-level summary of Wasmtime's LTS release
channel is:

* LTS releases receive patch updates for 2 years after their initial release.
* Patch releases are guaranteed to preserve API compatibility.
* Patch releases strive to maintain tooling compatibility (e.g. the Rust version
  required to compile Wasmtime) from the time of release. Depending on EOL dates
  from components such as GitHub Actions images, however, this may need minor
  updates.
* Patch releases are guaranteed to be issued for any security bug found in
  historical releases of Wasmtime.
* Patch releases may be issued to fix non-security released bugs as they are
  discovered. The Wasmtime project will rely on contributions to provide
  backports for these fixes.
* Patch releases will not be issued for new features to Wasmtime, even if a
  contribution is made to backport a new feature.

If you're a current user of Wasmtime and would like to use an LTS release then
it's recommended to either downgrade to the 24.0.0 version or wait for this
August to upgrade to the 36.0.0 version. Wasmtime 34.0.0, to be released June
20, 2025, will be supported up until the release of Wasmtime 36.0.0 on August
20, 2025.
