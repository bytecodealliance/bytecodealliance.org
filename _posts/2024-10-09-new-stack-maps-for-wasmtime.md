---
title: "New Stack Maps for Wasmtime and Cranelift"
author: "Nick Fitzgerald"
github_name: "fitzgen"
---

As part of implementing the WebAssembly garbage collection proposal in Wasmtime,
which is an ongoing process, we've overhauled the stack map infrastructure in
Cranelift. This post will explain what stack maps are, why we needed to change
them, and how the new stack maps work.

[Wasmtime] is a lightweight WebAssembly runtime that is fast, secure, and
standards-compliant. [Cranelift] is its compiler backend, which aims to strike a
balance between code quality and compile time, while maintaining exceptionally
high standards for correctness. The [garbage collection proposal for
WebAssembly][wasm-gc] extends the WebAssembly language with runtime-managed
references to `struct`s and `array`s.

[wasm-gc]: https://github.com/WebAssembly/gc
[Wasmtime]: https://wasmtime.dev/
[Cranelift]: https://cranelift.dev/

## Background: Garbage Collection, Safepoints, and Stack Maps

In the garbage collection (GC) literature, we call the program that allocates
objects and adds or removes edges between them the *mutator*. It mutates the
heap graph.

As the mutator runs, allocating objects and filling up the GC heap, the runtime
must eventually perform a GC. But the runtime can't collect garbage at any
arbitrary moment: the mutator might be in the middle of manipulating some
objects, keeping them in its stack frame or in registers, and effectively hiding
them from the runtime. The runtime must know about all such objects, or else it
might reclaim an object that it believes is garbage, but which the mutator is
still using, leading to use-after-free bugs. This is where safepoints and stack
maps come in.

A *safepoint* is a program point in the mutator (that is, an instruction in the
compiled WebAssembly program) where it is safe for the runtime to collect
garbage. When the mutator calls out to a runtime routine, for example, that
`call` instruction would typically be a safepoint, under the assumption that the
runtime might need to GC while running the routine.

The mutator's compiler does two things to make a safepoint safe, in the presence
of objects that the mutator is still actively working with:

1. Insert instructions to move the objects from (say) volatile registers that a
   `call` safepoint might clobber to well-known locations in the stack frame.

2. Emit *stack map* records that describe, for each safepoint in the mutator
   program, the locations where to find those still-in-active-use objects inside
   the stack frame.

While collecting garbage, the runtime can walk the mutator's stack frames and,
using those stack maps, identify all of the objects that the mutator is still
manipulating. No more potential use-after-collected bugs!

But there is a final twist: if the GC is a moving collector, for example a
[generational][gen-gc] or [compacting][mark-compact] collector, then an object
may be relocated in memory during collection. If an object is moved, then all
references to the object must also be updated to refer to the new
location. Failure to update a reference leads to use-after-move bugs like
accessing newly-allocated objects that happened to be placed in the original
object's old location. So, in the presence of a moving collector, the runtime
must additionally update the mutator's stack frame, redirecting each reference
noted in the stack map so that it now points to its object's new memory
location. The compiler must, in turn, insert reloads of each GC-managed
reference from its stack map location that it was spilled to &mdash; that is,
from the location where the runtime potentially overwrote the old reference with
a new, redirected reference &mdash; and back into a register so that the mutator
may continue to manipulate the object.

[gen-gc]: https://en.wikipedia.org/wiki/Tracing_garbage_collection#Generational_GC_(ephemeral_GC)
[mark-compact]: https://en.wikipedia.org/wiki/Mark%E2%80%93compact_algorithm

## Cranelift's Old Approach: Stack Maps During Register Allocation

Cranelift previously generated stack maps during register allocation. Our
register allocator naturally tracks the live range of each value in order to
determine whether the same hardware register may or may not be reused for two
values. At each safepoint, it would insert spills for each of the live values
that are managed by the GC, and record those spilled locations in a stack map
for that program point. This approach is straightforward on the surface, but led
to a number of subtle downsides and complications.

First, because register allocation is so late in the compiler pipeline, the
previous system involved tracking GC-managed references through almost the
entire compiler: from the WebAssembly frontend, through the <abbr
title="Instruction Set Architecture">ISA</abbr>-agnostic mid-end, through the
ISA-specific backends, and into register allocation. The only part of the
pipeline that didn't have to preserve knowledge of GC-managed references was the
final instruction encoding and binary emission. In general, the fewer invariants
we must maintain, the simpler our compiler's implementation. If we could avoid
precisely tracking GC references throughout most of Cranelift, we could expect
less complexity and, in general, less complexity would mean fewer bugs. The
complexity of the coordination required between the runtime and the compiler to
correctly implement garbage collection and stack maps has [bitten][cve1]
[us][cve2] [before][cve3].

[cve1]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-5fhj-g3p3-pq9g
[cve2]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-gwc9-348x-qwv2
[cve3]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-4873-36h9-wv49

Second, to make tracking GC-managed values easier, we distinguished them from
plain pointers and integers with dedicated types in Cranelift's intermediate
representation (CLIF). This succeeded in making them easier to track, but led to
foiling instruction selection rules and mid-end peephole rewrites that otherwise
should have applied. For example, checking if a pointer is null involves simply
comparing it to zero, the same way we compare any other integer to zero:

```python
v456 = icmp_imm eq v123, 0
```

Checking whether GC reference was null, on the other hand, required a dedicated
`is_null` instruction, despite lowering to identical machine code when it
appears in isolation:

```python
v456 = is_null v123
```

This doesn't seem like a big deal at first glance, beyond being forced to define
additional, duplicate instructions that waste our opcode space and inflate our
instruction set. However, we have a bunch of instruction selection rules for
integer comparisons followed by conditional branches, for example, that let us
avoid materializing flags on `x86_64`, yielding smaller and faster machine code
in those contexts. However, because `is_null` is a different instruction, these
rules' patterns don't match, and their optimizations are missed. The result is
that we must choose between generating subpar code or duplicating the relevant
set of instruction selection rules to also match against an `is_null`
instruction followed by a conditional branch.

Third, in addition to missed optimizations, we were also seeing
misoptimizations: incorrect transformations that broke the input program. From
its point of view, our mid-end was performing perfectly legal optimizations. But
the mid-end can't reason about effects that it can't see, and it couldn't see
the spills and reloads of GC references associated with a safepoint because they
weren't inserted yet. This lack of visibility became an issue when we were, for
example, accessing the same field of an object before and after a safepoint:

```asm
;; `v0` is a reference to a GC-managed object.
v0 = ...
;; Bitcast it to an `i64` so we can do pointer
;; arithmetic on it.
v1 = bitcast.i64 v0
;; Get the address of the field we want to
;; access.
v2 = iadd_imm v1, 8
;; Write `11` into the object field.
v3 = iconst.i32 11
store.i32 v2, v3

;; Call some function! This might trigger a GC
;; and therefore must be a safepoint.
call $f()

;; Write to same field as above, but with the
;; value `22` this time.
v4 = bitcast.i64 v0
v5 = iadd_imm v4, 8
v6 = iconst.i32 22
store.i32 v5, v6
```

Our mid-end performs a number of ISA-agnostic optimizations, including [global
value numbering (GVN)][gvn] (as part of its [e-graphs pass][aegraphs]) to
eliminate duplicate computations. When the mid-end processed the CLIF snippet
above, it would determine that the second field-address computation was
redundant, and we could instead reuse the result of the first field computation,
yielding the following optimized CLIF:

```asm
v0 = ...
v1 = bitcast.i64 v0
v2 = iadd_imm v1, 8
v3 = iconst.i32 11
store.i32 v2, v3

call $f()

v6 = iconst.i32 22
;; Reusing the field address we previously
;; computed above.
store.i32 v2, v6
```

To reason about why this transformation is invalid &mdash; despite only
deduplicating pure, non-effectful, and otherwise-identical instructions &mdash;
we must consider context that is invisible to the mid-end: the safepoint spills
and reloads that will be inserted later by the register allocator. The second
field-address computation is not actually reusing `v0` as its base, it is using
`reload(v0)` as the base, but that `reload` operation is hidden from the
mid-end. If the runtime collected garbage during `$f`'s execution and moved the
object that `v0` references, then in this optimized CLIF, the second `store` is
writing to the object's old, vacated location, which is a use-after-move
vulnerability.

We began to address these sorts of bugs in a whack-a-mole fashion, e.g. by
marking bitcasts of reference types as side-effectful, but ultimately we'd
rather not play this whack-a-mole game at all, reacting to bugs as we find them,
never knowing how many are still lurking. Instead, we'd much prefer that the
mid-end simply had the visibility it needs to optimize correctly in the first
place.

A final quirk of the old system was that GC references were always represented
as pointers at the machine level. You could only use 64-bit references on 64-bit
ISAs and 32-bit references on 32-bit ISAs, and you definitely could not do
[`NaN` boxing][nan-boxing]. This was an annoyance for us in practice because
we've designed Wasmtime's GC implementation such that our GC references are
always 32-bit integers, even on 64-bit ISAs. This design choice lets us leverage
the same sandboxing and virtual-memory techniques to elide bounds checks that
Wasmtime already implements for WebAssembly linear memories. It lets us benefit
from smaller objects and denser cache locality; because of that, it is a fairly
[common][hotspot-compressed-oops] [technique][v8-compressed-pointers]. But,
despite storing GC references in 32 bits on the heap, Cranelift's old system
forced us to extend those references to 64 bits when we were manipulating them
on the stack or in registers when targeting a 64-bit ISA.

[gvn]: https://en.wikipedia.org/wiki/Value_numbering#Global_value_numbering
[aegraphs]: https://vimeo.com/843540328
[hotspot-compressed-oops]: https://wiki.openjdk.org/display/HotSpot/CompressedOops
[v8-compressed-pointers]: https://v8.dev/blog/pointer-compression
[nan-boxing]: https://anniecherkaev.com/the-secret-life-of-nan

## The New Approach: User Stack Maps

Given the complications of Cranelift's previous system for tracking GC
references across safepoints and emitting stack maps, we decided to implement a
new approach. Instead of generating safepoint spills, reloads, and stack maps at
the end of the compiler pipeline, the user is responsible for producing CLIF
that already contains those spills and reloads, as well as annotating each
safepoint with the virtual stack slots live GC references were spilled into. The
mid-end, backends, and register allocator have no extra responsibilities other
than forwarding these annotations through to binary emission, at which point we
can translate the virtual stack slots into precise stack-pointer offsets and
emit stack maps. We dubbed this new approach "user stack maps" because their
correctness largely falls upon the Cranelift user, rather than the core of
Cranelift itself.

User stack maps mean that we no longer need to precisely track GC references
throughout the whole compiler pipeline. This simplification allows us us to
remove the distinct reference types from CLIF, as well as their related
instructions, like `is_null`. This means no more missed optimizations or
duplicated instruction selection rules.

With user stack maps, we no longer have to worry about safepoint-specific
miscompilations in the mid-end. Let's revisit the previous miscompilation
example, where we wrote to a GC object's field before and after a
safepoint. This is what the initial CLIF looks like with user stack maps, where
the CLIF producer has already inserted the spills and reloads for the safepoint:

```asm
;; Set the field to `11`
v0 = ...
v1 = iadd_imm v0, 8
v2 = iconst.i32 11
store.i32 v1, v2

;; NEW: Spill `v0` to stack slot `ss0`
;; before the safepoint.
v3 = stack_addr ss0
store.i64 notrap v3, v0

;; NEW: stack map annotation on the safepoint.
call $f(), stack_map = [i64 @ ss0]

;; NEW: Reload what was `v0` from the
;; stack slot. Don't reuse `v0` because
;; the referenced object could have
;; moved.
v4 = stack_addr ss0
v5 = load.i64 notrap v4

;; Set the field to `22`.
v6 = iadd_imm v5, 8
v7 = iconst.i32 22
store.i32 v6, v7
```

Looking at the updated CLIF, it is immediately obvious to the mid-end that
reusing the initial field-address computation for the second store is invalid.
The base of the second field-address computation is `v5`, not `v0`, and it
cannot prove that `v5` and `v0` are actually the same value; indeed, if the
referenced object moved in memory then they will *not* be the same! We've
avoided the previous misoptimization by construction.

Cranelift already must preserve the effects of accessing memory, and a
safepoint's spills and reloads are no different: they are explicitly present and
modeled in the intermediate representation as loads and stores, the same as any
other memory access. In the world of user stack maps, supporting safepoint
spills and reloads is not an additional responsibility nor additional
implementation complexity for the compiler.

User stack maps actually unlock *more* potential optimizations than what used to
be possible. Our alias analysis pass, which performs redundant load elimination
and store-to-load forwarding, can now see and operate upon safepoint-related
spills and reloads. And once again, Cranelift's surface area that is critical
for correctness has not grown; the alias analysis pass must already preserve the
effects of accessing memory.

While user stack maps are a big simplification for most of the compiler
pipeline, they do shift some of that old complexity into the frontend. The
mid-end, backends, and register allocator no longer need to precisely track GC
references, and insert spills and reloads at safepoints, but now the frontend
must. We believe that we've ended up at a design point with less overall
complexity.

We, the Cranelift developers, couldn't leave users (i.e. we, the Wasmtime
developers) completely on their own, without any tools to help produce correct
safepoints in CLIF. Cranelift users, including Wasmtime, generally use [the
`cranelift-frontend` crate] to produce the initial CLIF that Cranelift takes as
input to compilation. `cranelift-frontend` helps users build CLIF from their
source language, handles [SSA] construction, and etc...; it is an appropriate
place to help with user stack maps as well. While they are creating CLIF with
`cranelift-frontend`, users can now mark any value as requiring inclusion in
stack maps, and `cranelift-frontend` will automatically insert spills and
reloads of that value around safepoints, as well as annotate those safepoints
with stack map entries that record the spill locations for the runtime.

To fulfill these new obligations, the `cranelift-frontend` crate performs a
simple [liveness] analysis for GC references, allocates and assigns stack slots
for the GC references, and then inserts spills and reloads. If this sounds
similar to register allocation, that's because it is. The important difference
is that the frontend performs this work only for GC references, not for the
majority of non-GC-reference values in the program. When a program does not use
any GC-managed objects, which is the vast majority of WebAssembly programs
today, no overhead is imposed.

Our liveness analysis flows backwards, from uses (which mark values live) to
definitions (which remove values from the live set) in the data-flow graph and
from successor blocks to predecessor blocks in the control-flow graph.

We compute two live sets for each block:

1. The live-in set, which is the set of values that are live when control enters
   the block.

2. The live-out set, which is the set of values that are live when control exits
   the block.

A block's live-out set is the union of its successors' live-in sets. A block's
live-in set is the set of values that are still live after the block's
instructions have been processed, where uses mark values live and definitions
remove them from the set.

```python
live_in(block) = union(live_out(s) for s in successors(block))

live_out(block) = live_in(block) + uses(block) - defs(block)
```

Whenever we update a block's live-in set, we must reprocess all of its
predecessors, because those predecessors' live-out sets depend on this block's
live-in set. Processing continues until the live sets stop changing and we've
reached a fixed-point. We implement this with the classic worklist approach.

Once we have the results of the liveness analysis in hand, we do a final pass
over the CLIF, assigning stack slots and inserting spills and reloads. This is
also implemented as a backwards pass. Whenever the pass finds a use of a GC
reference that is live across any safepoint, it allocates the reference's stack
slot if it doesn't already have one, and replaces the use with a load from that
stack slot. Upon reaching a safepoint, the pass adds user stack map entries for
each of the GC references that are live across the safepoint. Finally, when the
pass encounters a GC reference's definition, it appends a spill of the reference
to its associated stack slot to the definition. Then, knowing that the value
will never be seen again, since we are processing SSA values in backwards order,
the GC reference's stack slot is returned to a free list and made available for
any new GC references the pass has yet to encounter.

Astute readers may have noticed that replacing every use with a fresh reload may
result in many redundant loads. This is not a concern because, as previously
noted, our mid-end's alias analysis can already clean up and remove these
redundant loads. Separation of concerns between compiler passes lets us decrease
overall complexity.

[the `cranelift-frontend` crate]: https://docs.rs/cranelift-frontend/latest/cranelift_frontend/
[SSA]: https://en.wikipedia.org/wiki/Static_single-assignment_form
[liveness]: https://en.wikipedia.org/wiki/Live-variable_analysis

## Conclusion

We've moved stack map generation and safepoint spills and reloads from the end
of the compiler pipeline and into the frontend. It simplifies the compiler and
avoids misoptimizations and missed optimizations by relying on our existing
correctness invariants rather than imposing new ones to maintain. It also
unlocks efficient sandboxing of the GC heap using the same techniques we use for
WebAssembly's linear memories.

We're making steady progress implementing the WebAssembly garbage collection
proposal in Wasmtime. It is not complete or ready for general use yet, but it is
coming soon.

Want to start hacking on Wasmtime or Cranelift? [Check out our contributor
documentation!][contributing]

Thanks to [Trevor Elliott] for partnering with me on implementing this stack
maps overhaul and to [Chris Fallin] for design feedback, brainstorming, code
review, and providing feedback on an early draft of this blog post.

[contributing]: https://docs.wasmtime.dev/contributing.html
[Trevor Elliott]: https://elliottt.github.io/
[Chris Fallin]: https://www.cfallin.org/
