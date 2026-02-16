# Russula Architecture Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-02-16

## Table of Contents

1. [Overview](#overview)
2. [Component Architecture](#component-architecture)
3. [Data Flow Architecture](#data-flow-architecture)
4. [State Management Model](#state-management-model)
5. [Configuration Hierarchy](#configuration-hierarchy)
6. [Context Management](#context-management)
7. [Error Propagation](#error-propagation)
8. [Lifecycle](#lifecycle)

## Overview

Russula is a Ruby library for structured generative programming, enabling type-safe, validated interactions with Large Language Models (LLMs). The architecture follows a layered design pattern with clear separation of concerns:

- **User Interface Layer**: Generative method DSL and Session API
- **Orchestration Layer**: Session management, validation strategies
- **Backend Layer**: LLM provider abstraction
- **Domain Layer**: Constraints, type system, context

### Design Principles

1. **Separation of Concerns**: Backend integration, validation logic, and user API are independent
2. **Type Safety**: All LLM outputs are type-checked and coerced
3. **Validation-First**: Every generation is subject to constraint validation
4. **Stateful Sessions**: Conversation context is maintained and accessible
5. **Backend Agnostic**: LLM providers are abstracted behind a common interface

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User Code                            │
│  ┌────────────────────┐         ┌─────────────────────┐    │
│  │ Generative Methods │         │ Session.instruct()  │    │
│  │   (DSL Mixin)      │         │     (Direct API)    │    │
│  └─────────┬──────────┘         └──────────┬──────────┘    │
└────────────┼─────────────────────────────────┼──────────────┘
             │                                 │
             └────────────┬────────────────────┘
                          │
              ┌───────────▼──────────┐
              │   Session Instance   │
              │  ┌─────────────────┐ │
              │  │  Configuration  │ │
              │  │  (push/pop)     │ │
              │  └─────────────────┘ │
              │  ┌─────────────────┐ │
              │  │     Context     │ │
              │  │  (msg history)  │ │
              │  └─────────────────┘ │
              └───────────┬──────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   ┌────▼────┐      ┌─────▼──────┐   ┌─────▼──────┐
   │ Backend │      │ Constraint │   │  Strategy  │
   │         │      │   System   │   │ (Sampling) │
   └────┬────┘      └─────┬──────┘   └─────┬──────┘
        │                 │                 │
        │    ┌────────────▼────────────┐    │
        │    │   Validation Engine     │    │
        │    │  ┌──────────────────┐   │    │
        │    │  │  Requirement     │   │    │
        │    │  │  Check           │   │    │
        │    │  │  TypeConstraint  │   │    │
        │    │  └──────────────────┘   │    │
        │    └────────────┬────────────┘    │
        │                 │                 │
        └─────────────────┼─────────────────┘
                          │
                   ┌──────▼──────┐
                   │ ModelOutput │
                   │   or        │
                   │SamplingResult│
                   └─────────────┘
```

### Core Components

#### 1. Session
- **Purpose**: Orchestrates all generative operations
- **Responsibilities**:
  - Manages Backend instance
  - Maintains conversation Context
  - Handles configuration stack (push/pop)
  - Executes instruct-validate-repair loop
  - Renders ERB templates
- **State**: Backend, Context, options stack

#### 2. Backend
- **Purpose**: Abstract interface to LLM providers
- **Responsibilities**:
  - Generate completions from messages
  - Translate errors to Russula exceptions
  - Apply provider-specific options
- **Implementations**: OpenAI (MVP), Anthropic (future), Ollama (future)

#### 3. Context
- **Purpose**: Maintain conversation history
- **Responsibilities**:
  - Store message sequence (role + content)
  - Provide message history for context-aware validation
- **State**: Array of message hashes

#### 4. Constraint System
- **Purpose**: Define and validate generation requirements
- **Components**:
  - **Requirement**: Included in prompt + validated
  - **Check**: Validated only (not in prompt)
  - **TypeConstraint**: Enforce return type contracts
- **Responsibilities**:
  - Validate outputs against criteria
  - Use LLM-as-a-judge when no custom validator
  - Coerce types when possible

#### 5. Validation Strategy
- **Purpose**: Control validation retry logic
- **Implementations**: RejectionSamplingStrategy
- **Responsibilities**:
  - Execute generation loop
  - Apply constraints
  - Manage retry budget
  - Return detailed sampling results

#### 6. Generative Mixin
- **Purpose**: DSL for defining LLM-powered methods
- **Responsibilities**:
  - Capture method metadata (return type, docstring)
  - Inject session parameter
  - Wrap method with type validation
  - Store metadata in class-level registry

## Data Flow Architecture

### Basic Generation Flow

```
1. User calls session.instruct(prompt, requirements: [...])
       │
       ▼
2. Session renders ERB template with user_variables
       │
       ▼
3. Session constructs prompt from:
   - Rendered template
   - Requirement descriptions (if include_in_prompt)
       │
       ▼
4. Session invokes Strategy.sample() with constraints
       │
       ▼
5. Strategy Loop:
   ┌─────────────────────────────────┐
   │ a. Generate via Backend         │
   │ b. Validate Requirements        │
   │ c. Validate Checks              │
   │ d. If all pass: return success  │
   │ e. Else: retry (if budget left) │
   └─────────────────────────────────┘
       │
       ▼
6. Return ModelOutput or raise ValidationError
```

### Generative Method Flow

```
1. User calls instance.method_name(session, **args)
       │
       ▼
2. Generative wrapper intercepts call
       │
       ▼
3. Wrapper renders docstring with ERB using args
       │
       ▼
4. Wrapper calls session.instruct(rendered_docstring)
       │
       ▼
5. (Same as Basic Generation Flow above)
       │
       ▼
6. Wrapper applies TypeConstraint.coerce(result)
       │
       ▼
7. Wrapper validates coerced value against return type
       │
       ▼
8. Return validated, typed result
```

### Validation Flow

```
For each constraint:
    │
    ├──── Has custom validation_fn?
    │     │
    │     ├─ Yes: call validation_fn(text_or_context)
    │     │       return boolean result
    │     │
    │     └─ No: Use LLM-as-a-judge
    │           │
    │           ├─ Construct validation prompt
    │           ├─ Call backend.generate(validation_prompt)
    │           ├─ Parse response (yes/no/true/false)
    │           └─ Return boolean result
    │
    └──── All constraints must pass for success
```

## State Management Model

### Session Configuration Stack

Sessions maintain a **configuration stack** for hierarchical option management:

```ruby
session = Russula.start_session(
  backend: :openai,
  model: 'gpt-4o-mini',
  temperature: 0.5
)

# Base configuration: {temperature: 0.5}

session.push(temperature: 0.9)
# Stack: [{temperature: 0.5}, {temperature: 0.9}]
# Active: {temperature: 0.9}

session.push(max_tokens: 100)
# Stack: [{temperature: 0.5}, {temperature: 0.9}, {max_tokens: 100}]
# Active: {temperature: 0.9, max_tokens: 100}

session.pop
# Stack: [{temperature: 0.5}, {temperature: 0.9}]
# Active: {temperature: 0.9}

session.pop
# Stack: [{temperature: 0.5}]
# Active: {temperature: 0.5}
```

**Implementation:**
- Base configuration stored in `@options`
- Stack stored in `@config_stack` (array of option hashes)
- Each `push` saves current options, then merges new options
- Each `pop` restores previous options from stack
- Error if `pop` called with empty stack

### Context State

Context maintains **immutable message history**:

```ruby
context = Context.new
context.add_message(role: :user, content: "Hello")
context.add_message(role: :assistant, content: "Hi there!")

context.messages
# => [
#      {role: :user, content: "Hello"},
#      {role: :assistant, content: "Hi there!"}
#    ]
```

**Properties:**
- Messages are append-only
- No message editing or deletion in MVP
- Messages include role (`:user`, `:assistant`, `:system`) and content

## Configuration Hierarchy

Configuration options flow through multiple layers:

```
1. Session initialization defaults
   ↓ (overridden by)
2. Backend-specific defaults
   ↓ (overridden by)
3. User-provided session options
   ↓ (overridden by)
4. Temporary push() options
   ↓ (applied to)
5. Backend.generate() call
```

**Example:**

```ruby
# Layer 1: Session defaults (none in MVP)
# Layer 2: OpenAI backend defaults
backend = Backend::OpenAI.new(api_key: key, model: 'gpt-4o-mini')

# Layer 3: User session options
session = Session.new(backend: :openai, temperature: 0.7)

# Layer 4: Temporary override
session.push(temperature: 0.9)
session.instruct("prompt")  # Uses temperature: 0.9

session.pop
session.instruct("prompt")  # Uses temperature: 0.7
```

## Context Management

### Message Structure

Each message in the context has:
- `role`: Symbol (`:user`, `:assistant`, `:system`)
- `content`: String (the message text)

**Future:** May include `metadata` hash for additional info.

### Context Lifecycle

1. **Initialization**: Context created when Session initialized
2. **User Message**: Added when `instruct()` is called
3. **Assistant Message**: Added when Backend returns generation
4. **Persistence**: Context lives for entire session lifetime
5. **Future**: Context serialization/deserialization for session resume

### Context-Aware Validation

Validators can optionally receive full Context instead of just text:

```ruby
# Simple text validator
req('contain hello', validation_fn: ->(text) { text.include?('hello') })

# Context-aware validator
req('maintain consistency', validation_fn: lambda { |context|
  # Can inspect full message history
  context.messages.any? { |m| m[:role] == :user }
})
```

The validation engine determines which signature to use based on validator arity.

## Error Propagation

### Error Hierarchy

```
StandardError
└── Russula::Error (base error)
    ├── Russula::ValidationError
    │   ├── Budget exhausted
    │   ├── Type constraint violation
    │   └── Constraint validation failure
    ├── Russula::BackendError
    │   ├── API errors
    │   ├── Connection errors
    │   └── Invalid response format
    └── Russula::ConfigurationError (future)
```

### Error Flow

```
Backend Error:
  Backend.generate() raises StandardError
  → Caught and wrapped in BackendError
  → Propagated to Session
  → Propagated to user code

Validation Error:
  Constraint.validate() returns false
  → Strategy continues retry loop
  → If budget exhausted: raise ValidationError
  → Propagated to user code

Type Error:
  TypeConstraint.coerce() fails
  → Raise ValidationError immediately
  → Propagated to user code (no retry)
```

**Design Decision:** Type errors don't trigger retries because the LLM already generated output—it's a contract violation, not a validation failure.

## Lifecycle

### Session Lifecycle

```
1. Initialization
   ├─ Create Backend instance
   ├─ Create Context instance
   ├─ Initialize options and config_stack
   └─ Session ready

2. Active Use
   ├─ User calls instruct() or generative methods
   ├─ Messages added to Context
   ├─ Configuration may change (push/pop)
   └─ Repeat

3. Cleanup (future)
   └─ Explicit session.close() or automatic cleanup
```

### Generation Lifecycle (with Validation)

```
1. Request Initiated
   ├─ instruct() called with prompt and constraints
   └─ Strategy.sample() invoked

2. Loop Iteration (up to loop_budget times)
   ├─ a. Context updated with user message
   ├─ b. Backend.generate() called
   ├─ c. Response added to context (tentative)
   ├─ d. Requirements validated
   ├─ e. Checks validated
   ├─ f. Success? → Return ModelOutput
   └─ g. Failure? → Retry (rollback tentative message)

3. Loop Exit
   ├─ Success: Return ModelOutput or SamplingResult
   └─ Failure: Raise ValidationError with attempts info
```

### Generative Method Lifecycle

```
1. Class Definition
   ├─ Generative mixin included
   ├─ generative decorator applied to method
   ├─ method_added hook captures metadata
   └─ Method wrapped with validation logic

2. Method Invocation
   ├─ User calls method(session, **args)
   ├─ Wrapper renders docstring with args
   ├─ Wrapper calls session.instruct()
   ├─ Result returned and type-checked
   └─ Typed value returned to user

3. Type Enforcement
   ├─ TypeConstraint.coerce() converts string
   ├─ TypeConstraint.validate() checks type
   └─ Success or ValidationError
```

## Component Dependencies

```
Session
├── depends on: Backend, Context, Strategy
├── uses: ERB (for templates)
└── provides: Public API

Backend
├── depends on: ruby-openai gem (or similar)
└── provides: LLM generation

Context
├── depends on: none (pure data structure)
└── provides: Message history

Constraint
├── depends on: Session (for LLM-as-a-judge)
└── provides: Validation logic

Strategy
├── depends on: Backend, Constraint, Context
└── provides: Validation loop

Generative Mixin
├── depends on: Session, TypeConstraint
└── provides: Method decorator DSL

TypeConstraint
├── depends on: JSON (for Hash/Array parsing)
└── provides: Type coercion and validation
```

## Performance Considerations

### Caching Opportunities (Future)

- **Backend Response Caching**: Cache identical prompts
- **Validation Caching**: Cache validator results for identical inputs
- **Template Rendering**: Pre-compile ERB templates

### Optimization Strategies

1. **Minimize LLM Calls**: Use custom validators instead of LLM-as-a-judge when possible
2. **Batch Validation**: Validate all constraints in parallel (future)
3. **Early Termination**: Short-circuit validation on first failure
4. **Streaming**: Support streaming responses for long generations (future)

## Extension Points

The architecture supports extension in these areas:

1. **New Backends**: Implement `Backend::Base` interface
2. **New Strategies**: Implement alternative sampling strategies (e.g., best-of-n)
3. **New Constraint Types**: Subclass `Requirement` or `Check`
4. **Custom Type Constraints**: Extend `TypeConstraint` for domain types
5. **Context Implementations**: Alternative context storage (e.g., database-backed)

## References

- [API Specification](API_SPECIFICATION.md)
- [Constraint System Specification](CONSTRAINT_SYSTEM.md)
- [Validation Algorithm](VALIDATION_ALGORITHM.md)
- [Type System](TYPE_SYSTEM.md)
- [Generative Methods DSL](GENERATIVE_METHODS_DSL.md)
- [Backend Integration](BACKEND_INTEGRATION.md)
