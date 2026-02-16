# Type Constraint System Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-02-16

## Table of Contents

1. [Overview](#overview)
2. [Type Constraint Architecture](#type-constraint-architecture)
3. [Symbol Enumeration Constraints](#symbol-enumeration-constraints)
4. [Class-Based Type Constraints](#class-based-type-constraints)
5. [Coercion System](#coercion-system)
6. [Validation Algorithm](#validation-algorithm)
7. [Error Specification](#error-specification)
8. [Integration with Generative Methods](#integration-with-generative-methods)
9. [Extensibility](#extensibility)
10. [Best Practices](#best-practices)

## Overview

The Type Constraint System is Russula's third tier of constraint validation, ensuring that LLM-generated outputs conform to expected type contracts. Unlike requirements (prompt-included) and checks (post-generation validation), type constraints enforce structural guarantees on return values.

### Design Goals

- **Type Safety**: Ensure all generative method outputs match declared types
- **Automatic Coercion**: Convert LLM text outputs to typed Ruby values
- **Clear Contracts**: Explicit type signatures for all generative methods
- **Fail-Fast**: Immediate validation errors on type mismatches
- **Extensibility**: Support for custom type definitions

### Position in Constraint Hierarchy

```
┌─────────────────────────────────────────────────────────┐
│ Tier 1: Requirements (in prompt + validated)           │
├─────────────────────────────────────────────────────────┤
│ Tier 2: Checks (validated, not in prompt)              │
├─────────────────────────────────────────────────────────┤
│ Tier 3: Type Constraints (enforced via return type)    │ ← This document
└─────────────────────────────────────────────────────────┘
```

**Key Difference from Requirements/Checks:**
- Type constraints apply to **return values** after generation
- Type violations **do not trigger retries** (they indicate contract violations)
- Type constraints are **always enforced** for generative methods

## Type Constraint Architecture

### Core Components

```
┌──────────────────────────────────────────────────────────┐
│              TypeConstraint Class                        │
│  ┌────────────────────────────────────────────────┐     │
│  │ @type: Symbol[], Class, or Custom              │     │
│  └────────────────────────────────────────────────┘     │
│                                                          │
│  Methods:                                                │
│  ┌────────────────────────────────────────────────┐     │
│  │ validate(value) -> Boolean                      │     │
│  │ coerce(string_value) -> TypedValue              │     │
│  └────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
                          │
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   ┌────▼──────┐   ┌──────▼────┐   ┌──────▼──────┐
   │  Symbol   │   │   Class   │   │   Custom    │
   │Enumeration│   │ Based     │   │   Types     │
   └───────────┘   └───────────┘   └─────────────┘
```

### TypeConstraint Class Interface

```ruby
class TypeConstraint
  attr_reader :type

  def initialize(type)
    @type = type
  end

  # Check if value matches type constraint
  def validate(value) -> Boolean

  # Convert string to typed value
  def coerce(string_value) -> TypedValue

  private

  def symbol_enumeration?
    @type.is_a?(Array) && @type.all? { |t| t.is_a?(Symbol) }
  end

  def class_based?
    @type.is_a?(Class)
  end
end
```

### Type Classification

Type constraints are classified into three categories:

**1. Symbol Enumeration:**
```ruby
TypeConstraint.new([:positive, :negative, :neutral])
```

**2. Class-Based:**
```ruby
TypeConstraint.new(String)
TypeConstraint.new(Integer)
TypeConstraint.new(Float)
TypeConstraint.new(Hash)
TypeConstraint.new(Array)
```

**3. Custom Types (Future):**
```ruby
TypeConstraint.new(EmailAddress)
TypeConstraint.new(PhoneNumber)
```

## Symbol Enumeration Constraints

### Purpose

Symbol enumerations are ideal for **classification tasks** where the output must be one of a fixed set of values.

### Definition

```ruby
constraint = TypeConstraint.new([:positive, :negative, :neutral])
```

**Properties:**
- `@type` is an Array of Symbols
- All elements must be Symbols
- Order is not significant
- No duplicates allowed (by design)

### Validation

```ruby
def validate(value)
  return false unless value.is_a?(Symbol)
  @type.include?(value)
end
```

**Examples:**

```ruby
constraint = TypeConstraint.new([:red, :green, :blue])

constraint.validate(:red)     # => true
constraint.validate(:green)   # => true
constraint.validate(:yellow)  # => false
constraint.validate("red")    # => false (must be Symbol)
constraint.validate(:Red)     # => false (case-sensitive)
```

### Coercion

LLM outputs are strings, so automatic coercion to symbols is essential:

```ruby
def coerce(value)
  return value if value.is_a?(Symbol) && @type.include?(value)

  # Convert string to symbol
  if value.is_a?(String)
    symbolized = value.strip.downcase.to_sym

    if @type.include?(symbolized)
      return symbolized
    end

    raise ValidationError,
          "Invalid return value: '#{value}'. Must be one of: #{@type.join(', ')}"
  end

  raise ValidationError,
        "Cannot coerce #{value.class} to symbol enumeration"
end
```

**Coercion Rules:**
1. Strip whitespace from string
2. Convert to lowercase
3. Convert to symbol
4. Validate against enumeration
5. Raise error if not in enumeration

**Examples:**

```ruby
constraint = TypeConstraint.new([:positive, :negative])

constraint.coerce("positive")    # => :positive
constraint.coerce("POSITIVE")    # => :positive
constraint.coerce(" positive ")  # => :positive
constraint.coerce(:positive)     # => :positive (no-op)

constraint.coerce("neutral")     # => ValidationError
constraint.coerce(123)           # => ValidationError
```

### Case Sensitivity

**Symbol enumerations are case-insensitive during coercion:**
- Defined as: `[:positive, :negative]`
- LLM returns: `"Positive"` or `"POSITIVE"`
- Coerces to: `:positive`

**Rationale:** LLMs may vary capitalization, but semantic meaning is the same.

### Use Cases

**Classification:**
```ruby
generative def classify_sentiment(text:) -> [:positive, :negative, :neutral]
  "Classify the sentiment of: <%= text %>"
end
```

**Decision Making:**
```ruby
generative def should_approve(request:) -> [:approve, :reject, :escalate]
  "Should we approve this request: <%= request %>?"
end
```

**Enumerated Outputs:**
```ruby
generative def priority_level(task:) -> [:low, :medium, :high, :urgent]
  "What priority should this task have: <%= task %>?"
end
```

## Class-Based Type Constraints

### Supported Types

Russula supports five built-in class-based types:

| Type    | Purpose                  | Example                    |
|---------|--------------------------|----------------------------|
| String  | Text output (pass-through) | `"Hello world"`          |
| Integer | Whole numbers            | `42`                       |
| Float   | Decimal numbers          | `3.14`                     |
| Hash    | Structured data (JSON)   | `{"name" => "Alice"}`      |
| Array   | Lists (JSON)             | `["a", "b", "c"]`          |

### String Type Constraint

**Definition:**
```ruby
constraint = TypeConstraint.new(String)
```

**Behavior:**
- **Validation**: Checks `value.is_a?(String)`
- **Coercion**: Pass-through (LLM output is already a string)

**Example:**
```ruby
generative def summarize(text:) -> String
  "Summarize this text: <%= text %>"
end

# LLM returns: "This is a summary."
# Type constraint: ✓ (already String)
# Method returns: "This is a summary."
```

**Edge Cases:**
- Empty strings are valid
- Multi-line strings are valid
- Strings with special characters are valid

### Integer Type Constraint

**Definition:**
```ruby
constraint = TypeConstraint.new(Integer)
```

**Validation:**
```ruby
def validate(value)
  value.is_a?(Integer)
end
```

**Coercion:**
```ruby
def coerce(value)
  return value if value.is_a?(Integer)

  if value.is_a?(String)
    Integer(value.strip)
  else
    raise ValidationError, "Cannot coerce #{value.class} to Integer"
  end
rescue ArgumentError => e
  raise ValidationError,
        "Invalid Integer: '#{value}'. Must be a valid integer string."
end
```

**Coercion Rules:**
1. Strip whitespace
2. Use Ruby's `Integer()` for parsing
3. Supports negative numbers
4. Does NOT support floats (e.g., "3.14" raises error)

**Examples:**
```ruby
constraint = TypeConstraint.new(Integer)

constraint.coerce("42")      # => 42
constraint.coerce("-100")    # => -100
constraint.coerce(" 123 ")   # => 123
constraint.coerce(456)       # => 456 (no-op)

constraint.coerce("3.14")    # => ValidationError
constraint.coerce("abc")     # => ValidationError
constraint.coerce("")        # => ValidationError
```

**Use Cases:**
```ruby
generative def count_words(text:) -> Integer
  "Count the number of words in: <%= text %>"
end

generative def extract_year(text:) -> Integer
  "Extract the year from: <%= text %>"
end
```

### Float Type Constraint

**Definition:**
```ruby
constraint = TypeConstraint.new(Float)
```

**Validation:**
```ruby
def validate(value)
  value.is_a?(Float)
end
```

**Coercion:**
```ruby
def coerce(value)
  return value if value.is_a?(Float)

  if value.is_a?(String)
    Float(value.strip)
  elsif value.is_a?(Integer)
    value.to_f
  else
    raise ValidationError, "Cannot coerce #{value.class} to Float"
  end
rescue ArgumentError => e
  raise ValidationError,
        "Invalid Float: '#{value}'. Must be a valid float string."
end
```

**Coercion Rules:**
1. Strip whitespace
2. Use Ruby's `Float()` for parsing
3. Supports scientific notation (e.g., "1.5e10")
4. Converts integers to floats

**Examples:**
```ruby
constraint = TypeConstraint.new(Float)

constraint.coerce("3.14")      # => 3.14
constraint.coerce("-2.5")      # => -2.5
constraint.coerce("1.5e10")    # => 15000000000.0
constraint.coerce(42)          # => 42.0
constraint.coerce(" 3.14 ")    # => 3.14

constraint.coerce("abc")       # => ValidationError
constraint.coerce("")          # => ValidationError
```

**Use Cases:**
```ruby
generative def calculate_price(items:) -> Float
  "Calculate total price for: <%= items %>"
end

generative def extract_temperature(text:) -> Float
  "Extract temperature in Celsius from: <%= text %>"
end
```

### Hash Type Constraint

**Definition:**
```ruby
constraint = TypeConstraint.new(Hash)
```

**Purpose:** Structured data extraction from LLM outputs.

**Validation:**
```ruby
def validate(value)
  value.is_a?(Hash)
end
```

**Coercion:**
```ruby
require 'json'

def coerce(value)
  return value if value.is_a?(Hash)

  if value.is_a?(String)
    # Try to parse as JSON
    JSON.parse(value.strip)
  else
    raise ValidationError, "Cannot coerce #{value.class} to Hash"
  end
rescue JSON::ParserError => e
  raise ValidationError,
        "Invalid JSON for Hash: '#{value}'. Error: #{e.message}"
end
```

**Coercion Rules:**
1. Strip whitespace
2. Parse as JSON using `JSON.parse`
3. Return parsed Hash
4. Keys are strings (not symbols) by default

**Examples:**
```ruby
constraint = TypeConstraint.new(Hash)

constraint.coerce('{"name": "Alice", "age": 30}')
# => {"name" => "Alice", "age" => 30}

constraint.coerce('{"status": "ok"}')
# => {"status" => "ok"}

constraint.coerce('{}')
# => {}

constraint.coerce({"key" => "value"})
# => {"key" => "value"} (no-op)

constraint.coerce('not valid json')
# => ValidationError
```

**JSON Format Requirements:**
- Must be valid JSON
- Use double quotes for strings (not single quotes)
- Keys are returned as strings
- Nested hashes are supported

**Use Cases:**
```ruby
generative def extract_person_info(text:) -> Hash
  "Extract name, age, and city from: <%= text %>. Return as JSON."
end

# LLM returns: '{"name": "Alice", "age": 30, "city": "NYC"}'
# Coerced to: {"name" => "Alice", "age" => 30, "city" => "NYC"}
```

**Common LLM Response Formats:**
```
Good (valid JSON):
{"name": "Alice", "age": 30}

Good (nested):
{"person": {"name": "Alice"}, "location": "NYC"}

Bad (single quotes):
{'name': 'Alice'}  ❌

Bad (unquoted keys):
{name: "Alice"}  ❌

Bad (trailing comma):
{"name": "Alice",}  ❌
```

### Array Type Constraint

**Definition:**
```ruby
constraint = TypeConstraint.new(Array)
```

**Purpose:** Lists, collections, or sequences from LLM outputs.

**Validation:**
```ruby
def validate(value)
  value.is_a?(Array)
end
```

**Coercion:**
```ruby
require 'json'

def coerce(value)
  return value if value.is_a?(Array)

  if value.is_a?(String)
    JSON.parse(value.strip)
  else
    raise ValidationError, "Cannot coerce #{value.class} to Array"
  end
rescue JSON::ParserError => e
  raise ValidationError,
        "Invalid JSON for Array: '#{value}'. Error: #{e.message}"
end
```

**Coercion Rules:**
1. Strip whitespace
2. Parse as JSON using `JSON.parse`
3. Verify result is an Array
4. Return parsed Array

**Examples:**
```ruby
constraint = TypeConstraint.new(Array)

constraint.coerce('["a", "b", "c"]')
# => ["a", "b", "c"]

constraint.coerce('[1, 2, 3]')
# => [1, 2, 3]

constraint.coerce('[]')
# => []

constraint.coerce('[{"name": "Alice"}]')
# => [{"name" => "Alice"}]

constraint.coerce(['x', 'y'])
# => ['x', 'y'] (no-op)

constraint.coerce('not valid json')
# => ValidationError
```

**Use Cases:**
```ruby
generative def extract_keywords(text:) -> Array
  "Extract keywords from: <%= text %>. Return as JSON array."
end

# LLM returns: '["machine learning", "AI", "neural networks"]'
# Coerced to: ["machine learning", "AI", "neural networks"]

generative def list_steps(task:) -> Array
  "Break down this task into steps: <%= task %>. Return as JSON array."
end

# LLM returns: '["Step 1", "Step 2", "Step 3"]'
# Coerced to: ["Step 1", "Step 2", "Step 3"]
```

**JSON Format Requirements:**
- Must be valid JSON
- Use double quotes for strings
- Nested arrays/hashes supported
- Empty arrays are valid

## Coercion System

### Coercion Philosophy

**Goal:** Bridge the gap between untyped LLM text outputs and typed Ruby values.

**Principles:**
1. **Automatic**: Coercion happens transparently
2. **Conservative**: Only apply safe, unambiguous conversions
3. **Fail-Fast**: Raise clear errors for invalid coercions
4. **Idempotent**: Coercing a correctly-typed value is a no-op

### Coercion Flow

```
┌─────────────────────────────────────────────────────────┐
│ 1. LLM generates string output                          │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 2. TypeConstraint.coerce(string) called                 │
└────────────────┬────────────────────────────────────────┘
                 │
      ┌──────────┴──────────┐
      │                     │
      ▼                     ▼
┌──────────────┐   ┌───────────────────┐
│ Type Check   │   │ Already Correct   │
│ Dispatches   │   │ Type? Return      │
└──────┬───────┘   └───────────────────┘
       │
       ├─ Symbol Enum → String → Symbol → Validate
       ├─ Integer → String → Integer()
       ├─ Float → String → Float()
       ├─ Hash → String → JSON.parse → Hash
       ├─ Array → String → JSON.parse → Array
       └─ String → Pass-through
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Return typed value OR raise ValidationError          │
└─────────────────────────────────────────────────────────┘
```

### Coercion Table

| Target Type      | Input Type | Coercion Method              | Example                                |
|------------------|------------|------------------------------|----------------------------------------|
| Symbol Enum      | String     | `.strip.downcase.to_sym`     | `"Positive"` → `:positive`             |
| Symbol Enum      | Symbol     | Validate only                | `:positive` → `:positive`              |
| Integer          | String     | `Integer(value.strip)`       | `"42"` → `42`                          |
| Integer          | Integer    | Pass-through                 | `42` → `42`                            |
| Float            | String     | `Float(value.strip)`         | `"3.14"` → `3.14`                      |
| Float            | Integer    | `.to_f`                      | `42` → `42.0`                          |
| Float            | Float      | Pass-through                 | `3.14` → `3.14`                        |
| Hash             | String     | `JSON.parse`                 | `'{"a":1}'` → `{"a" => 1}`             |
| Hash             | Hash       | Pass-through                 | `{a: 1}` → `{a: 1}`                    |
| Array            | String     | `JSON.parse`                 | `'[1,2,3]'` → `[1, 2, 3]`              |
| Array            | Array      | Pass-through                 | `[1, 2]` → `[1, 2]`                    |
| String           | String     | Pass-through                 | `"text"` → `"text"`                    |

### Error Messages

Coercion errors must be clear and actionable:

**Symbol Enumeration Error:**
```ruby
raise ValidationError,
      "Invalid return value: 'happy'. Must be one of: positive, negative, neutral"
```

**Integer Error:**
```ruby
raise ValidationError,
      "Invalid Integer: 'abc'. Must be a valid integer string."
```

**Float Error:**
```ruby
raise ValidationError,
      "Invalid Float: 'not_a_number'. Must be a valid float string."
```

**Hash Error:**
```ruby
raise ValidationError,
      "Invalid JSON for Hash: '{not valid}'. Error: unexpected token at '{not valid}'"
```

**Array Error:**
```ruby
raise ValidationError,
      "Invalid JSON for Array: '[1, 2,'. Error: unexpected end of JSON input"
```

## Validation Algorithm

### Validation vs Coercion

**Key Distinction:**
- **Validation**: Checks if value is correct type (returns boolean)
- **Coercion**: Converts value to correct type (returns typed value or raises)

### Validation Algorithm

```ruby
def validate(value)
  case @type
  when Array
    # Symbol enumeration
    if symbol_enumeration?
      value.is_a?(Symbol) && @type.include?(value)
    else
      # Future: Typed arrays
      value.is_a?(Array)
    end
  when Class
    # Class-based constraint
    value.is_a?(@type)
  else
    # Custom type (future)
    @type.respond_to?(:===) && @type === value
  end
end
```

### Coercion Algorithm

```ruby
def coerce(value)
  # Fast path: already correct type
  return value if validate(value)

  # Dispatch to type-specific coercion
  case @type
  when Array
    coerce_symbol_enumeration(value) if symbol_enumeration?
  when String
    coerce_string(value)
  when Integer
    coerce_integer(value)
  when Float
    coerce_float(value)
  when Hash
    coerce_hash(value)
  when Array
    coerce_array(value)
  else
    coerce_custom_type(value)
  end
rescue StandardError => e
  raise ValidationError, "Coercion failed: #{e.message}"
end
```

### Integration with Generative Methods

Type constraints are applied **after** LLM generation:

```
1. User calls generative method
       │
       ▼
2. Method wrapper calls session.instruct()
       │
       ▼
3. LLM generates string output
       │
       ▼
4. Requirements/checks validated (optional)
       │
       ▼
5. TypeConstraint.coerce(output) ← Type system activates
       │
       ├─ Success: Return typed value
       └─ Failure: Raise ValidationError
```

**Implementation in Generative Wrapper:**
```ruby
def generative_method_wrapper(session, **args)
  # 1. Render docstring with args
  prompt = render_docstring(args)

  # 2. Call session.instruct
  output = session.instruct(prompt)

  # 3. Apply type constraint
  type_constraint = TypeConstraint.new(return_type)
  typed_value = type_constraint.coerce(output.value)

  # 4. Return typed value
  typed_value
end
```

## Error Specification

### ValidationError Structure

```ruby
class ValidationError < Error
  attr_reader :value, :expected_type, :coercion_error

  def initialize(message, value: nil, expected_type: nil, coercion_error: nil)
    super(message)
    @value = value
    @expected_type = expected_type
    @coercion_error = coercion_error
  end
end
```

### Error Scenarios

**1. Symbol Enumeration Violation:**
```ruby
constraint = TypeConstraint.new([:positive, :negative])
constraint.coerce("neutral")

# Raises:
# ValidationError: Invalid return value: 'neutral'. Must be one of: positive, negative
```

**2. Integer Coercion Failure:**
```ruby
constraint = TypeConstraint.new(Integer)
constraint.coerce("not_a_number")

# Raises:
# ValidationError: Invalid Integer: 'not_a_number'. Must be a valid integer string.
```

**3. JSON Parse Failure:**
```ruby
constraint = TypeConstraint.new(Hash)
constraint.coerce("{invalid json")

# Raises:
# ValidationError: Invalid JSON for Hash: '{invalid json'. Error: unexpected token at '{invalid json'
```

**4. Type Mismatch:**
```ruby
constraint = TypeConstraint.new(Integer)
constraint.validate("42")  # String, not Integer

# Returns: false
```

### Error Handling Best Practices

**In User Code:**
```ruby
begin
  result = classifier.classify_sentiment(session, text: input)
rescue Russula::ValidationError => e
  puts "Type validation failed: #{e.message}"
  puts "Expected: #{e.expected_type}"
  puts "Got: #{e.value}"
end
```

**No Retries for Type Errors:**

Unlike requirement/check failures, type constraint violations **do not trigger retries**:
- **Rationale**: Type errors indicate a contract violation between user and LLM, not a generation quality issue
- **Behavior**: Raise error immediately, propagate to user
- **User Action**: Fix prompt or adjust type constraint

## Integration with Generative Methods

### Return Type Syntax

```ruby
generative def method_name -> ReturnTypeConstraint
  "docstring"
end
```

**Supported Syntaxes:**

**Symbol Enumeration:**
```ruby
generative def classify -> [:positive, :negative, :neutral]
  "Classify sentiment"
end
```

**Class-Based:**
```ruby
generative def summarize -> String
  "Summarize text"
end

generative def count -> Integer
  "Count words"
end

generative def extract -> Hash
  "Extract structured data"
end
```

### Method Wrapper Implementation

The generative method wrapper must:

1. **Capture return type** from method signature
2. **Call session.instruct** with rendered prompt
3. **Apply type constraint** to output
4. **Return typed value** to user

**Simplified Implementation:**
```ruby
module Generative
  module ClassMethods
    def generative(method_def)
      # Parse return type from method signature
      # (Implementation detail: use method_added hook)

      method_name = extract_method_name(method_def)
      return_type = extract_return_type(method_def)

      # Store metadata
      generative_methods[method_name] = {
        return_type: return_type,
        docstring: extract_docstring(method_def)
      }

      # Wrap method
      original_method = instance_method(method_name)

      define_method(method_name) do |session, **args|
        raise ArgumentError, "session required" unless session

        # Render docstring
        docstring = self.class.generative_methods[method_name][:docstring]
        prompt = ERB.new(docstring).result_with_hash(args)

        # Generate
        output = session.instruct(prompt)

        # Apply type constraint
        type_constraint = TypeConstraint.new(return_type)
        type_constraint.coerce(output.value)
      end
    end
  end
end
```

### Example Flow

**Definition:**
```ruby
class Classifier
  include Russula::Generative

  generative def classify(text:) -> [:positive, :negative]
    "Classify: <%= text %>"
  end
end
```

**Invocation:**
```ruby
classifier = Classifier.new
result = classifier.classify(session, text: "I love this!")

# Internally:
# 1. Render: "Classify: I love this!"
# 2. Generate: LLM returns "positive"
# 3. Coerce: "positive" → :positive
# 4. Return: :positive
```

## Extensibility

### Custom Type Constraints (Future)

**Goal:** Allow users to define domain-specific types.

**Example:**
```ruby
class EmailAddress
  def self.===(value)
    value.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
  end

  def self.coerce(value)
    if value.is_a?(String) && self === value
      value.strip.downcase
    else
      raise ValidationError, "Invalid email address: #{value}"
    end
  end
end

# Usage:
generative def extract_email(text:) -> EmailAddress
  "Extract email from: <%= text %>"
end
```

**TypeConstraint Extension:**
```ruby
def coerce(value)
  # ...existing code...

  # Custom type handling
  if @type.respond_to?(:coerce)
    @type.coerce(value)
  elsif @type.respond_to?(:===)
    @type === value ? value : raise_error
  else
    raise ValidationError, "Unknown type constraint: #{@type}"
  end
end
```

### Parameterized Types (Future)

**Goal:** Support types with parameters (e.g., `Array<Integer>`).

**Example:**
```ruby
generative def extract_numbers(text:) -> Array<Integer>
  "Extract numbers from: <%= text %>"
end

# LLM returns: "[1, 2, 3]"
# Coerced to: [1, 2, 3]
# Validated: All elements are Integers
```

**Implementation Sketch:**
```ruby
class ParameterizedTypeConstraint < TypeConstraint
  def initialize(container_type, element_type)
    @container_type = container_type
    @element_type = element_type
  end

  def validate(value)
    return false unless value.is_a?(@container_type)
    value.all? { |elem| @element_type === elem }
  end

  def coerce(value)
    container = super  # Use base coercion for container

    # Coerce each element
    container.map do |elem|
      TypeConstraint.new(@element_type).coerce(elem)
    end
  end
end
```

### Union Types (Future)

**Goal:** Support multiple possible types (e.g., `Integer | Float`).

**Example:**
```ruby
generative def parse_number(text:) -> Integer | Float
  "Parse number from: <%= text %>"
end

# Could return either 42 (Integer) or 3.14 (Float)
```

**Implementation Sketch:**
```ruby
class UnionTypeConstraint < TypeConstraint
  def initialize(*types)
    @types = types
  end

  def validate(value)
    @types.any? { |type| TypeConstraint.new(type).validate(value) }
  end

  def coerce(value)
    # Try each type in order
    @types.each do |type|
      begin
        return TypeConstraint.new(type).coerce(value)
      rescue ValidationError
        next
      end
    end

    raise ValidationError, "Could not coerce to any of: #{@types.join(', ')}"
  end
end
```

## Best Practices

### Choosing the Right Type

**Use Symbol Enumerations for:**
- Classification tasks
- Multiple-choice outputs
- Enumerated decisions
- Categorical data

**Use String for:**
- Open-ended text generation
- Summaries, descriptions
- Creative writing
- Natural language responses

**Use Integer for:**
- Counts, quantities
- Ordinal values (rank, position)
- Years, ages
- Discrete numeric values

**Use Float for:**
- Prices, amounts
- Measurements (temperature, distance)
- Percentages, ratios
- Continuous numeric values

**Use Hash for:**
- Structured data extraction
- Multiple related fields
- Key-value pairs
- Entity attributes

**Use Array for:**
- Lists, collections
- Multiple items
- Sequences, steps
- Tags, keywords

### Prompt Design for Type Constraints

**For Symbol Enumerations:**
```ruby
# Good: Explicitly list options
generative def classify -> [:positive, :negative, :neutral]
  "Classify as positive, negative, or neutral: <%= text %>"
end

# Better: Include in requirements
generative def classify -> [:positive, :negative, :neutral]
  "Classify: <%= text %>"
end
# (Type constraint implicitly guides LLM)
```

**For Hash/Array:**
```ruby
# Good: Explicitly request JSON
generative def extract -> Hash
  "Extract data as JSON: <%= text %>"
end

# Better: Show JSON structure
generative def extract -> Hash
  "Extract data as JSON with keys 'name' and 'age': <%= text %>"
end
```

### Error Recovery

**Strategy 1: Fallback Types**
```ruby
begin
  result = method.extract_number(session, text: input)
rescue Russula::ValidationError
  # Fallback to string
  result = method.extract_text(session, text: input)
end
```

**Strategy 2: Retry with Modified Prompt**
```ruby
begin
  result = method.classify(session, text: input)
rescue Russula::ValidationError => e
  # Add explicit instruction
  session.push(temperature: 0.0)  # More deterministic
  result = method.classify(session, text: "#{input}\nRespond with exactly one word.")
  session.pop
end
```

**Strategy 3: Validate Before Coercion**
```ruby
# If unsure about LLM output quality:
generative def classify -> String  # Use String first
  "Classify as positive, negative, or neutral: <%= text %>"
end

# Then validate manually:
result = classifier.classify(session, text: input)
valid_values = [:positive, :negative, :neutral]
symbolized = result.strip.downcase.to_sym

unless valid_values.include?(symbolized)
  raise "Invalid classification: #{result}"
end
```

### Testing Type Constraints

**Test Validation:**
```ruby
RSpec.describe TypeConstraint do
  it 'validates symbol enumeration' do
    constraint = TypeConstraint.new([:a, :b, :c])

    expect(constraint.validate(:a)).to be true
    expect(constraint.validate(:d)).to be false
    expect(constraint.validate("a")).to be false
  end
end
```

**Test Coercion:**
```ruby
RSpec.describe TypeConstraint do
  it 'coerces string to symbol' do
    constraint = TypeConstraint.new([:positive, :negative])

    expect(constraint.coerce("positive")).to eq(:positive)
    expect(constraint.coerce("POSITIVE")).to eq(:positive)
  end

  it 'raises error for invalid value' do
    constraint = TypeConstraint.new([:positive, :negative])

    expect {
      constraint.coerce("invalid")
    }.to raise_error(ValidationError, /must be one of/)
  end
end
```

**Test Integration:**
```ruby
RSpec.describe Classifier do
  it 'returns typed symbol' do
    allow(session.backend).to receive(:generate).and_return("positive")

    result = classifier.classify(session, text: "I love this!")

    expect(result).to be_a(Symbol)
    expect(result).to eq(:positive)
  end
end
```

## Performance Considerations

### Coercion Cost

**Low Cost (Fast):**
- String (pass-through)
- Symbol enumeration (string manipulation)
- Integer/Float (built-in coercion)

**Medium Cost:**
- Hash (JSON parsing)
- Array (JSON parsing)

**High Cost (Future):**
- Custom types with complex validation
- Parameterized types (recursive validation)

### Optimization Strategies

**1. Cache Type Constraints:**
```ruby
# Don't recreate for every call
@type_constraint ||= TypeConstraint.new(return_type)
```

**2. Skip Validation if Unnecessary:**
```ruby
def coerce(value)
  return value if validate(value)  # Fast path
  # Expensive coercion only if needed
end
```

**3. Use Custom Validators for Performance:**
```ruby
# Slow: JSON parse + type check
generative def extract -> Hash
  "Extract as JSON"
end

# Fast: Custom validator
generative def extract -> String
  "Extract as key:value pairs"
end

# Then parse manually if needed
```

## See Also

- [Architecture Specification](ARCHITECTURE.md)
- [API Specification](API_SPECIFICATION.md)
- [Constraint System](CONSTRAINT_SYSTEM.md)
- [Validation Algorithm](VALIDATION_ALGORITHM.md)
- [Generative Methods DSL](GENERATIVE_METHODS_DSL.md)
