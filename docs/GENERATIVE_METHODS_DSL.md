# Generative Methods DSL Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-02-16

> **Implementation note (MVP):** Ruby does not support `-> Type` annotations on
> method definitions (`->` parses as a lambda literal). v0.1.0 therefore uses a
> block-form DSL: `generative :name, returns: Type do |args| "template" end`.
> The semantics described below (type constraints, ERB interpolation, session
> injection, return-type coercion) apply identically — mentally rewrite
> `generative def foo(args) -> Type` as `generative :foo, returns: Type do |args|`,
> and treat the block return value as the docstring/prompt template.

## Table of Contents

1. [Overview](#overview)
2. [DSL Syntax](#dsl-syntax)
3. [Method Definition Pattern](#method-definition-pattern)
4. [Template Processing](#template-processing)
5. [Session Injection Mechanism](#session-injection-mechanism)
6. [Implementation Strategy](#implementation-strategy)
7. [Type Constraint Enforcement](#type-constraint-enforcement)
8. [Error Handling](#error-handling)
9. [Metadata Storage](#metadata-storage)
10. [Complete Examples](#complete-examples)

## Overview

The Generative Methods DSL provides a declarative way to define LLM-powered methods within Ruby classes. It combines:

- **Type-safe method signatures** with return type constraints
- **ERB template processing** for dynamic prompt generation
- **Automatic session management** via parameter injection
- **Transparent type coercion** and validation
- **Metadata tracking** for introspection

### Design Philosophy

Traditional LLM integration requires boilerplate:

```ruby
# Without DSL
def classify_sentiment(session, text:)
  prompt = "Classify the sentiment of the input text as positive, negative, or neutral: #{text}"
  response = session.instruct(prompt)
  # Manual type checking, coercion, validation...
  response.to_sym
end
```

The DSL eliminates this boilerplate:

```ruby
# With DSL
generative def classify_sentiment(text:) -> [:positive, :negative, :neutral]
  "Classify the sentiment of the input text as positive, negative, or neutral."
end
```

**Key Benefits:**
- Declarative type constraints
- Automatic template rendering
- Built-in validation
- Reduced boilerplate
- Clear separation of prompt from implementation

## DSL Syntax

### Basic Form

```ruby
generative def method_name(param1:, param2: = default, ...) -> ReturnTypeConstraint
  "Docstring template with <%= param1 %> and <%= param2 %>"
end
```

### Components

#### 1. `generative` Decorator

The `generative` keyword marks a method for LLM-powered execution.

**Placement:**
- Appears immediately before method definition
- Applied to instance methods only (not class methods)

**Example:**
```ruby
generative def my_method
  "Prompt template"
end
```

#### 2. Method Signature

**Requirements:**
- MUST use keyword arguments (positional arguments not supported)
- MAY include default values
- MUST NOT include `session` parameter (automatically injected)

**Valid:**
```ruby
generative def method_one(text:) -> String
generative def method_two(text:, max_words: 50) -> Integer
generative def method_three(a:, b: 10, c: 'default') -> Array
```

**Invalid:**
```ruby
generative def bad_one(text) -> String          # No keyword arg
generative def bad_two(session, text:) -> String # Session explicit
generative def bad_three(text:, *args) -> String # Splat not supported
```

#### 3. Return Type Annotation

The `-> ReturnType` syntax specifies the expected output type.

**Supported Types:**

| Annotation | Description | Example Output |
|------------|-------------|----------------|
| `-> String` | Plain text | `"Hello world"` |
| `-> Integer` | Whole number | `42` |
| `-> Float` | Decimal number | `3.14` |
| `-> Hash` | JSON object | `{"name" => "Alice"}` |
| `-> Array` | JSON array | `[1, 2, 3]` |
| `-> [:a, :b, ...]` | Symbol enumeration | `:positive` |
| `-> Boolean` | True/false (future) | `true` |

**Examples:**
```ruby
generative def summarize(text:) -> String
generative def count_words(text:) -> Integer
generative def extract_data(text:) -> Hash
generative def classify(text:) -> [:positive, :negative, :neutral]
```

#### 4. Docstring Body

The method body MUST be a single string (the docstring).

**Properties:**
- Serves as the prompt template
- Supports ERB interpolation
- No other code allowed in method body
- String can be multi-line

**Valid:**
```ruby
generative def example(name:) -> String
  "Hello, <%= name %>!"
end

generative def multi_line(topic:) -> String
  <<~PROMPT
    Write an essay about <%= topic %>.
    The essay should be informative and engaging.
  PROMPT
end
```

**Invalid:**
```ruby
generative def bad_example(name:) -> String
  puts "Debug"  # ERROR: No code allowed
  "Hello, <%= name %>!"
end
```

## Method Definition Pattern

### Class Inclusion

Include `Russula::Generative` module to enable the DSL:

```ruby
class MyClass
  include Russula::Generative

  generative def method_name(...) -> ReturnType
    "Template"
  end
end
```

**What happens:**
1. `included` hook adds class methods (`.generative_methods`, `.generative`)
2. `method_added` hook intercepts generative method definitions
3. Original method replaced with wrapper
4. Metadata stored in class-level registry

### Method Invocation

Generative methods require `session` as the first argument:

```ruby
instance = MyClass.new
session = Russula.start_session(...)

# Call with session first, then keyword args
result = instance.method_name(session, param1: value1, param2: value2)
```

**Session Requirement:**
- Session MUST be passed explicitly
- Validation enforced at runtime
- Raises `ArgumentError` if session missing

**Example:**
```ruby
class Classifier
  include Russula::Generative

  generative def classify(text:) -> [:positive, :negative, :neutral]
    "Classify: <%= text %>"
  end
end

classifier = Classifier.new
session = Russula.start_session(backend: :openai, model: 'gpt-4o-mini')

# Correct
result = classifier.classify(session, text: 'I love this!')
# => :positive

# Wrong - missing session
classifier.classify(text: 'I love this!')
# => ArgumentError: session required
```

### Parameter Passing

**Keyword Arguments:**
- All method parameters become template variables
- Passed as `key: value` pairs
- Default values applied if not provided

**Example:**
```ruby
generative def summarize(text:, max_words: 50) -> String
  "Summarize in at most <%= max_words %> words: <%= text %>"
end

# Use default
summarize(session, text: 'Long text...')
# Template: "Summarize in at most 50 words: Long text..."

# Override default
summarize(session, text: 'Long text...', max_words: 25)
# Template: "Summarize in at most 25 words: Long text..."
```

## Template Processing

### ERB Rendering

Docstrings are rendered using ERB (Embedded Ruby) before being sent to the LLM.

**Template Syntax:**
```ruby
"Text with <%= variable %> interpolation"
```

**Example:**
```ruby
generative def greet(name:, greeting: 'Hello') -> String
  "<%= greeting %>, <%= name %>! How are you today?"
end

greet(session, name: 'Alice')
# Rendered: "Hello, Alice! How are you today?"

greet(session, name: 'Bob', greeting: 'Hi')
# Rendered: "Hi, Bob! How are you today?"
```

### Variable Scoping

**Variables Available in Templates:**
1. All method parameters (keyword arguments)
2. No instance variables or methods (isolated scope)

**Example:**
```ruby
class Example
  include Russula::Generative

  def initialize
    @instance_var = "Cannot access this"
  end

  generative def test_method(name:) -> String
    # Only 'name' is available
    "Hello, <%= name %>!"

    # This would fail:
    # "Hello, <%= @instance_var %>"  # ERROR: @instance_var not in scope
  end
end
```

**Why Isolated Scope:**
- Ensures templates are pure functions of parameters
- Prevents accidental state coupling
- Makes templates easier to test and reason about

### Template Rendering Algorithm

```ruby
def render_template(docstring, variables)
  # 1. Create isolated binding
  binding_object = create_isolated_binding(variables)

  # 2. Render ERB template
  erb = ERB.new(docstring)
  erb.result(binding_object)
end

def create_isolated_binding(variables)
  # Create clean binding with only the variables hash
  variables.instance_eval { binding }
end
```

**Process:**
1. Extract docstring from method metadata
2. Extract parameter values from method call
3. Create isolated binding with parameter hash
4. Render ERB template with binding
5. Return rendered string as prompt

**Example Flow:**
```ruby
# Definition
generative def example(a:, b:) -> String
  "Param a is <%= a %> and param b is <%= b %>"
end

# Invocation
example(session, a: 10, b: 20)

# Rendering
variables = {a: 10, b: 20}
template = "Param a is <%= a %> and param b is <%= b %>"
rendered = ERB.new(template).result(variables.instance_eval { binding })
# => "Param a is 10 and param b is 20"
```

### Complex Template Examples

**Multi-line Templates:**
```ruby
generative def write_email(to:, subject:, points:) -> String
  <<~PROMPT
    Write a professional email with the following details:

    To: <%= to %>
    Subject: <%= subject %>

    Key points to cover:
    <%= points.map { |p| "- #{p}" }.join("\n") %>
  PROMPT
end

write_email(
  session,
  to: 'team@company.com',
  subject: 'Project Update',
  points: ['Milestone achieved', 'Next steps defined']
)
# Rendered:
# Write a professional email with the following details:
#
# To: team@company.com
# Subject: Project Update
#
# Key points to cover:
# - Milestone achieved
# - Next steps defined
```

**Conditional Templates:**
```ruby
generative def format_response(formal:, name:) -> String
  <<~PROMPT
    <%= if formal %>
      Write a formal greeting to <%= name %>.
    <% else %>
      Write a casual greeting to <%= name %>.
    <% end %>
  PROMPT
end
```

## Session Injection Mechanism

### Why Session Injection

Generative methods need access to a `Session` instance to call `session.instruct()`, but requiring users to define `session` as a parameter would clutter the DSL:

```ruby
# Without injection (verbose)
generative def method(session, text:) -> String
  "Template with <%= text %>"
end

# With injection (clean)
generative def method(text:) -> String
  "Template with <%= text %>"
end

# But invocation still requires session
method(session, text: 'value')
```

### Injection Implementation

**Step 1: Define method without session**
```ruby
generative def classify(text:) -> [:positive, :negative]
  "Classify: <%= text %>"
end
```

**Step 2: Wrapper intercepts call**
```ruby
def classify(*args, **kwargs)
  # Extract session from first positional arg
  session = args.first

  # Validate session presence
  raise ArgumentError, 'session required' unless session.is_a?(Russula::Session)

  # Extract keyword args (text:, etc.)
  # Render template
  # Call session.instruct()
  # Apply type constraints
  # Return result
end
```

**Step 3: User calls with session first**
```ruby
result = instance.classify(session, text: 'I love this!')
```

### Session Validation

The wrapper validates that the first argument is a `Session`:

```ruby
def validate_session(arg)
  unless arg.is_a?(Russula::Session)
    raise ArgumentError, "session required as first argument, got #{arg.class}"
  end
  arg
end
```

**Error Cases:**
```ruby
# Missing session
instance.method(text: 'value')
# => ArgumentError: session required

# Wrong type
instance.method('not a session', text: 'value')
# => ArgumentError: session required as first argument, got String

# Nil session
instance.method(nil, text: 'value')
# => ArgumentError: session required as first argument, got NilClass
```

### Parameter Separation

The wrapper separates session from method parameters:

```ruby
def wrapper(*args, **kwargs)
  session = args.first  # Session
  # args[1..] would be additional positional args (not supported)
  # kwargs contains all keyword arguments

  render_and_invoke(session, kwargs)
end
```

**Example:**
```ruby
# Call
instance.method(session, a: 1, b: 2, c: 3)

# Inside wrapper
session = args[0]       # Session instance
kwargs = {a: 1, b: 2, c: 3}
```

## Implementation Strategy

### Method Wrapping

When a generative method is defined, it's replaced with a wrapper:

```ruby
# Original definition
generative def classify(text:) -> [:positive, :negative]
  "Classify: <%= text %>"
end

# Becomes (conceptually)
def classify(*args, **kwargs)
  session = validate_session(args.first)
  metadata = self.class.generative_methods[:classify]

  # Render template
  template = metadata[:docstring]
  rendered = render_template(template, kwargs)

  # Call session.instruct
  response = session.instruct(rendered)

  # Apply type constraint
  return_type = metadata[:return_type]
  coerced = TypeConstraint.coerce(response.value, return_type)

  # Validate type
  TypeConstraint.validate(coerced, return_type)

  coerced
end
```

### `method_added` Hook

The `generative` decorator uses Ruby's `method_added` hook to intercept method definitions:

```ruby
module Russula
  module Generative
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def generative_methods
        @generative_methods ||= {}
      end

      def generative(method_def)
        @next_method_is_generative = true
      end

      def method_added(method_name)
        return unless @next_method_is_generative

        @next_method_is_generative = false

        # Capture metadata
        original_method = instance_method(method_name)
        docstring = extract_docstring(original_method)
        return_type = extract_return_type  # From @pending_return_type
        parameters = original_method.parameters

        # Store metadata
        generative_methods[method_name] = {
          docstring: docstring,
          return_type: return_type,
          parameters: parameters
        }

        # Replace method with wrapper
        define_generative_wrapper(method_name)
      end
    end
  end
end
```

### Return Type Capture

Return type annotations are captured before `method_added` fires:

```ruby
def generative(return_type_annotation)
  # Parse: def method(...) -> ReturnType
  # Extract ReturnType
  @pending_return_type = parse_return_type(return_type_annotation)
  @next_method_is_generative = true
end

def parse_return_type(annotation)
  # annotation could be:
  # - String (class name)
  # - Array (symbol enumeration)
  # - Class constant

  # Return normalized representation
end
```

**Note:** Ruby doesn't natively support `-> ReturnType` syntax. This requires parsing or custom DSL extensions.

**Alternative Implementation (Explicit):**
```ruby
# If -> syntax not available, use explicit return type
generative :classify, returns: [:positive, :negative] do
  def classify(text:)
    "Classify: <%= text %>"
  end
end
```

### Docstring Extraction

Extract the docstring from the method body:

```ruby
def extract_docstring(method)
  # Get method source
  source = method.source

  # Parse method body
  # Extract string literal (docstring)
  # Return docstring text

  # Simplified: assume body is single string
  # Real implementation needs AST parsing
end
```

**Assumption for MVP:**
- Method body must be a single string literal
- No other code allowed
- String can be single or multi-line

### Wrapper Definition

Define the wrapper that replaces the original method:

```ruby
def define_generative_wrapper(method_name)
  metadata = generative_methods[method_name]

  define_method(method_name) do |*args, **kwargs|
    # Validate session
    session = args.first
    raise ArgumentError, 'session required' unless session.is_a?(Russula::Session)

    # Render template
    template = metadata[:docstring]
    rendered = ERB.new(template).result(kwargs.instance_eval { binding })

    # Call session.instruct
    response = session.instruct(rendered)

    # Apply type constraint
    return_type = metadata[:return_type]
    result = TypeConstraint.coerce(response.value, return_type)

    # Validate type
    unless TypeConstraint.valid?(result, return_type)
      raise Russula::ValidationError,
            "Invalid return value: expected #{return_type}, got #{result.class}"
    end

    result
  end
end
```

## Type Constraint Enforcement

### Type Coercion

The wrapper automatically coerces LLM string responses to the declared return type:

**String -> Symbol (for enumeration):**
```ruby
# Definition
generative def classify(text:) -> [:positive, :negative, :neutral]
  "Classify: <%= text %>"
end

# LLM returns
"positive"

# Coerced to
:positive
```

**String -> Integer:**
```ruby
# Definition
generative def count_words(text:) -> Integer
  "Count words in: <%= text %>"
end

# LLM returns
"42"

# Coerced to
42
```

**String -> Hash:**
```ruby
# Definition
generative def extract_data(text:) -> Hash
  "Extract as JSON: <%= text %>"
end

# LLM returns
'{"name": "Alice", "age": 30}'

# Coerced to
{"name" => "Alice", "age" => 30}
```

### Coercion Algorithm

```ruby
module TypeConstraint
  def self.coerce(value, type_annotation)
    case type_annotation
    when String
      value.to_s

    when Integer
      Integer(value)

    when Float
      Float(value)

    when Hash
      JSON.parse(value)

    when Array
      if type_annotation.all? { |t| t.is_a?(Symbol) }
        # Symbol enumeration
        value.to_sym
      else
        # Array type
        JSON.parse(value)
      end

    else
      raise "Unknown type annotation: #{type_annotation}"
    end
  end
end
```

### Validation Algorithm

After coercion, validate the result:

```ruby
module TypeConstraint
  def self.validate(value, type_annotation)
    case type_annotation
    when String
      value.is_a?(String)

    when Integer
      value.is_a?(Integer)

    when Float
      value.is_a?(Float)

    when Hash
      value.is_a?(Hash)

    when Array
      if type_annotation.all? { |t| t.is_a?(Symbol) }
        # Symbol enumeration constraint
        type_annotation.include?(value)
      else
        value.is_a?(Array)
      end

    else
      false
    end
  end
end
```

### Symbol Enumeration Constraints

Special handling for symbol enumerations:

```ruby
# Definition
generative def classify(text:) -> [:positive, :negative, :neutral]
  "Classify: <%= text %>"
end

# Valid responses (after coercion)
:positive   # Valid
:negative   # Valid
:neutral    # Valid
:happy      # Invalid - raises ValidationError

# Validation
def validate_symbol_enumeration(value, allowed_symbols)
  unless allowed_symbols.include?(value)
    raise Russula::ValidationError,
          "Invalid return value: #{value.inspect} must be one of #{allowed_symbols.inspect}"
  end
end
```

### Type Error Examples

**Symbol Enumeration Violation:**
```ruby
# LLM returns
"happy"

# Coerced to
:happy

# Validation fails
raise ValidationError, "Invalid return value: :happy must be one of [:positive, :negative, :neutral]"
```

**Integer Parsing Error:**
```ruby
# LLM returns
"not a number"

# Coercion fails
raise ValidationError, "Invalid Integer: 'not a number'"
```

**JSON Parsing Error:**
```ruby
# LLM returns
"not valid json"

# Coercion fails (JSON.parse raises)
raise ValidationError, "Invalid JSON: unexpected token at 'not valid json'"
```

## Error Handling

### Error Types

Generative methods can raise several error types:

| Error | Cause | When |
|-------|-------|------|
| `ArgumentError` | Missing or invalid session | Method invocation |
| `Russula::ValidationError` | Type constraint violation | After generation |
| `Russula::ValidationError` | Coercion failure | Type coercion |
| `Russula::BackendError` | LLM API failure | During generation |

### Session Validation Errors

```ruby
instance.method(text: 'value')
# ArgumentError: session required

instance.method(nil, text: 'value')
# ArgumentError: session required as first argument, got NilClass

instance.method('wrong', text: 'value')
# ArgumentError: session required as first argument, got String
```

### Type Constraint Errors

```ruby
# Symbol enumeration violation
generative def classify(text:) -> [:positive, :negative]
  "Classify: <%= text %>"
end

# LLM returns 'neutral'
instance.classify(session, text: 'I love this!')
# ValidationError: Invalid return value: :neutral must be one of [:positive, :negative]
```

### Coercion Errors

```ruby
# Integer coercion failure
generative def count(text:) -> Integer
  "Count: <%= text %>"
end

# LLM returns 'many'
instance.count(session, text: 'Some text')
# ValidationError: Invalid Integer: 'many'

# JSON parsing failure
generative def extract(text:) -> Hash
  "Extract as JSON: <%= text %>"
end

# LLM returns 'not json'
instance.extract(session, text: 'Some text')
# ValidationError: Invalid JSON: unexpected token at 'not json'
```

### Backend Errors

```ruby
# API failure (network, auth, etc.)
instance.method(session, text: 'value')
# BackendError: OpenAI API error: Invalid API key

# Rate limit
instance.method(session, text: 'value')
# BackendError: Rate limit exceeded
```

### Error Handling Best Practices

**Rescue Specific Errors:**
```ruby
begin
  result = classifier.classify(session, text: 'I love this!')
rescue Russula::ValidationError => e
  # Handle validation failure
  puts "Validation failed: #{e.message}"
rescue Russula::BackendError => e
  # Handle API failure
  puts "API error: #{e.message}"
end
```

**Check Session Before Calling:**
```ruby
if session.is_a?(Russula::Session)
  result = instance.method(session, text: 'value')
else
  puts "Invalid session"
end
```

**Provide Fallback for Type Errors:**
```ruby
begin
  sentiment = classifier.classify(session, text: text)
rescue Russula::ValidationError
  # Fallback to default
  sentiment = :neutral
end
```

## Metadata Storage

### Class-Level Registry

Each class with `include Russula::Generative` maintains a metadata registry:

```ruby
class Example
  include Russula::Generative

  generative def method_one(a:) -> String
    "Template"
  end

  generative def method_two(b:) -> Integer
    "Template"
  end
end

Example.generative_methods
# => {
#      method_one: {
#        docstring: "Template",
#        return_type: String,
#        parameters: [[:keyreq, :a]]
#      },
#      method_two: {
#        docstring: "Template",
#        return_type: Integer,
#        parameters: [[:keyreq, :b]]
#      }
#    }
```

### Metadata Structure

Each method's metadata includes:

```ruby
{
  docstring: String,        # Template text
  return_type: Class | Array,  # Type constraint
  parameters: Array         # Method parameters (from method.parameters)
}
```

**Example:**
```ruby
generative def classify(text:, threshold: 0.5) -> [:positive, :negative]
  "Classify: <%= text %> with threshold <%= threshold %>"
end

# Metadata
{
  docstring: "Classify: <%= text %> with threshold <%= threshold %>",
  return_type: [:positive, :negative],
  parameters: [[:keyreq, :text], [:key, :threshold]]
}
```

### Accessing Metadata

**Class Method:**
```ruby
Example.generative_methods[:method_name]
# => {docstring: "...", return_type: ..., parameters: ...}
```

**Instance Method (Future):**
```ruby
instance.generative_method_metadata(:method_name)
# => {docstring: "...", return_type: ..., parameters: ...}
```

### Metadata Uses

1. **Runtime Introspection**: Inspect method signatures and types
2. **Documentation Generation**: Auto-generate API docs
3. **Testing**: Validate method contracts
4. **Debugging**: Inspect template and type information

**Example: Documentation Generation**
```ruby
Example.generative_methods.each do |name, meta|
  puts "Method: #{name}"
  puts "  Template: #{meta[:docstring]}"
  puts "  Returns: #{meta[:return_type]}"
  puts "  Parameters: #{meta[:parameters].map(&:last).join(', ')}"
end

# Output:
# Method: classify
#   Template: Classify: <%= text %> with threshold <%= threshold %>
#   Returns: [:positive, :negative]
#   Parameters: text, threshold
```

## Complete Examples

### Example 1: Sentiment Classifier

```ruby
class SentimentClassifier
  include Russula::Generative

  generative def classify(text:) -> [:positive, :negative, :neutral]
    "Classify the sentiment of the following text as positive, negative, or neutral: <%= text %>"
  end

  generative def explain_sentiment(text:) -> String
    "Explain why the sentiment of '<%= text %>' is what it is."
  end
end

# Usage
classifier = SentimentClassifier.new
session = Russula.start_session(backend: :openai, model: 'gpt-4o-mini')

sentiment = classifier.classify(session, text: 'I love this product!')
# => :positive

explanation = classifier.explain_sentiment(session, text: 'I love this product!')
# => "The text expresses strong positive emotion with the word 'love'..."
```

### Example 2: Text Summarizer

```ruby
class TextSummarizer
  include Russula::Generative

  generative def summarize(text:, max_words: 50) -> String
    "Summarize the following text in at most <%= max_words %> words:\n\n<%= text %>"
  end

  generative def extract_key_points(text:) -> Array
    "Extract the key points from the following text as a JSON array:\n\n<%= text %>"
  end
end

# Usage
summarizer = TextSummarizer.new
session = Russula.start_session(backend: :openai, model: 'gpt-4o-mini')

summary = summarizer.summarize(
  session,
  text: 'Long article text...',
  max_words: 25
)
# => "A concise 25-word summary..."

points = summarizer.extract_key_points(
  session,
  text: 'Article text...'
)
# => ["Point 1", "Point 2", "Point 3"]
```

### Example 3: Data Extractor

```ruby
class DataExtractor
  include Russula::Generative

  generative def extract_person_info(text:) -> Hash
    <<~PROMPT
      Extract the following information from the text and return as JSON:
      - name (string)
      - age (integer)
      - city (string)

      Text: <%= text %>
    PROMPT
  end

  generative def extract_dates(text:) -> Array
    "Extract all dates mentioned in the text as a JSON array: <%= text %>"
  end
end

# Usage
extractor = DataExtractor.new
session = Russula.start_session(backend: :openai, model: 'gpt-4o-mini')

info = extractor.extract_person_info(
  session,
  text: 'Alice is 30 years old and lives in New York.'
)
# => {"name" => "Alice", "age" => 30, "city" => "New York"}

dates = extractor.extract_dates(
  session,
  text: 'The meeting is on March 15th and the deadline is April 1st.'
)
# => ["March 15th", "April 1st"]
```

### Example 4: Multi-Parameter Template

```ruby
class EmailWriter
  include Russula::Generative

  generative def write_email(to:, subject:, tone: 'professional', key_points: []) -> String
    <<~PROMPT
      Write a <%= tone %> email with the following details:

      To: <%= to %>
      Subject: <%= subject %>

      <% if key_points.any? %>
      Key points to include:
      <%= key_points.map { |point| "- #{point}" }.join("\n") %>
      <% end %>
    PROMPT
  end
end

# Usage
writer = EmailWriter.new
session = Russula.start_session(backend: :openai, model: 'gpt-4o-mini')

email = writer.write_email(
  session,
  to: 'team@company.com',
  subject: 'Project Update',
  tone: 'casual',
  key_points: ['Milestone reached', 'Next steps defined', 'Help needed with testing']
)
# => "Hi team,\n\nJust wanted to update you on the project..."
```

### Example 5: Context Integration

```ruby
class ConversationAgent
  include Russula::Generative

  generative def continue_story(prompt:) -> String
    "Continue the story from the previous context: <%= prompt %>"
  end
end

# Usage
agent = ConversationAgent.new
session = Russula.start_session(backend: :openai, model: 'gpt-4o-mini')

# First call
part1 = agent.continue_story(session, prompt: 'Once upon a time...')
# => "Once upon a time, there was a brave knight..."

# Second call (with context)
part2 = agent.continue_story(session, prompt: 'What happened next?')
# => "The knight encountered a dragon..." (references previous context)

# Check context
session.context.messages.count
# => 4 (2 user messages + 2 assistant messages)
```

## See Also

- [API Specification](API_SPECIFICATION.md)
- [Architecture Specification](ARCHITECTURE.md)
- [Constraint System](CONSTRAINT_SYSTEM.md)
- [Type System](TYPE_SYSTEM.md)
- [Validation Algorithm](VALIDATION_ALGORITHM.md)
