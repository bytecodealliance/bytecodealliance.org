---
title: "Using Wasmtime from Ruby"
author: "Jimmy Bourassa"
github_name: jbourassa
---

We’re happy to announce the release of [the `wasmtime` Ruby
gem](https://rubygems.org/gems/wasmtime), the official embedding of Wasmtime
for Ruby.

## Goal

The initial use case for this came from Shopify – a commerce platform built on
Ruby and the company sponsoring this work. Shopify is heavily investing in
making commerce extensible. Among other things, it uses WebAssembly to run
untrusted code on the server. All that Wasm code must run fast and securely.

The goal of the gem is to allow **exposing all of Wasmtime’s power with minimal
overhead**. The gem’s API should have a nice Ruby feel to it – we think it
does! – but it intentionally does not introduce new abstractions or DSLs. These
can be added by the community through new gems.

To best reach the project’s goal, we’ve built a Rust-based native Ruby
extension using Wasmtime’s Rust API.

## Wait – Rust?

_Why pick Rust?_ you may ask, knowing Ruby native extensions are normally written in
C? That is a fair question, let’s dive into it.

First, Wasmtime’s Rust API is the canonical one. It is more expressive &mdash; thanks
to Rust &mdash; and tends to get the features first. Closing the gap between Rust’s
and C’s API would have increased the scope of work greatly.

Second, Rust is gaining in popularity in the Ruby community, increasing the
pool of potential contributors. YJIT (Ruby’s latest JIT compiler) uses Rust and
is [now considered stable](https://github.com/ruby/ruby/pull/6909) as of Ruby
3.2. RubyGems also added [support for scaffolding Rust-based native extensions
using the Magnus crate](https://github.com/rubygems/rubygems/pull/6149), which
makes writing Rust-based Ruby native extensions a breeze.

Finally, Rust helps build more secure and robust programs thanks to its type
system and the borrow checker. That’s one of the many reasons why Shopify chose
[Rust as its systems programming
language](https://shopify.engineering/shopify-rust-systems-programming).

The main drawback of using Rust is that the compiler is not widely available
as C’s. This drawback is mitigated by shipping precompiled libraries for
macOS, Linux and Windows. Most users won’t even need to know it’s written in
Rust! All in all, Rust is a better fit to help us reach our goal and lower the
long-term maintenance cost.

## How to use it?

Assuming you have a supported Ruby version (we recommend 3.0+) and Bundler,
you’re good to go. We’ll use Bundler to install the gem: 

```
bundle init && bundle add wasmtime
```

We can now use Wasmtime from Ruby. Let’s write a simple program as an example.

```ruby
# Create an engine. Generally, you only need a single engine
# and can re-use it throughout your program.
engine = Wasmtime::Engine.new

# Compile a Wasm module from either Wasm or WAT.
mod = Wasmtime::Module.new(engine, <<~WAT)
  (module
    (func $hello (import "" "hello"))
    (func (export "run") (call $hello))
  )
WAT

# Create a store with an optional arbitrary object.
store_data = { count: 0 }
store = Wasmtime::Store.new(engine, store_data)

# Define a Wasm function from Ruby code.
# The function has no params ([]) and no results ([]).
func = Wasmtime::Func.new(store, [], []) do |caller|
  puts "Hello from Func!"
  caller.store_data[:count] += 1
  puts "Ran #{caller.store_data[:count]} time(s)"
end

# Build the Wasm instance by providing its "hello" import.
instance = Wasmtime::Instance.new(store, mod, [func])

# Run the `run` export.
instance.invoke("run")
```

Running the above will print:

```ruby
Hello from Func!
Ran 1 time(s)
```

If you’ve seen Wasmtime’s Rust API, this should all feel very familiar!

## What’s next

While we’re pretty happy with the gem, it is still early. There is still room
for reducing the performance overhead of the gem and some missing features.

If you find a missing feature you would want, something slow, a bug, or any
other kind of improvements, [come and talk to us on
GitHub](https://github.com/bytecodealliance/wasmtime-rb/issues/new)!
