---
name: cpp-oop-style
description: >-
  High-quality C++ OOP coding style (archibate / parallel101 lineage) that
  overrides sloppy AI-default C++. Use this skill WHENEVER writing, editing,
  refactoring, or reviewing C++ code (.cpp / .h / .hpp / .cc / .cxx), designing
  C++ classes, interfaces, APIs, or libraries, or when the user mentions C++
  design, OOP, design patterns, dependency injection, RAII, or "clean / modern
  C++". Apply it even when the user does not explicitly ask for a style: the
  default way models write C++ leans on free functions, public mutable state,
  raw new/delete, sentinel return codes, and long loose parameter lists — this
  skill replaces all of that with abstract-class-or-data-class design,
  dependency injection, type-rich APIs, value-based error handling, and RAII
  ownership.
---

# archibate C++ OOP Style

A skill that makes you write C++ the way a senior systems engineer who loves
design patterns writes it — not the way an autocompleter does. When this skill
is loaded, it **overrides** your default C++ instincts.

## The one rule

> **"Abstract class, data class, or value type. Nothing else."**

Every type you introduce is one of these three kinds — never the muddy middle:

- **Abstract class** — *behavior only*. A pure-virtual interface with no data
  members of its own; any injected collaborators live in its concrete `…Impl`,
  not in the interface. Always has `virtual ~T() = default;`. This is the unit of
  *polymorphism and dependency injection*.
- **Data class** — *data only*. A plain `struct` with public fields, built with
  designated initializers. No business logic, no getters/setters wrapping plain
  fields. This is the unit of *value passing and configuration*.
- **Value / resource type** — a concrete, value-semantic type that either owns a
  resource (an RAII wrapper) or enforces one invariant (a strong type: `Money`,
  `EmailAddress`, a math `Vector3`, a C-handle wrapper). It has a small, total
  interface and behaves like a built-in — the *Regular* type. This is the one
  concrete-class-with-methods that earns its keep.

Reject the muddy middle that models reach for by default: a concrete class that
mixes private fields, a grab-bag of public methods, *and* a scatter of free
helper functions — neither a clean interface, nor plain data, nor a focused value
type. That shape is the single biggest tell of AI-slop C++.

So a concrete class with methods is allowed only when it is **(a)** the
implementation of an abstract class (`struct FooImpl final : Foo`, defined
in a `.cpp`, never a header), or **(b)** a value/resource type as above.
Everything else is behavior behind an interface, or data in a struct.

## What you are overriding

| AI-slop default | This skill |
|---|---|
| Free functions `dep1DoX()`, `dep2DoX()` | One abstract interface `Dep`, injected |
| Concrete class with public mutable fields + methods | Abstract class (behavior) **or** data struct (data) |
| `Dog dog; dog.doThing(globalThing);` | Inject the collaborator: `dog.doThing(dep)` |
| `void f(string n, int a, int p, int addr)` | `void f(FooConfig const &cfg)` (designated init) |
| `new T` / `delete` / `new T[]` | `make_unique` / `make_shared` / `vector<T>` |
| `int parseInt()` returning `-1` on failure | `optional<int> parseInt()` |
| `enum Mode` + `switch` dispatch | inject a strategy / functor, or a state class |
| `pair<bool, It>` / `tuple<...>` returns | named result struct |
| `const T&`, `const T*` | East const: `T const &`, `T const *` |

## Named anti-patterns (real smells this overrides)

These are the concrete shapes that mark sloppy or dated C++ — name them and
refuse them:

- **God-base interface** — one abstract class fusing *data and behavior*, with a
  pile of public mutable members (e.g. a node base every node both reads state
  from and overrides). Split it: behavior → interface, state → data struct.
- **Global object + free functions** — a global instance poked by a scatter of
  free helpers. Make it a class with a clear owner and inject it.
- **Stringly-typed API** — `setParam("mode", "fast")`, sockets/params keyed by
  string. Use `enum class`, strong types, and named fields so the compiler
  checks them. Relatedly, **fetch an abstract handle once** rather than re-passing
  a string key on every call: `auto *dev = api->getDevice("CD"); dev->play();`,
  not `api->playDevice("CD")` then `api->stopDevice("CD")`.
- **Sentinel returns** — `(size_t)-1`, `-1`, empty string, or null on failure.
  Use `optional` / `expected` or a result struct (see `references/error-handling.md`).

## The canonical shape

```cpp
// Dep.h — interface only. Pure virtual. Lives in a small header.
struct MethodConfig {
    Point position{};
    float size{};
};

struct Dep {
    virtual ~Dep() = default;
    virtual std::string someQuery() const = 0;
    virtual void someMethod(MethodConfig const &config) = 0;
};

// Animal.h
struct Animal {
    virtual ~Animal() = default;
    virtual void someInterface(Dep *dep) = 0;   // collaborator injected, not owned
};

// Dog.h — concrete impl, declared minimally, defined in .cpp
struct Dog final : Animal {
    void someInterface(Dep *dep) override;
private:
    int somePrivate{};
};

// Dog.cpp
void Dog::someInterface(Dep *dep) {
    auto answer = dep->someQuery();   // reuse, don't reimplement per concrete dep
    // ...
}

// callSite.cpp — the composition root wires concrete to abstract
auto dog = Dog{};
auto dep1 = std::make_unique<Dep1>(someOptions);
dog.someInterface(dep1.get());
```

## Class design

**Virtual functions are a backbone of this style — reach for them.** They do
*two* distinct jobs, and both are worth an interface:

1. **Dispatch / dependency injection** — one shared caller works across subtypes
   it doesn't know. Without it, every new subtype copy-pastes the shared logic
   and one requirement change means editing N files.

   ```cpp
   void feed(Animal *a) { puts("feeding"); a->speak(); puts("done"); }
   ```

2. **Implementation hiding** — the interface lives in the header, the concrete
   `…Impl` lives in the `.cpp`. This is worthwhile *even with a single
   implementation*: a compile firewall (member types and heavy/third-party
   headers stay out of your public header, callers don't recompile when the impl
   changes), a clean ABI boundary, and a ready test seam. (See
   "single-implementation interface" below.)

The only thing to avoid is the *empty* interface — a `virtual` that delivers
neither job: you already hold the concrete type, there is exactly one
implementation, and you gain no hiding, seam, or ABI benefit. That is pure
overhead. Everywhere a real seam exists — polymorphism **or** build/ABI/test —
prefer the interface.

**Escalate abstraction only as far as the duplication demands.** Lift a repeated
value to a variable, repeated logic to a function, a clump of arguments to a
struct, shared state-plus-behavior to a class, a fixed set of variants to an
`enum`, and an open set of behaviors to a `virtual` interface — in that order.
Don't jump to the interface when a function would do. The real cost of copy-paste
is not the typing — it is the typo you later make in one rarely-run branch.

**One interface, one responsibility.** Never mix concerns (e.g. IO *and*
computation) in one abstract class — it forces an N×M subclass explosion. Split
into independent interfaces and let a high-level function combine them:

```cpp
struct Inputer { virtual ~Inputer() = default; virtual std::optional<int> fetch() = 0; };
struct Reducer { virtual ~Reducer() = default; virtual int init() = 0; virtual int add(int, int) = 0; };
int reduce(Inputer *in, Reducer *r);   // 2+2 classes, unlimited combinations
```

**Template Method — public non-virtual wrapper, protected virtual `do_xxx`.**
The public method owns the contract and supplies ergonomic overloads; subclasses
override only the raw `do_xxx`. (As in `std::pmr::memory_resource`.)

```cpp
struct Converter {
    void process(std::string_view sv) { do_process(sv.data(), sv.size()); }
    void process(char const *s)       { do_process(s, std::strlen(s)); }
protected:
    virtual void do_process(char const *s, size_t n) = 0;
};
```

**Strategy vs Template Method — which to pick.** Many independent behaviors on one
object → *Strategy*: hold pointers to injected strategy interfaces (a `Character`
with separate `move` and `attack` strategies). A single behavior that needs the
object's own members → *Template Method*: the base *is* the strategy, the
`virtual` reads its own fields (a `Weapon` whose `attack` uses its `damage` /
`range`). One axis of variation that owns no state → functor; several axes, or
state-carrying behavior → strategy objects.

**Thin virtual core, fat non-virtual API.** Put only primitives behind `virtual`
(`raw_read`, `raw_write`, `raw_seek`); build the rich convenience API
(`getline`, `flush`) as non-virtual methods on top. Few virtuals, much reuse.

**Compose, don't multiply subclasses.**
- *Adapter*: wrap an interface, return the same interface, add one capability.
  Adapters compose orthogonally instead of `N×M` subclasses.
- *State as class*: encode states as classes implementing a `State` interface,
  not `enum + switch`. Adding a state touches no existing branch.
- *Component*: a `GameObject` holds `vector<unique_ptr<Component>>`. Use dynamic
  composition for behavior, **never multiple inheritance.**
- *CRTP*: auto-implement boilerplate virtuals (`clone`, `accept`) once in a
  `template <class D> struct Impl : Base` mixin instead of per subclass.
- *Visitor / double-dispatch*: when behavior depends on two types (or you'd
  otherwise write `getType()` / `isEatable()` and switch on it), use
  `accept`/`visit` so the compiler picks the overload — don't query a type tag.
- *Flyweight*: when many objects share identical heavy data (a texture, a lookup
  table), hoist it into a separate type held by a `shared_ptr`; keep only the
  per-instance data (position, velocity) local. 1000 bullets, one shared sprite —
  not 1000 texture copies. The owner's method just *forwards* to the shared object
  (`sprite->draw(position)`) — that delegation is the *proxy* idiom.

**Interface/implementation split (header hygiene).** Put the pure-virtual
interface in a small header; keep the concrete `…Impl final` entirely in the
`.cpp`. Hand back the interface through a **factory**, so callers never see — or
`#include` — the concrete type:

```cpp
// Foo.h
struct Foo { virtual ~Foo() = default; virtual void run() = 0; };
std::unique_ptr<Foo> createFoo(FooConfig const &cfg);   // factory returns the interface
```

This is also how you select backends: define the factory once per backend
directory and let the build system link exactly one. Swapping an implementation
(real vendor SDK ↔ a fake for tests/replay) becomes a build-variable change, not
a code change — the test double is just another implementation behind the seam.

**A single-implementation interface is justified — for hiding, not dispatch.**
Even when only one `…Impl` will ever exist, putting it behind a pure-virtual
interface earns its keep: a **compile firewall** (callers don't `#include` the
implementation's heavy or third-party headers, and don't recompile when it
changes), **hiding** a proprietary or volatile implementation out of public
headers, a stable **ABI boundary** across a library edge, and a ready **test
seam** (drop in a fake without touching callers). This is the deliberate
exception to "don't over-abstract": the payoff is the build/ABI/test boundary,
not polymorphism. (If you want only the compile firewall and never a second
implementation or a fake, classic PIMPL — a `unique_ptr<Impl>` member, with the
destructor declared in the header and `= default`-ed in the `.cpp` — gives the
same hiding without virtuals. Reach for the interface when you also want the test
or backend seam.)

**Command/callback pairs.** For a subsystem with inversion of control, define
two interfaces: an `Api` (methods you call in) and an `Spi` (methods called back
to you). The owner implements the `Spi` and holds the `Api`; wire with
`api->setSpi(this)`.

**Singleton — encapsulate the one instance, never a bare global.** For a genuinely
process-wide subsystem, hide the constructor, delete copy/move, and hand out the
instance through one accessor — define it in the `.cpp` like any other method:

```cpp
// Game.h
struct Game {
    void update();
    static Game &instance();        // the sole accessor
    Game(Game &&) = delete;
private:
    Game();
};
// Game.cpp
Game &Game::instance() { static Game inst; return inst; }   // lazy, thread-safe (C++11)
```

A header form — a header-only util, or the generic
`template <class T> T &singleton() { static T inst; return inst; }` — must be
`inline`, not `static`, and gets a separate copy per Windows DLL. A singleton is
still global state: prefer injection through the composition root, and reserve it
for subsystems that are truly one-per-process.

## Dependency injection

- **Inject abstractions into high-level functions, never concrete types.** The
  caller chooses the implementation; the callee depends only on the interface.
- **Inject a factory, not a product, when the callee must create many.** Give a
  `Gun` whose `virtual unique_ptr<Bullet> shoot()` the callee calls repeatedly —
  not a single pre-made `Bullet`.
- **A single composition root does all the wiring.** One `main.cpp` (or one
  setup function) calls the factories and injects via constructor args or
  setters. No globals reach across modules; production vs test differ only by
  which factories the root calls.
- **Collaborators are borrowed, not owned.** Pass dependencies as raw interface
  pointers (`Dep *`) or references; the injectee never owns its collaborators.
  Ownership lives in the composition root. (See `references/ownership-lifetime.md`.)

## Type-rich data classes

Make illegal states unrepresentable and make call sites self-documenting. The
compiler is your reviewer.

- **Bundle ≥3 related params into a named struct with designated init.** Names
  beat positions; adding a defaulted field breaks zero callers.
  `void foo(FooConfig const &cfg);` then `foo({.name = "x", .age = 24});`
- **Return a named struct, never `pair`/`tuple`.** `result.success` not
  `result.first`.
- **`optional<T>` for nullable returns** — never a sentinel like `-1` or a
  nullable raw pointer. (Error handling: `references/error-handling.md`.)
- **Don't default new fields to `optional<T>`**. Reserve it for data that
  is genuinely sometimes-absent; an always-present field wrapped in `optional`
  only sprays null-checks and weakens the invariant. For a real either/or,
  model it with `std::variant`, dependency injection or distinct types.
- **`enum class` for flags/states** — blocks implicit `int` conversion and
  argument-order bugs.
- **Strong types for primitives that should not interconvert.** Wrap in a
  one-member struct or `enum class FileHandle : int {}` so `read(fd, …)` can't
  silently take the wrong `int`.
- **`std::span<T>` / `string_view` for non-owning buffer/string params** —
  length travels with the data, no `ptr,len` mismatch.
- **`std::chrono` for time**, never raw integers — `time_point + time_point`
  becomes a compile error instead of a 54-year sleep.
- **Plain data is a `struct` with public fields**, constructed by aggregate
  initialization — `Foo{a, b}` or designated `Foo{.x = a, .y = b}` — with no
  hand-written constructor and no encapsulation ceremony.
- **Getters/setters earn their place only to guard an invariant** — inside a
  value/resource type. Independent fields stay public (a `Point`'s `.x`/`.y` need
  no `getX`/`setX`); fields coupled by an invariant hide behind hook methods with
  mutation banned (a `vector` exposes `size()`/`resize()` and a read-only `data()`
  because resizing must reallocate).
- **Name constructors by intent — use named static factories** when variants
  differ in meaning, not signature (`Cake::makeChoco()` / `Cake::makeMoca()`,
  not `Cake(double)` vs `Cake(int)`).

## Naming & layout

- **No `m_` prefix, no trailing-underscore on members.** Members are bare names.
- **Trailing underscore only on a ctor/setter param that shadows a member:**
  `void setX(double x_) { x = x_; }`.
- Types `PascalCase`; methods & members `camelCase`; constants `kPascalCase`;
  `enum class : uint8_t` with explicit underlying type.
- Predicate methods read as intent: `shouldRetry()`, `canFlush()`.
- **One concept per header**, kept small. `#pragma once`, never include guards.
- **Forward-declare in headers, `#include` in the `.cpp`** to cut compile
  coupling.
- **East const everywhere:** `T const &`, `T const *` — const binds to what
  precedes it, which reads consistently right-to-left.
- **Always `struct`, never the `class` keyword** — even for encapsulated types.
  Open an explicit `private:` / `protected:` section when you need encapsulation
  (`struct Game { void play(); private: Game(); };`). The keyword carries nothing
  the access labels don't, and defaulting to `struct` keeps each type's public
  surface first and visible.
- In headers, share definitions with `inline`, never `static` (which silently
  duplicates per translation unit).

## The `auto` idiom (AAA)

- **Almost Always Auto:** `auto x = Type(...)`, never `Type x(...)`. Forces
  initialization and survives return-type changes.
- **Explicit cast over implicit:** `auto i = size_t(3);` not `auto i = 3;`.
- **In range-for: `auto const &` to read, `auto &` to modify.** Never bare
  `auto` — it copies. For maps: `for (auto const &[k, v] : m)`.
- C++20 `auto` parameters are implicit templates: `auto square(auto const &x)`.

## Compiler hygiene

Let the compiler enforce the style — most rules above become hard errors instead
of review comments. Build with:

```
-Wall -Wextra -Weffc++
-Werror=return-type -Werror=uninitialized
-Werror=suggest-override          # every override marked `override`
-Wzero-as-null-pointer-constant   # `nullptr`, never `0` / `NULL`
-Wold-style-cast                  # named casts only, never `(T)x`
-Werror=vla                       # `std::vector` / `std::array`, never VLAs
-Wnon-virtual-dtor -Wdelete-non-virtual-dtor
-Wconversion -Wsign-compare       # no silent narrowing
-Werror=unused-result             # don't ignore a [[nodiscard]] result
```

Add `-D_GLIBCXX_DEBUG` in development builds to catch iterator/bounds misuse at
runtime (every linked translation unit must match). And decompose programs into
named functions — don't pile logic directly into `main`.

## Pragmatics — when to dial it back

This is a style for code that must live and change. Don't weaponize it:

- **Don't pre-abstract.** A one-off internal helper does not need an interface.
  Add the *dispatch* seam when a second implementation actually appears (or is
  imminent). This is about polymorphism only — a single-implementation interface
  for a compile firewall, ABI boundary, or test seam is still justified (see
  "single-implementation interface" under Class design).
- **Hot paths prefer a template `Func` over `std::function`/virtual** for
  zero-overhead dispatch. (See `references/functors-callbacks.md`.) In a *measured*
  inner loop it is even fine to drop OOP entirely — raw intrinsics, free
  functions, value-semantic SIMD wrappers — provided every such kernel is paired
  with a reference-checked test and a benchmark. Performance you can't measure is
  not a reason to abandon the style.
- **`shared_ptr` vs `unique_ptr`:** prefer a single clear owner (`unique_ptr`,
  or a process-lifetime raw owning pointer for singletons); reach for
  `shared_ptr` only when ownership is genuinely shared.

## Exemplar libraries — good API to imitate

When unsure what a well-designed API looks like, study these. Each is a clean
demonstration of one principle:

| Library | Principle it demonstrates |
|---|---|
| **fmt** / `std::format` | type-rich, compile-time-checked format API; no unsafe varargs |
| **ranges-v3** / `std::ranges` | composable lazy adaptors over concrete containers |
| **magic_enum** | type-safe enum reflection without macros or codegen |
| **nlohmann-json** | RAII ownership and type-deduced `get<T>()` |
| **tl::expected** / `std::expected` | value-based error propagation |
| **structopt** | struct-as-API — a plain data class drives the interface |

## What not to imitate

Fine to *use*; wrong to *copy the style of*:

- **poco** — raw `new`/`delete` throughout, Java-style OOP, no value semantics.
- **rapidjson / jsoncpp** — SAX template maze / weakly-typed `Value` tree.
- **tinyxml2, legacy OpenCV C API, stb** — raw-pointer, pre-RAII style.

Qt is a different case: it is *excellent* **classic** OOP — object-tree ownership,
signals/slots, `QObject` parenting. Its `m_` members, raw `new`, and
parent-owns-child idioms are deliberate and correct *for that paradigm*. Keep
them inside Qt code; just don't carry them into value-semantic modern C++, where
this skill's conventions apply.

## References

Load these when the task touches their area:

- `references/ownership-lifetime.md` — no raw `new`, smart pointers vs `vector`,
  references vs pointers, RAII for C resources, the rule of five, dangling
  temporaries.
- `references/functors-callbacks.md` — template `Func` vs `std::function`,
  lambdas over `std::bind`, capture lifetime, closures as structs.
- `references/error-handling.md` — recoverable vs unrecoverable, `optional` /
  `expected`, `[[noreturn]]`, the result-struct / error-sink / bool+log fallbacks.
- `references/wrapping-c-resources.md` — RAII wrappers for opaque C handles:
  move-only handle template, `error_category`, check-on-assign with
  `source_location`, builders, scope-guard binds.

Source material (the "why" behind these rules), all by the same author:
<https://github.com/parallel101/cppguidebook> (`design_virtual.md`,
`no_more_new.md`, `type_rich_api.md`, `design_functor.md`, `design_gamedev.md`,
`error_code.md`, `cpp_lifetime.md`, `lambda.md`, `functions.md`, `auto.md`,
`platform.md`) and the lecture repo <https://github.com/parallel101/course>
(the `design`, `stl`, and `cmake` sessions — singleton, get/set, type erasure,
move semantics). Real code worth reading: <https://github.com/archibate/co_async>
(design idioms) and parallel101/opengltutor's `check_gl.hpp` (the cleanest RAII
C-handle wrapper). Further reading: cppreference.com, hackingcpp.com,
learncpp.com; godbolt.org / cppinsights.io / quick-bench.com to see codegen and
cost.
