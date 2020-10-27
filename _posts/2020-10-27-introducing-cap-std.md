---
title: "Introducing cap-std, a capability-oriented version of the Rust standard library"
author: "Dan Gohman"
github_name: sunfishcode
---

## Introducing `cap-std`

`cap-std` is a project to create capability-oriented versions of Rust standard
library and related APIs. Capability-oriented here means that the APIs don't
access files, directories, or other external resources implicitly, but instead
operate on handles that are explicitly passed in. This helps programs that
work with potentially malicious content avoid accidentally accessing resources
other than they intend, and does so without the need of a traditional
process-wide sandbox, so it can be easily embedded in larger applications.

## Background

Some of the most devious software bugs are those where the code looks like it
does one thing, and usually does that thing in practice, but sometimes, under
special circumstances, does something else. Here's a simple example using
Rust's filesystem APIs:

```rust
    fn hello(name: &Path) -> Result<()> {
        let tmp = tempdir()?;
        fs::write(tmp.path().join(name), "hello world")?;
    }
```

The expected behavior of this function is to write "hello world" to a file within
a temporary directory. The code looks like it will do this. And indeed, it will
*usually* do this. But if the path passed in is `../../home/me/.ssh/id_dsa.pub`,
then the behavior of this function could be to corrupt the user's ssh public key.
That's... not remotely within what we said the expected behavior is. It usually
doesn't do that, but under the right circumstances, it could.

And since `name` is just a string, if the string is computed in a way that could
be influenced by an attacker, the right circumstances could easily occur in
practice.

The [`cap-std` project] provides Rust crates with lightweight ways to avoid such
problems. In particular, the [`cap-std` crate]'s `Dir` type represents a
directory, with [methods] corresponding to Rust's `std::fs` functions, for
opening and working with files within the directory, that ensure that all paths
stay within that directory. In contrast to conventional sandboxing, `cap-std`
doesn't have any global state, so using it in one part of an application doesn't
require using it in the rest of the application. Library crates can use
`cap-std` internally without imposing any sandboxing constraints on their users.

[`cap-std` project]: https://github.com/bytecodealliance/cap-std/
[`cap-std` crate]: https://docs.rs/cap-std
[methods]: https://docs.rs/cap-std/latest/cap_std/fs/struct.Dir.html#impl

## What can `Dir` do?

`cap_std` is just a library, so by itself, it isn't a sandbox for arbitrary
Rust code—it can't prevent arbitrary Rust code from using `std::fs`'s
path-oriented APIs. Instead, it protects against malicious *content*, when
filesystem paths can be influenced by untrusted inputs, and malicious
*concurrent modifications*, when another program running at the same time
has the ability to remove, rename, or create files, directories, symlinks,
or hard links in ways that could cause a program to inadvertently access
unintended resources.

Revisiting our example above, with `cap-std` we might write:

```rust
    fn hello(name: &Path, tmp: &Dir) -> Result<()> {
        tmp.write(name, "hello world")?;
    }
```


In this code, tmp.write returns an error instead of writing to a path outside
of tempdir.

One key difference from before is that instead of creating the temporary
directory itself, this function requests a directory be passed in. The `Dir`
type here serves as a "vocabulary" type, allowing the function to declare that
it wants a directory to be passed in, and that it intends to access resources
within that directory, rather than accessing arbitrary locations in the
filesystem. These kinds of declarations can help reduce the
[reasoning footprint] of a function call.

[reasoning footprint]: https://blog.rust-lang.org/2017/03/02/lang-ergonomics.html

The `Dir` crate also makes it much easier to write this code robustly. There's
no need to think about `..` or absolute paths at the application level, and no
need to handle symlinks specially, which with the Rust standard library today
isn't even possible to do robustly without [platform-specific code].

[platform-specific code]: https://doc.rust-lang.org/std/os/unix/fs/trait.OpenOptionsExt.html#examples-1

It also gives callers increased control. The caller gets to choose how and
where to create the directory, and when to remove it. Callers choose to use
something like [`cap-tempfile`]'s `tempdir` function to easily create a
temporary directory in a conventional location and automatically remove it
afterwords, however they could also opt to create the directory somewhere
else and manage it manually.

Note that `Dir` is passed by immutable reference, even though it's being used
to mutate external filesystem state. This follows Rust's conventions, for
example in [`std::fs::File::set_len`], and it reflects an underlying truth
about filesystems. `&mut` in Rust is sometimes called an "exclusive" reference,
because when someone has a `&mut`, they're the only one which can access the
underlying object. However, this is generally not a safe assumption when
working with filesystem objects, because other programs could concurrently
access or even mutate files or directories without Rust's type system having
any say in the matter. Consequently, it makes sense to think of filesystem
state as being external to the program, with `File` and `Dir` objects being
just handles that are themselves typically immutable.

`Dir` can also be combined with other security techniques. In a project which is
written to carefully avoid using untrusted paths, it can add an extra layer of
defense in depth. And in the [Wasmtime] project, we're planning to use it in
combination with with our WebAssembly sandbox to implement sandboxed access to
system resources as part of a project to build our WASI implementation on a
strong foundation.

[`std::fs::File::set_len`]: https://doc.rust-lang.org/std/fs/struct.File.html#method.set_len

[Wasmtime]: https://github.com/bytecodealliance/wasmtime/

## Usage

The main pattern for filesystem operations using the `cap-std` crate is to
obtain a `Dir` and use methods on it, which closely resemble the functions in
`std::fs`.

One of the ways to obtain a `Dir` is to use the [`cap-directories`]
crate to request a `Dir` for a standard directory (similar to the
[`directories-next`] crate, but returns a `Dir` instead of a `Path`).
For example, to obtain the data directory for an example program:

```rust
    let project_dirs = unsafe {
        cap_directories::ProjectDirs::from(
            "com.example",
            "Example Organization",
            "`cap-std` Key-Value CLI Example",
        ).unwrap()
    };

    let data_dir = project_dirs.data_dir().unwrap();
```

Then in place of `fs::read` and `fs::write` to read and write files, one
can use `data_dir` here to do `data_dir.read(key)` and
`data_dir.write(file_name, value)`.

Note the use of `unsafe` here. While `unsafe` in Rust often refers to possible
memory unsafety, it may also be used to describe functions in an API which
don't uphold the invariants of the rest of the API, and that's how it's being
used here. For example, [`File::from_raw_fd`] in Rust's standard library is
`unsafe` to indicate that a `File` is meant to be the sole owner of a file
descriptor, and the `from_raw_fd` method isn't guaranteed to uphold that
guarantee. Analogously, `cap-std`, `cap-directories`, and related crates have
an invariant that safe functions don't introduce ambient authorities. They
don't create their own absolute filesystem paths, and always rely on resources
being passed in as handles. [`cap_directories::ProjectDirs::from`] is a
function which internally crates absolute paths, so it is marked `unsafe`.

[app-dirs`]: https://crates.io/crates/app_dirs2/
[`AppInfo`]: https://docs.rs/app_dirs2/latest/app_dirs2/struct.AppInfo.html
[`File::from_raw_fd`]: https://doc.rust-lang.org/std/fs/struct.File.html#method.from_raw_fd

To see all this put together in a complete example, see
[the kv-cli example](https://github.com/bytecodealliance/cap-std/blob/main/examples/kv-cli.rs)
in the `cap-std` repository. This program implements a simple key-value store,
using filesystem paths as keys, and using `cap-std` ensures that it only
accesses paths within its own data directory. Attempts to escape the directory
with `..` fail gracefully. This is true even if a concurrently running program
renames directories on the path or changes symlinks—something that's very hard
to get right using `std::fs` APIs.

```sh
$ cargo run --quiet --example kv-cli color green
$ cargo run --quiet --example kv-cli color
green
$ cargo run --quiet --example kv-cli temperature cold
$ cargo run --quiet --example kv-cli temperature
cold
$ cargo run --quiet --example kv-cli color
green
$ cargo run --quiet --example kv-cli /etc/passwd
Error: a path led outside of the filesystem
$ cargo run --quiet --example kv-cli ../../../secret_cookie_recipe.txt
Error: a path led outside of the filesystem
```

Another useful crate is [`cap-tempfile`], which creates temporary directories
and provides a `Dir` to access them.

It's also possible to create a `Dir` by opening a raw path, using
`Dir::open_ambient_dir`. Note that this function is `unsafe` since it does
not uphold the sandboxing invariant that the rest of the API does.

[`cap-directories`]: https://docs.rs/cap-directories
[`cap-tempfile`]: https://docs.rs/cap-tempfile
[`directories`]: https://crates.io/crates/directories

## Implementation Landscape

One of the reasons that Rust doesn't already have a `Dir` type, when it does have a
`File` type, is that popular OS filesystem APIs don't make this as efficient
or idiomatic as just using paths to name directories. However, this is changing.

One of the inspirations for `cap-std` is the [CloudABI project], which among
other things developed a technique of using a sequence of `openat` calls to
emulate path lookup in userspace in a way that's robust in the face of concurrent
renames. `cap-std` uses a variant of this technique, optimized to use fewer
intermediate system calls, to implement a portable sandboxed path lookup algorithm.

[CloudABI project]: https://cloudabi.org/

And, Linux [recently] added a system call, `openat2`, which has the ability to
[restrict path lookup] so that it stays within a given directory, which is exactly
the behavior we want here. It doesn't require a process-wide mode, and it avoids
the overhead of doing multiple system calls. `cap-std` uses this in place of its
portable algorithm whenever it can. On systems which support `openat2`, most
functions in the API perform only one or two system calls.

[recently]: https://lwn.net/Articles/816213/
[restrict path lookup]: https://lwn.net/Articles/796868/

Linux and other operating systems are also exploring adding more such features,
and as these features become available, it will become increasingly practical to
not just implement a `Dir` type, but to implement it with WASI-style sandboxing
protections built in.

## Philosophy

`cap-std` came about because we were looking to generalize the filesystem
sandboxing techniques we were using in Wasmtime's WASI implementation to make
them more broadly applicable, and we were particularly inspired by
[`async-std`'s philosophy]:

> the best API is the one you already know.

[`async-std`'s philosophy]: https://github.com/async-rs/async-std#philosophy

Rust already has a standard library API. It's very good overall, and a lot of
care has gone into ensuring that it's implementable on many platforms. It's
used by a lot of code, and well known to a lot of developers.

`cap-std` is an approach that takes advantage of this. Developers who know `std`
can easily learn `cap-std`. Applications using `std` can be ported to `cap-std`, with
the main concern being about how to ensure that directory handles are available
to all the places that need them, rather than with dealing with differences
in the API or in filesystem behavior.

The close alignment between `cap-std` and `std`, combined with the close
alignment between [`async-std`] and `std`, also make it straightforward to do
both at the same time, producing [`cap-async-std`].

[`async-std`]: https://async.rs/
[`cap-async-std`]: https://docs.rs/cap-async-std

`cap-async-std` is currently a very simplistic port of `cap-std`, and many of
the operations are not yet optimized to take advantage of `async`, but the core
of the idea is there: if you're familiar with using `std::fs`, `cap-std`'s and
`cap-async-std`'s APIs should feel familiar, and it should be straightforward to
port code from `std::fs`.

## Current status

The `std`-like filesystem and time APIs, [`cap_std::fs`], [`cap_std::time`], the
corresponding extension crates adding additional filesystem and time features
[`cap-dir-ext`] and [`cap-time-ext`], as well as the random number crate
[`cap-rand`], currently work on Linux, macOS, FreeBSD, and Windows, with stable
Rust. On Linux, [`cap_std::fs`] is optimized to use new system calls including
`openat2`, when available, which significantly reduce the sandboxing overhead.

`cap_std::fs` and `cap_std::time` pass a translation of the tests in Rust's
[`fs`] and [`time`] modules into `cap-std` APIs. It has a modest suite of its
own tests, a `cargo fuzz` target to test for sandbox escapes and other bugs,
and a `cargo bench` suite for measuring performance.

[`cap_std::fs`]: https://docs.rs/cap-std/latest/cap_std/fs/index.html
[`cap_std::time`]: https://docs.rs/cap-std/latest/cap_std/time/index.html
[`cap-dir-ext`]: https://docs.rs/cap-dir-ext/latest/cap_dir_ext/
[`cap-time-ext`]: https://docs.rs/cap-time-ext/latest/cap_time_ext/
[`cap-rand`]: https://docs.rs/cap-rand/latest/cap_rand/
[`fs`]: https://github.com/rust-lang/rust/blob/master/library/std/src/fs/tests.rs
[`time`]: https://github.com/rust-lang/rust/blob/master/library/std/src/time/tests.rs

Support for compiling to WASI is under active development.

## Speaking of WASI...

The sandboxing performed by `cap-std` is the same as what's provided by WASI APIs,
with one difference: while `cap-std` is designed so that it can be used as a
library within otherwise unsandboxed programs, WASI applies this sandboxing to
all filesystem access to that it serves as an extension to the core WebAssembly
sandbox.

This means that when the `cap-std` library is compiled for the WASI platform, it
will be able to bypass its own sandboxing techniques and simply call into the WASI
system calls directly, achieving smaller code size and tighter integration with
the underlying WASI platform.

[`WASI`]: https://github.com/WebAssembly/WASI

## The Future!

We're continuing to add more testing, fuzzing, and optimization. A port to WASI
is underway.

We're also starting to think about extending the capability-oriented model to more
parts of Rust's API. The most obvious next step is `std::net`, which is in a very
early state right now, but this is a space we're thinking about for the future! Other
areas that may be interesting include `std::env` for information passed in by the
host environment, `std::process` for launching sandboxed processes, and anything else
that allows programs to interact with the outside world.

And as we're doing with [`cap-directories`] and [`cap-tempfile`], we're also interested
in ways that we can do more than just translate the standard library API into a
capability-oriented model, but also make the capability-oriented model easy to use.
