# Russula API Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-02-16

## Table of Contents

1. [Overview](#overview)
2. [Module-Level API](#module-level-api)
3. [Session API](#session-api)
4. [Generative Mixin API](#generative-mixin-api)
5. [Backend Interface](#backend-interface)
6. [Constraint API](#constraint-api)
7. [Strategy API](#strategy-api)
8. [Data Types](#data-types)

## Overview

This document specifies all public APIs in Russula. These are the contracts that users depend on and that implementations must satisfy.

**API Stability Guarantees:**
- Public APIs specified here follow semantic versioning
- Breaking changes only in major versions
- Deprecation warnings for one minor version before removal

## Module-Level API

### `Russula.start_session`

Create and initialize a new generative programming session.

**Signature:**
```ruby
Russula.start_session(
  backend: Symbol,
  model: String,
  api_key: String = nil,
  **options
) -> Russula::Session
```

**Parameters:**
- `backend` (Symbol, required): Backend type (`:openai`, `:anthropic`, etc.)
- `model` (String, required): Model identifier (e.g., `'gpt-4o-mini'`)
- `api_key` (String, optional): API key for the backend. If not provided, will look for environment variables
- `**options` (Hash): Additional backend-specific options
  - `temperature` (Float): Sampling temperature (0.0-2.0, default: 1.0)
  - `max_tokens` (Integer): Maximum tokens to generate
  - Other backend-specific options

**Returns:**
- `Russula::Session` instance

**Raises:**
- `Russula::BackendError`: If backend is unsupported, API key missing, or model invalid

**Example:**
```ruby
session = Russula.start_session(
  backend: :openai,
  api_key: ENV['OPENAI_API_KEY'],
  model: 'gpt-4o-mini',
  temperature: 0.7
)
```

---

### `Russula.req`

Create a requirement constraint (included in prompt + validated).

**Signature:**
```ruby
Russula.req(
  description: String,
  validation_fn: Proc = nil
) -> Russula::Requirement
```

**Parameters:**
- `description` (String, required): Human-readable requirement description
  - Included in the generation prompt
  - Used by LLM-as-a-judge if no custom validator
- `validation_fn` (Proc, optional): Custom validation function
  - Signature: `Proc(String) -> Boolean` or `Proc(Context) -> Boolean`
  - Returns `true` if requirement satisfied, `false` otherwise

**Returns:**
- `Russula::Requirement` instance

**Example:**
```ruby
# LLM-as-a-judge validation
req('be polite and professional')

# Custom validator
req('contain greeting', validation_fn: ->(text) { text.match?(/hello|hi/i) })

# Context-aware validator
req('maintain consistency', validation_fn: lambda { |context|
  context.messages.count > 1
})
```

---

### `Russula.check`

Create a check constraint (validated only, NOT included in prompt).

**Signature:**
```ruby
Russula.check(
  description: String,
  validation_fn: Proc = nil
) -> Russula::Check
```

**Parameters:**
- `description` (String, required): Human-readable check description
  - NOT included in prompt (avoids negative priming)
  - Used by LLM-as-a-judge if no custom validator
- `validation_fn` (Proc, optional): Custom validation function
  - Same signature as `req` validators

**Returns:**
- `Russula::Check` instance

**Example:**
```ruby
# Avoid telling LLM what NOT to do (negative priming)
check('no profanity', validation_fn: ->(text) { !text.match?(/bad|damn/) })

# LLM-as-a-judge for subtle checks
check('avoid passive voice')
```

---

## Session API

### `Session#initialize`

Initialize a new session (typically called via `Russula.start_session`).

**Signature:**
```ruby
def initialize(
  backend: Symbol,
  model: String,
  api_key: String = nil,
  **options
)
```

**Parameters:** Same as `Russula.start_session`

**Instance Variables:**
- `@backend`: Backend instance
- `@context`: Context instance
- `@options`: Current options hash
- `@config_stack`: Array of option hashes for push/pop

**Raises:**
- `Russula::BackendError`: If initialization fails

---

### `Session#instruct`

Generate text with optional validation and retry.

**Signature:**
```ruby
def instruct(
  prompt: String,
  requirements: Array<Requirement> = [],
  checks: Array<Check> = [],
  strategy: Strategy = nil,
  user_variables: Hash = {},
  return_sampling_results: Boolean = false
) -> ModelOutput | SamplingResult
```

**Parameters:**
- `prompt` (String, required): Template string for generation
  - Can include ERB syntax: `<%= variable %>`
  - Will be rendered with `user_variables`
- `requirements` (Array<Requirement>, optional): Requirements to include in prompt and validate
- `checks` (Array<Check>, optional): Checks to validate but NOT include in prompt
- `strategy` (Strategy, optional): Validation strategy (default: no validation)
- `user_variables` (Hash, optional): Variables for ERB template rendering
- `return_sampling_results` (Boolean, optional): Return detailed sampling info (default: false)

**Returns:**
- `ModelOutput`: If `return_sampling_results: false` (default)
  - Has `.value` method returning the generated text
- `SamplingResult`: If `return_sampling_results: true`
  - Has `.success`, `.attempts`, `.sample_generations`, `.result` methods

**Raises:**
- `Russula::ValidationError`: If validation fails and budget exhausted
- `Russula::BackendError`: If generation fails

**Example:**
```ruby
# Simple generation
response = session.instruct('Explain quantum computing')
puts response.value

# With template variables
email = session.instruct(
  'Write an email to <%= recipient %> about <%= topic %>',
  user_variables: { recipient: 'team', topic: 'meeting' }
)

# With validation
result = session.instruct(
  'Write a greeting',
  requirements: [
    Russula.req('be formal'),
    Russula.req('include "Dear"')
  ],
  checks: [
    Russula.check('avoid slang')
  ],
  strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 5)
)

# With detailed results
result = session.instruct(
  'Generate text',
  requirements: [Russula.req('be brief')],
  strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3),
  return_sampling_results: true
)

puts "Success: #{result.success}"
puts "Attempts: #{result.attempts}"
puts "Final: #{result.result.value}"
```

---

### `Session#push`

Push new configuration options onto the stack.

**Signature:**
```ruby
def push(**options) -> void
```

**Parameters:**
- `**options` (Hash): Options to merge with current configuration
  - Common options: `temperature`, `max_tokens`
  - Backend-specific options allowed

**Returns:** None (void)

**Side Effects:**
- Saves current options to `@config_stack`
- Merges new options into `@options`
- Updates backend options

**Example:**
```ruby
# Temporary configuration change
session.push(temperature: 0.9, max_tokens: 100)
# All subsequent calls use new config

session.instruct('Creative prompt')  # Uses temp: 0.9

session.pop  # Restore previous config
```

---

### `Session#pop`

Restore previous configuration from the stack.

**Signature:**
```ruby
def pop -> void
```

**Parameters:** None

**Returns:** None (void)

**Raises:**
- `Russula::Error`: If config stack is empty

**Side Effects:**
- Restores options from top of `@config_stack`
- Updates current `@options`
- Updates backend options

**Example:**
```ruby
session.push(temperature: 0.9)
session.push(max_tokens: 50)
session.pop  # Back to temperature: 0.9
session.pop  # Back to original config
session.pop  # ERROR: stack empty
```

---

### `Session#context`

Access the conversation context.

**Signature:**
```ruby
def context -> Context
```

**Returns:**
- `Context` instance with message history

**Example:**
```ruby
session.instruct('Hello')
session.instruct('How are you?')

messages = session.context.messages
# => [
#      {role: :user, content: 'Hello'},
#      {role: :assistant, content: '...'},
#      {role: :user, content: 'How are you?'},
#      {role: :assistant, content: '...'}
#    ]
```

---

### `Session#backend`

Access the backend instance.

**Signature:**
```ruby
def backend -> Backend::Base
```

**Returns:**
- Backend instance (e.g., `Backend::OpenAI`)

**Usage:**
```ruby
session.backend.model  # => 'gpt-4o-mini'
```

---

### `Session#options`

Access current configuration options.

**Signature:**
```ruby
def options -> Hash
```

**Returns:**
- Hash of current options

**Example:**
```ruby
session.options  # => {temperature: 0.7, max_tokens: 1000}
```

---

## Generative Mixin API

### `Generative` Module

Include this module in a class to enable generative method definitions.

**Usage:**
```ruby
class MyClass
  include Russula::Generative

  generative def method_name(param1:, param2: default) -> ReturnType
    "Template with <%= param1 %> and <%= param2 %>"
  end
end
```

---

### `generative` Decorator

Define an LLM-powered method with type constraints.

**Syntax:**
```ruby
generative def method_name(param1:, param2: = default, ...) -> ReturnTypeConstraint
  "Docstring template"
end
```

**Components:**

1. **Method Signature:**
   - Must use keyword arguments
   - Positional arguments not supported (except `session`)

2. **Return Type Annotation:**
   - `-> [:symbol1, :symbol2, ...]`: Symbol enumeration constraint
   - `-> String`: String constraint
   - `-> Integer`: Integer constraint
   - `-> Float`: Float constraint
   - `-> Hash`: Hash constraint (expects JSON)
   - `-> Array`: Array constraint (expects JSON)

3. **Docstring/Body:**
   - Becomes the prompt template
   - Supports ERB interpolation: `<%= param_name %>`
   - Variables come from method parameters

**Invocation:**
- First parameter MUST be `session` (injected by wrapper)
- Remaining parameters passed as keyword arguments

**Example:**
```ruby
class SentimentClassifier
  include Russula::Generative

  generative def classify(text:) -> [:positive, :negative, :neutral]
    "Classify the sentiment of: <%= text %>"
  end

  generative def extract_entities(text:) -> Hash
    "Extract person names and locations from: <%= text %>. Return as JSON."
  end
end

classifier = SentimentClassifier.new
session = Russula.start_session(...)

# Must pass session first
sentiment = classifier.classify(session, text: 'I love this!')
# => :positive

entities = classifier.extract_entities(session, text: 'Alice visited Paris.')
# => {"person" => "Alice", "location" => "Paris"}
```

---

### `ClassMethods.generative_methods`

Access metadata for all generative methods defined in a class.

**Signature:**
```ruby
def self.generative_methods -> Hash
```

**Returns:**
- Hash mapping method names to metadata hashes
  - Keys: method name symbols
  - Values: `{return_type: ..., docstring: ..., parameters: ...}`

**Example:**
```ruby
class Example
  include Russula::Generative

  generative def test_method -> [:a, :b]
    "Docstring"
  end
end

Example.generative_methods
# => {
#      test_method: {
#        return_type: [:a, :b],
#        docstring: "Docstring",
#        parameters: []
#      }
#    }
```

---

## Backend Interface

All backends must implement the `Backend::Base` interface.

### `Backend::Base#initialize`

**Signature:**
```ruby
def initialize(model:, **options)
```

**Parameters:**
- `model` (String, required): Model identifier
- `**options`: Backend-specific options

---

### `Backend::Base#generate`

Generate a completion from message history.

**Signature:**
```ruby
def generate(messages: Array<Hash>, **options) -> String
```

**Parameters:**
- `messages` (Array<Hash>, required): Message history
  - Each hash has `:role` (Symbol) and `:content` (String)
  - Roles: `:system`, `:user`, `:assistant`
- `**options` (Hash, optional): Override options for this call

**Returns:**
- String: Generated text content

**Raises:**
- `Russula::BackendError`: On API errors, connection failures, or invalid responses

**Example:**
```ruby
messages = [
  {role: :system, content: 'You are a helpful assistant.'},
  {role: :user, content: 'Hello!'}
]

response = backend.generate(messages)
# => "Hello! How can I help you today?"
```

---

### `Backend::Base#update_options`

Update backend configuration options.

**Signature:**
```ruby
def update_options(**new_options) -> void
```

**Parameters:**
- `**new_options` (Hash): Options to merge

**Returns:** None (void)

---

### `Backend::Base#model`

Get the current model identifier.

**Signature:**
```ruby
def model -> String
```

---

### `Backend::Base#options`

Get current backend options.

**Signature:**
```ruby
def options -> Hash
```

---

## Constraint API

### `Requirement#initialize`

**Signature:**
```ruby
def initialize(description: String, validation_fn: Proc = nil)
```

---

### `Requirement#validate`

Validate text or context against this requirement.

**Signature:**
```ruby
def validate(text_or_context: String | Context, session: Session) -> Boolean
```

**Parameters:**
- `text_or_context`: Either generated text (String) or full Context
- `session`: Session instance (for LLM-as-a-judge)

**Returns:**
- `true` if requirement satisfied
- `false` if requirement not satisfied

---

### `Requirement#include_in_prompt`

**Signature:**
```ruby
def include_in_prompt -> Boolean
```

**Returns:**
- `true` for Requirements (always)

---

### `Check#initialize`

Same as `Requirement#initialize`.

---

### `Check#validate`

Same as `Requirement#validate`.

---

### `Check#include_in_prompt`

**Signature:**
```ruby
def include_in_prompt -> Boolean
```

**Returns:**
- `false` for Checks (always)

---

## Strategy API

### `RejectionSamplingStrategy#initialize`

**Signature:**
```ruby
def initialize(loop_budget: Integer)
```

**Parameters:**
- `loop_budget` (Integer, required): Maximum number of generation attempts

---

### `RejectionSamplingStrategy#sample`

Execute the validation loop.

**Signature:**
```ruby
def sample(
  session: Session,
  prompt: String,
  requirements: Array<Requirement> = [],
  checks: Array<Check> = []
) -> SamplingResult
```

**Parameters:**
- `session`: Session instance
- `prompt`: Rendered prompt text
- `requirements`: Requirements to validate
- `checks`: Checks to validate

**Returns:**
- `SamplingResult` with success/failure info

**Raises:**
- `Russula::ValidationError`: If budget exhausted without success

---

## Data Types

### `ModelOutput`

Represents a single generation output.

**Attributes:**
- `value` (String): Generated text
- `metadata` (Hash): Optional metadata

**Methods:**
- `to_s -> String`: Returns `value`

---

### `SamplingResult`

Represents detailed sampling results.

**Attributes:**
- `success` (Boolean): Whether validation succeeded
- `attempts` (Integer): Number of attempts made
- `sample_generations` (Array<ModelOutput>): All attempted generations
- `result` (ModelOutput): Final successful generation (or last attempt if failed)

---

### `Context`

Represents conversation history.

**Attributes:**
- `messages` (Array<Hash>): Message history

**Methods:**
- `add_message(role: Symbol, content: String) -> void`
- `clear -> void` (future)

---

## Error Classes

### `Russula::Error`

Base error class for all Russula errors.

---

### `Russula::ValidationError < Error`

Raised when validation fails.

**Attributes:**
- `message` (String): Error description
- `attempts` (Integer): Number of attempts made (if from sampling)
- `sample_generations` (Array<ModelOutput>): Failed generations (if from sampling)

---

### `Russula::BackendError < Error`

Raised when backend operations fail.

**Attributes:**
- `message` (String): Error description
- `cause` (Exception): Original exception (if wrapped)

---

## Versioning and Compatibility

**API Version:** 0.1.0

**Stability:**
- Module-level API: Stable
- Session API: Stable
- Generative Mixin API: Experimental (syntax may change)
- Backend Interface: Stable
- Constraint API: Stable
- Strategy API: Experimental

**Future Additions (Non-Breaking):**
- Additional backend implementations
- Additional strategy implementations
- Additional constraint types
- Session serialization/deserialization
- Streaming support

**Breaking Changes (Future Major Versions):**
- Changes to generative method syntax
- Changes to constraint validation semantics
- Changes to backend interface contracts

---

## See Also

- [Architecture Specification](ARCHITECTURE.md)
- [Constraint System](CONSTRAINT_SYSTEM.md)
- [Validation Algorithm](VALIDATION_ALGORITHM.md)
- [Type System](TYPE_SYSTEM.md)
- [Generative Methods DSL](GENERATIVE_METHODS_DSL.md)
- [Backend Integration](BACKEND_INTEGRATION.md)
