---
name: cpp-coding-standards
description: C++ coding standards reference. Use only when the user explicitly invokes /cpp-coding-standards or explicitly asks to use the cpp-coding-standards skill by name.
origin: ECC
---

# C++ Coding Standards

Practical C++ coding standards based on the C++ Core Guidelines, adapted for projects using `.clang-format` and `.clang-tidy` as the source of truth.

## Tooling & Compatibility First

### Tooling Is Source of Truth

| Rule | Summary |
|---|---|
| **T0.1** | Prefer project `.clang-format` and `.clang-tidy`; otherwise use `~/.claude/formatters/cpp/`. |
| **T0.2** | Run `clang-format` for layout and `clang-tidy` for naming/static checks when code exists in local files. |
| **T0.3** | Treat examples in this skill as intent examples; tooling decides formatting and naming details. |
| **T0.4** | Avoid applying these rules directly to third-party, generated, vendored, build, or system headers. |

### Language Standard Compatibility

Infer the active standard from `compile_commands.json`, build files, compiler flags, or the user's instruction before choosing features.

| Need | C++20+ | C++17 | C++14 | C++11 |
|---|---|---|---|---|
| Template constraints | Concepts / `requires` | Type traits / `enable_if` | Type traits / `enable_if` | Type traits / `enable_if` |
| String views | `std::string_view` | `std::string_view` | `const std::string&` or project polyfill | `const std::string&` or project polyfill |
| Multiple mutex locking | `std::scoped_lock` | `std::scoped_lock` | `std::lock` + `adopt_lock` guards | `std::lock` + `adopt_lock` guards |
| Nested namespace syntax | `namespace a::b` | `namespace a::b` | Traditional nested namespaces | Traditional nested namespaces |
| Ownership factory | `std::make_unique` | `std::make_unique` | `std::make_unique` | Project helper, otherwise explicit `std::unique_ptr<T>(new T(...))` |
| Compile-time branching | `if constexpr` | `if constexpr` | Tag dispatch / overloads | Tag dispatch / overloads |

## Cross-Cutting Principles

| Principle | Summary |
|---|---|
| **RAII everywhere** | Bind resource lifetime to object lifetime. |
| **Tool-aligned style** | Let `.clang-format` and `.clang-tidy` define style and naming. |
| **Type safety** | Use strong, precise types instead of ambiguous primitive parameters. |
| **Explicit ownership** | Values and smart pointers own; raw pointers and references observe. |
| **Useful immutability** | Prefer immutable local state when it improves clarity; avoid churn from mechanical `const`. |
| **Standard awareness** | Do not introduce C++17/20 features into C++11/14 projects. |
| **Boundary discipline** | Validate external input and system API failures at file, network, IPC, CLI, and serialization boundaries. |
| **Compatibility preservation** | Do not change public ABI/API, serialized layouts, or wire formats accidentally. |

## Naming & Tooling (NL.*, Tooling)

### Key Rules

| Rule | Summary |
|---|---|
| **NL.8** | Use a consistent naming style, enforced by active `.clang-tidy`. |
| **NL.9** | Use ALL_CAPS only for macros. |
| **NL.10** | Use the configured project convention, not ad hoc local style. |
| **T0.2** | Run `clang-format` and `clang-tidy` before final output when code exists in local files. |

### Default Naming Convention

| Entity | Default style |
|---|---|
| Classes, structs, enum types | `UpperCamelCase` |
| Functions, member functions | `UpperCamelCase` |
| Variables, local variables, parameters | `lower_snake_case` |
| Data members | `lower_snake_case_` |
| Namespaces | `lower_snake_case` |
| Global constants | `kUpperCamelCase` |
| Enum constants | `kUpperCamelCase` |
| Local `const` / `constexpr` temporaries | `lower_snake_case` |
| Macros | `UPPER_CASE` |

### DO

```cpp
namespace task_system
{
    enum class TaskState
    {
        kPending,
        kRunning,
        kFinished
    };

    class TaskManager
    {
    public:
        bool StartTask(const std::string& task_id);

    private:
        std::unordered_map<std::string, TaskState> task_map_;
    };
} // namespace task_system
```

### DON'T

```cpp
namespace TaskSystem
{
    enum class task_state
    {
        pending,
        running,
        finished
    };

    class task_manager
    {
    public:
        bool start_task(const std::string& task_id);
    };
} // namespace TaskSystem
```

## Philosophy & Interfaces (P.*, I.*)

### Key Rules

| Rule | Summary |
|---|---|
| **P.1** | Express ideas directly in code. |
| **P.3** | Express intent through names, types, and ownership. |
| **P.4** | Prefer static type safety. |
| **P.5** | Prefer compile-time checking to run-time checking. |
| **P.8** | Do not leak resources. |
| **I.1** | Make interfaces explicit. |
| **I.4** | Make interfaces precisely and strongly typed. |
| **I.11** | Never transfer ownership by raw pointer or reference. |
| **I.23** | Keep function argument lists short. |

### DO

```cpp
struct Temperature
{
    double kelvin;
};

Temperature Boil(const Temperature& water);
```

### DON'T

```cpp
double Boil(double* temp);

int g_counter = 0;
```

## Functions (F.*)

### Key Rules

| Rule | Summary |
|---|---|
| **F.1** | Package meaningful operations as carefully named functions. |
| **F.2** | A function should perform one logical operation. |
| **F.3** | Keep functions short and simple. |
| **F.4** | Use `constexpr` when the active standard supports the intended compile-time work. |
| **F.6** | Use `noexcept` only when failure cannot happen or the contract requires it. |
| **F.16** | Pass cheap input values by value; pass expensive read-only inputs by `const&`. |
| **F.20** | Prefer return values to output parameters. |
| **F.21** | Return a named struct for multiple output values. |
| **F.43** | Never return a pointer or reference to a local object. |

### DO

```cpp
struct ParseResult
{
    std::string token;
    int position;
};

ParseResult Parse(const std::string& input);
```

### DON'T

```cpp
void Parse(const std::string& input, std::string& token, int& position);

const std::string& MakeName()
{
    const std::string name{"task"};
    return name;
}
```

### Anti-Patterns

- Returning `T&&` from ordinary functions.
- Returning `const T` by value.
- Using C-style variadics in new C++ APIs.
- Adding `noexcept` speculatively to functions that can fail.

## Classes & Class Hierarchies (C.*)

### Key Rules

| Rule | Summary |
|---|---|
| **C.2** | Use `class` for protected invariants; use `struct` for passive data. |
| **C.9** | Minimize exposure of members unless the type is a DTO/POD. |
| **C.20** | Prefer Rule of Zero. |
| **C.21** | If defining or deleting one special member, consider the full copy/move/destructor set. |
| **C.35** | Base class destructor is public virtual or protected non-virtual. |
| **C.41** | Constructors leave objects fully initialized. |
| **C.46** | Mark single-argument constructors `explicit`. |
| **C.67** | Suppress unsafe public copy/move in polymorphic base classes. |
| **C.128** | Use exactly one of `virtual`, `override`, or `final` on each virtual declaration site. |

### DO

```cpp
class Buffer
{
public:
    explicit Buffer(std::size_t size) : data_(std::make_unique<char[]>(size)), size_(size) {}

    char* Data()
    {
        return data_.get();
    }

    std::size_t Size() const
    {
        return size_;
    }

private:
    std::unique_ptr<char[]> data_;
    std::size_t size_;
};
```

### DON'T

```cpp
class Buffer
{
public:
    Buffer(std::size_t size)
    {
        data_ = new char[size];
    }

    ~Buffer()
    {
        delete[] data_;
    }

private:
    char* data_;
};
```

### Anti-Patterns

- Calling virtual functions in constructors or destructors.
- Using `memset` or `memcpy` on non-trivial types.
- Different default arguments between virtual functions and overriders.
- Data members that are `const` or references when they unnecessarily block copying/moving.

## Resource Management (R.*)

### Key Rules

| Rule | Summary |
|---|---|
| **R.1** | Manage resources automatically using RAII. |
| **R.3** | A raw pointer is non-owning unless clearly documented otherwise. |
| **R.5** | Prefer scoped objects; do not heap-allocate unnecessarily. |
| **R.10** | Avoid `malloc()` and `free()` in C++ code. |
| **R.11** | Avoid explicit `new` and `delete`. |
| **R.20** | Use smart pointers to represent ownership. |
| **R.21** | Prefer `unique_ptr` over `shared_ptr` unless ownership is shared. |
| **Boundary** | Wrap file descriptors, handles, sockets, locks, and similar resources in RAII types. |

### DO

```cpp
class FileHandle
{
public:
    explicit FileHandle(const std::string& path) : handle_(std::fopen(path.c_str(), "r"))
    {
        if (handle_ == nullptr)
        {
            throw std::runtime_error("failed to open file");
        }
    }

    ~FileHandle()
    {
        if (handle_ != nullptr)
        {
            std::fclose(handle_);
        }
    }

    FileHandle(const FileHandle&) = delete;
    FileHandle& operator=(const FileHandle&) = delete;

private:
    std::FILE* handle_;
};
```

### DON'T

```cpp
void ReadFile(const std::string& path)
{
    std::FILE* handle = std::fopen(path.c_str(), "r");
    Process(handle);
    std::fclose(handle);
}
```

### C++11 Note

Use `std::unique_ptr<T>(new T(...))` only when the project has no `make_unique` helper.

## Expressions & Statements (ES.*)

### Key Rules

| Rule | Summary |
|---|---|
| **ES.5** | Keep scopes small. |
| **ES.20** | Initialize objects at declaration. |
| **ES.23** | Prefer brace initialization when it remains readable. |
| **ES.25** | Prefer `const` when it improves clarity; avoid mechanical churn. |
| **ES.45** | Name domain-meaningful constants; allow obvious `0`, `1`, and test literals. |
| **ES.46** | Avoid narrowing conversions. |
| **ES.47** | Use `nullptr`, not `0` or `NULL`. |
| **ES.48** | Avoid C-style casts. |
| **ES.50** | Do not cast away `const`. |

### DO

```cpp
const int retry_count{3};
const std::string request_body{"payload"};
const auto buffer_size = static_cast<std::size_t>(payload_size);
```

### DON'T

```cpp
int retry_count;
char* buffer = NULL;
const auto buffer_size = (std::size_t) payload_size;
```

## Error Handling (E.*)

### Key Rules

| Rule | Summary |
|---|---|
| **E.1** | Follow the project's error-handling strategy. |
| **E.2** | In exception-enabled code, throw when a function cannot perform its task. |
| **E.6** | Use RAII to prevent leaks on error paths. |
| **E.12** | Use `noexcept` for destructors, deallocation, swaps, or impossible-failure contracts. |
| **E.14** | Prefer purpose-built exception types. |
| **E.15** | Throw by value and catch by reference. |
| **E.17** | Do not catch every exception at every layer. |
| **Boundary** | Convert system API failures into the project's error model. |

### DO

```cpp
class AppError : public std::runtime_error
{
public:
    using std::runtime_error::runtime_error;
};

void FetchData(const std::string& url)
{
    throw AppError("connection refused");
}
```

### DON'T

```cpp
void FetchData(const std::string& url)
{
    try
    {
        Connect(url);
    }
    catch (...)
    {
    }
}
```

### No-Exception Projects

Use status codes, `std::optional`, project `Expected`/`Result` types, or callback error channels consistently when exceptions are disabled.

## Constants & Immutability (Con.*)

### Key Rules

| Rule | Summary |
|---|---|
| **Con.1** | Prefer immutable values when that clarifies intent. |
| **Con.2** | Mark member functions `const` when they do not mutate observable state. |
| **Con.3** | Pass read-only pointer/reference parameters as pointers/references to `const`. |
| **Con.4** | Use `const` for values that do not change after initialization. |
| **Con.5** | Use `constexpr` for compile-time values supported by the active standard. |
| **Naming** | `k` prefix is for global constants and enum constants, not local constants. |

### DO

```cpp
constexpr int kMaxPacketSize{4096};

void SendPacket(const std::string& payload)
{
    const int retry_count{3};
    const std::size_t payload_size{payload.size()};
}
```

### DON'T

```cpp
void SendPacket(const std::string& payload)
{
    const int kRetryCount{3};
    int payload_size = payload.size();
}
```

## Concurrency & Parallelism (CP.*)

### Key Rules

| Rule | Summary |
|---|---|
| **CP.2** | Avoid data races. |
| **CP.3** | Minimize shared writable data. |
| **CP.4** | Think in tasks rather than raw threads. |
| **CP.8** | Do not use `volatile` for synchronization. |
| **CP.20** | Use RAII locks. |
| **CP.21** | Use standard deadlock-avoidance patterns for multiple mutexes. |
| **CP.22** | Do not call unknown code while holding a lock. |
| **CP.42** | Wait on condition variables with predicates. |
| **CP.44** | Name lock objects. |
| **Async** | Give threads, futures, callbacks, and async tasks clear ownership and shutdown paths. |

### DO

```cpp
class ThreadSafeQueue
{
public:
    void Push(int value)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        queue_.push(value);
        cv_.notify_one();
    }

    int Pop()
    {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this] { return !queue_.empty(); });

        const int value = queue_.front();
        queue_.pop();
        return value;
    }

private:
    std::mutex mutex_;
    std::condition_variable cv_;
    std::queue<int> queue_;
};
```

### DON'T

```cpp
void RunCallback(const Callback& callback)
{
    std::lock_guard<std::mutex> lock(mutex_);
    callback();
}
```

### Compatibility Notes

- C++17+: use `std::scoped_lock` for multiple mutexes.
- C++11/14: use `std::lock` plus `std::adopt_lock` guards.
- Avoid capturing references in callbacks that may outlive the current scope; use value capture, `weak_ptr`, or cancellation tokens.

## Templates & Generic Programming (T.*)

### Key Rules

| Rule | Summary |
|---|---|
| **T.1** | Use templates to raise abstraction when it simplifies code. |
| **T.2** | Use templates to express algorithms over many argument types. |
| **T.10** | Constrain visible templates when constraints matter. |
| **T.43** | Prefer `using` over `typedef`. |
| **T.120** | Avoid template metaprogramming when simpler code is enough. |
| **T.144** | Prefer overloads over function-template specializations. |

### DO

```cpp
template <typename T> typename std::enable_if<std::is_integral<T>::value, T>::type Gcd(T a, T b)
{
    while (b != 0)
    {
        const T next = a % b;
        a = b;
        b = next;
    }

    return a;
}
```

### DON'T

```cpp
template <typename T> T Gcd(T a, T b)
{
    return a;
}
```

### Compatibility Notes

- C++20+: prefer concepts for visible template constraints.
- C++11/14/17: use type traits, overloads, tag dispatch, or `enable_if`.

## Standard Library (SL.*)

### Key Rules

| Rule | Summary |
|---|---|
| **SL.1** | Use libraries wherever possible. |
| **SL.2** | Prefer the standard library to custom code. |
| **SL.con.1** | Prefer `std::array` or `std::vector` over C arrays. |
| **SL.con.2** | Prefer `std::vector` by default for dynamic sequences. |
| **SL.str.1** | Use `std::string` to own character sequences. |
| **SL.str.2** | Use `std::string_view` only when the active standard supports it. |
| **SL.io.50** | Use `\n` instead of `std::endl` unless flushing is needed. |

### DO

```cpp
std::string BuildGreeting(const std::string& name)
{
    return "Hello, " + name + "!";
}

std::cout << "result: " << value << '\n';
```

### DON'T

```cpp
std::cout << "result: " << value << std::endl;
```

## Enumerations (Enum.*)

### Key Rules

| Rule | Summary |
|---|---|
| **Enum.1** | Prefer enumerations over macros for related named values. |
| **Enum.3** | Prefer `enum class` over plain `enum`. |
| **Enum.5** | Do not use ALL_CAPS for enumerators. |
| **Enum.6** | Avoid unnamed enumerations. |
| **Naming** | Follow `.clang-tidy`; default enum constants use `kUpperCamelCase`. |

### DO

```cpp
enum class LogLevel
{
    kDebug,
    kInfo,
    kWarning,
    kError
};
```

### DON'T

```cpp
enum
{
    DEBUG,
    INFO,
    WARNING,
    ERROR
};
```

## Source Files & Headers (SF.*)

### Key Rules

| Rule | Summary |
|---|---|
| **SF.1** | Use `.cpp` for implementation files and project-standard extensions for headers. |
| **SF.7** | Do not write `using namespace` at global scope in headers. |
| **SF.8** | Use include guards or `#pragma once` according to project style. |
| **SF.10** | Avoid header dependency on include order. |
| **SF.11** | Headers should be self-contained. |
| **Boundary** | Keep platform-specific code behind narrow wrappers. |
| **Compatibility** | Preserve public ABI/API, serialized layouts, and wire formats unless change is requested. |

### DO

```cpp
#ifndef PROJECT_TASK_MANAGER_H_
#define PROJECT_TASK_MANAGER_H_

#include <memory>
#include <string>

namespace task_system
{
    class TaskManager
    {
    public:
        explicit TaskManager(std::string name);
        std::string Name() const;

    private:
        std::string name_;
    };
} // namespace task_system

#endif
```

### DON'T

```cpp
using namespace std;

class TaskManager
{
public:
    string Name() const;
};
```

## Performance (Per.*)

### Key Rules

| Rule | Summary |
|---|---|
| **Per.1** | Do not optimize without reason. |
| **Per.2** | Do not optimize prematurely. |
| **Per.6** | Do not make performance claims without measurements. |
| **Per.7** | Design to enable optimization. |
| **Per.10** | Rely on the static type system. |
| **Per.11** | Move computation from run time to compile time when it is simple and supported. |
| **Per.19** | Access memory predictably in hot paths. |

### DO

```cpp
std::vector<Point> points;
points.reserve(point_count);
```

### DON'T

```cpp
std::vector<std::unique_ptr<Point>> points;
```

## Security & External Boundaries

### Key Rules

| Rule | Summary |
|---|---|
| **Input** | Validate file, network, IPC, CLI, and serialization inputs at boundaries. |
| **System API** | Check return values and convert failures into the project error model. |
| **Binary data** | Define version, endian, size, and alignment explicitly. |
| **Object representation** | Do not `memcpy` non-trivial C++ objects. |
| **Logging** | Include useful context without leaking sensitive data. |

### DO

```cpp
bool IsValidPayloadSize(std::size_t payload_size, std::size_t max_payload_size)
{
    return payload_size <= max_payload_size;
}
```

### DON'T

```cpp
Record record;
std::memcpy(&record, buffer, sizeof(record));
```

## Quick Reference Checklist

Before marking C++ work complete:

- [ ] Active `.clang-format` and `.clang-tidy` were run, or the reason they could not run is stated.
- [ ] Code uses only features supported by the project's C++ standard.
- [ ] Naming follows active `.clang-tidy` conventions.
- [ ] No ownership is transferred through raw pointers or references.
- [ ] Constructors leave objects fully initialized.
- [ ] Resource-owning types use RAII and have clear copy/move behavior.
- [ ] Public headers are self-contained and avoid global `using namespace`.
- [ ] External input is validated at file, network, IPC, CLI, and serialization boundaries.
- [ ] System API failures are checked and converted into the project's error model.
- [ ] Concurrency code has clear lifetime, cancellation, and locking behavior.
- [ ] Public ABI/API, serialized data, and wire formats are not changed accidentally.
- [ ] Performance claims are backed by measurements.
