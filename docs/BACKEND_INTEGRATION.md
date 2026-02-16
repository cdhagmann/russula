# Backend Integration Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-02-16

## Table of Contents

1. [Overview](#overview)
2. [Backend Interface Contract](#backend-interface-contract)
3. [Message Protocol](#message-protocol)
4. [Configuration Options](#configuration-options)
5. [Error Handling](#error-handling)
6. [OpenAI Backend Specification](#openai-backend-specification)
7. [Backend Factory Pattern](#backend-factory-pattern)
8. [Future Backend Patterns](#future-backend-patterns)
9. [Implementation Checklist](#implementation-checklist)

## Overview

Russula uses a **Backend abstraction layer** to interface with different LLM providers (OpenAI, Anthropic, Ollama, etc.). This design ensures:

- **Provider Independence**: Core logic doesn't depend on specific LLM APIs
- **Extensibility**: New providers can be added without changing Session or constraint logic
- **Consistent Interface**: All backends expose the same methods and contracts
- **Error Translation**: Provider-specific errors are wrapped in Russula exceptions

### Architecture Role

```
Session
  ├─> Backend Interface
  │     ├─> Backend::OpenAI (ruby-openai gem)
  │     ├─> Backend::Anthropic (future)
  │     └─> Backend::Ollama (future)
  │
  └─> Context (message history)
```

The Session interacts exclusively with the Backend interface. The specific backend implementation handles:
1. Authentication with the provider
2. Message format translation
3. API calls and response parsing
4. Error wrapping

## Backend Interface Contract

All backends MUST implement the `Backend::Base` interface.

### Required Methods

#### `initialize(model:, **options)`

Create a new backend instance.

**Signature:**
```ruby
def initialize(model:, **options)
```

**Parameters:**
- `model` (String, required): Model identifier specific to the provider
  - OpenAI: `'gpt-4o'`, `'gpt-4o-mini'`, `'gpt-3.5-turbo'`
  - Anthropic: `'claude-3-opus-20240229'`, `'claude-3-sonnet-20240229'`
  - Ollama: `'llama2'`, `'mistral'`, etc.
- `**options` (Hash): Provider-specific options
  - Common: `temperature`, `max_tokens`, `top_p`
  - Provider-specific: See [Configuration Options](#configuration-options)

**Raises:**
- `Russula::BackendError`: If required parameters missing or invalid

**Responsibilities:**
1. Validate required parameters (`model` at minimum)
2. Store configuration in instance variables
3. Initialize provider SDK client (if applicable)
4. Do NOT make API calls (lazy initialization)

**Example:**
```ruby
class OpenAI < Base
  def initialize(api_key:, model:, **options)
    raise BackendError, 'API key required' unless api_key
    raise BackendError, 'Model required' unless model

    super(model: model, **options)
    @client = OpenAI::Client.new(access_token: api_key)
  end
end
```

---

#### `generate(messages, **options) -> String`

Generate a completion from message history.

**Signature:**
```ruby
def generate(messages, **options) -> String
```

**Parameters:**
- `messages` (Array<Hash>, required): Message history in standardized format
  - See [Message Protocol](#message-protocol) for structure
- `**options` (Hash, optional): Override options for this specific call
  - Merged with instance options
  - Call-specific options take precedence

**Returns:**
- String: The generated text content (ONLY the text, no metadata)

**Raises:**
- `Russula::BackendError`: On API errors, connection failures, or invalid responses

**Responsibilities:**
1. Translate Russula messages to provider format
2. Merge call-specific options with instance options
3. Make API request to provider
4. Extract text content from response
5. Validate response structure
6. Wrap any provider errors in `BackendError`

**Example:**
```ruby
def generate(messages, **options)
  params = build_parameters(messages, options)

  response = @client.chat(parameters: params)

  # Validate response structure
  unless response.dig('choices', 0, 'message', 'content')
    raise BackendError, 'Invalid response format'
  end

  response.dig('choices', 0, 'message', 'content')
rescue StandardError => e
  raise BackendError, "Generation failed: #{e.message}"
end
```

**Performance Considerations:**
- Should NOT cache responses (caching is Session's responsibility)
- Should NOT retry on failure (retry logic is Strategy's responsibility)
- Should be synchronous (streaming support is future work)

---

#### `update_options(**new_options) -> void`

Update backend configuration options.

**Signature:**
```ruby
def update_options(**new_options) -> void
```

**Parameters:**
- `**new_options` (Hash): Options to merge into current configuration

**Returns:** None (void)

**Side Effects:**
- Merges `new_options` into `@options` hash
- Does NOT make API calls
- Changes affect subsequent `generate()` calls

**Example:**
```ruby
def update_options(**new_options)
  @options.merge!(new_options)
end
```

**Usage:**
```ruby
backend = Backend::OpenAI.new(api_key: key, model: 'gpt-4o-mini')
backend.options[:temperature]  # => nil (or default)

backend.update_options(temperature: 0.9, max_tokens: 500)
backend.options[:temperature]  # => 0.9
```

---

#### `model -> String`

Get the current model identifier.

**Signature:**
```ruby
attr_reader :model
# or
def model
  @model
end
```

**Returns:**
- String: Model identifier

**Example:**
```ruby
backend.model  # => 'gpt-4o-mini'
```

---

#### `options -> Hash`

Get current backend options.

**Signature:**
```ruby
attr_reader :options
# or
def options
  @options
end
```

**Returns:**
- Hash: Current options hash

**Example:**
```ruby
backend.options  # => {temperature: 0.7, max_tokens: 1000}
```

---

### Interface Summary

```ruby
module Russula
  module Backend
    class Base
      attr_reader :model, :options

      def initialize(model:, **options)
        raise NotImplementedError, 'Subclass must implement initialize'
      end

      def generate(messages, **options)
        raise NotImplementedError, 'Subclass must implement generate'
      end

      def update_options(**new_options)
        @options.merge!(new_options)
      end
    end
  end
end
```

## Message Protocol

Russula uses a **standardized message format** independent of provider-specific formats.

### Russula Message Structure

```ruby
{
  role: Symbol,     # :system, :user, or :assistant
  content: String   # Message text content
}
```

**Fields:**

- `role` (Symbol, required): Message author
  - `:system`: System-level instructions (provider-dependent support)
  - `:user`: User/human messages
  - `:assistant`: Model/assistant responses

- `content` (String, required): Message text
  - Plain text string
  - Provider-specific formatting (Markdown, etc.) allowed
  - No nested structures in MVP

**Example Message Array:**
```ruby
messages = [
  {role: :system, content: 'You are a helpful assistant.'},
  {role: :user, content: 'Hello!'},
  {role: :assistant, content: 'Hi there! How can I help?'},
  {role: :user, content: 'What is the weather?'}
]
```

### Provider Translation

Backends MUST translate Russula messages to provider-specific formats.

#### OpenAI Format

OpenAI expects:
```ruby
{
  "role": "system" | "user" | "assistant",
  "content": "string"
}
```

**Translation:**
```ruby
def translate_messages(messages)
  messages.map do |msg|
    {
      "role" => msg[:role].to_s,
      "content" => msg[:content]
    }
  end
end
```

#### Anthropic Format (Future)

Anthropic expects:
```ruby
{
  "role": "user" | "assistant",
  "content": "string"
}
```

**Translation Notes:**
- Anthropic doesn't support `system` role in messages array
- System prompt is a separate parameter
- Requires special handling:

```ruby
def translate_messages(messages)
  system_msg = messages.find { |m| m[:role] == :system }
  non_system = messages.reject { |m| m[:role] == :system }

  {
    system: system_msg&.[](:content),
    messages: non_system.map { |m|
      {"role" => m[:role].to_s, "content" => m[:content]}
    }
  }
end
```

#### Ollama Format (Future)

Ollama expects similar format to OpenAI:
```ruby
{
  "role": "system" | "user" | "assistant",
  "content": "string"
}
```

**Translation:**
```ruby
def translate_messages(messages)
  messages.map do |msg|
    {
      "role" => msg[:role].to_s,
      "content" => msg[:content]
    }
  end
end
```

### Message Validation

Backends SHOULD validate messages before sending:

```ruby
def validate_messages(messages)
  raise BackendError, 'Messages must be an array' unless messages.is_a?(Array)
  raise BackendError, 'Messages cannot be empty' if messages.empty?

  messages.each_with_index do |msg, idx|
    unless msg.is_a?(Hash) && msg[:role] && msg[:content]
      raise BackendError, "Invalid message at index #{idx}"
    end

    unless [:system, :user, :assistant].include?(msg[:role])
      raise BackendError, "Invalid role at index #{idx}: #{msg[:role]}"
    end
  end
end
```

**Design Decision:** Validation at the backend level provides better error messages than cryptic provider API errors.

## Configuration Options

### Standard Options

These options are supported across most providers:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `temperature` | Float | Provider default (usually 1.0) | Sampling temperature (0.0-2.0). Lower = more deterministic. |
| `max_tokens` | Integer | Provider default | Maximum tokens to generate |
| `top_p` | Float | Provider default (usually 1.0) | Nucleus sampling threshold (0.0-1.0) |
| `stop` | Array<String> or String | nil | Stop sequences to end generation |
| `presence_penalty` | Float | 0.0 | Presence penalty (-2.0 to 2.0) |
| `frequency_penalty` | Float | 0.0 | Frequency penalty (-2.0 to 2.0) |

**Usage:**
```ruby
backend = Backend::OpenAI.new(
  api_key: key,
  model: 'gpt-4o-mini',
  temperature: 0.7,
  max_tokens: 500
)
```

### Provider-Specific Options

#### OpenAI-Specific

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api_key` | String | Required | OpenAI API key |
| `organization` | String | nil | Organization ID (optional) |
| `n` | Integer | 1 | Number of completions to generate |
| `logit_bias` | Hash | nil | Token bias adjustments |
| `user` | String | nil | User identifier for tracking |

#### Anthropic-Specific (Future)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api_key` | String | Required | Anthropic API key |
| `max_tokens_to_sample` | Integer | Required | Maximum tokens (required by Anthropic) |
| `anthropic_version` | String | '2023-06-01' | API version |

#### Ollama-Specific (Future)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `base_url` | String | 'http://localhost:11434' | Ollama server URL |
| `num_ctx` | Integer | 2048 | Context window size |
| `num_predict` | Integer | 128 | Number of tokens to predict |

### Option Inheritance and Merging

Options flow through multiple layers:

```
1. Backend instance options (from initialize)
   ↓
2. Session options (from start_session)
   ↓
3. Session.push() temporary options
   ↓
4. generate() call-specific options
   ↓ (final merged options)
5. Backend.generate() receives merged options
```

**Merge Behavior:**
```ruby
def build_parameters(messages, call_options)
  # Instance options < Call options
  merged_options = @options.merge(call_options)

  {
    model: @model,
    messages: translate_messages(messages),
    **merged_options
  }
end
```

**Example:**
```ruby
# Layer 1: Backend instance
backend = Backend::OpenAI.new(
  api_key: key,
  model: 'gpt-4o-mini',
  temperature: 0.5
)

# Layer 2: Session
session = Session.new(backend: backend)

# Layer 3: Temporary push
session.push(temperature: 0.9)  # Overrides 0.5

# Layer 4: Call-specific
backend.generate(messages, max_tokens: 100)
# Final options: {temperature: 0.9, max_tokens: 100}
```

### Option Validation

Backends SHOULD validate option values:

```ruby
def validate_options(options)
  if options[:temperature]
    temp = options[:temperature]
    unless temp.is_a?(Numeric) && temp >= 0.0 && temp <= 2.0
      raise BackendError, "temperature must be 0.0-2.0, got #{temp}"
    end
  end

  if options[:max_tokens]
    max = options[:max_tokens]
    unless max.is_a?(Integer) && max > 0
      raise BackendError, "max_tokens must be positive integer, got #{max}"
    end
  end
end
```

**Trade-off:** Validation at backend level catches errors early, but adds overhead.

## Error Handling

### Error Types

All backend errors are wrapped in `Russula::BackendError`:

```ruby
module Russula
  class Error < StandardError; end

  class BackendError < Error
    attr_reader :cause

    def initialize(message, cause: nil)
      super(message)
      @cause = cause
    end
  end
end
```

### Error Translation

Backends MUST catch provider-specific errors and wrap them:

```ruby
def generate(messages, **options)
  # ... implementation ...
rescue OpenAI::Error => e
  raise BackendError.new("OpenAI API error: #{e.message}", cause: e)
rescue Faraday::Error => e
  raise BackendError.new("Network error: #{e.message}", cause: e)
rescue JSON::ParserError => e
  raise BackendError.new("Invalid JSON response: #{e.message}", cause: e)
rescue StandardError => e
  raise BackendError.new("Unexpected error: #{e.message}", cause: e)
end
```

### Common Error Scenarios

#### 1. Missing API Key

```ruby
def initialize(api_key:, model:, **options)
  raise BackendError, 'API key required' unless api_key
  # ...
end
```

**Error Message:** `"API key required"`

---

#### 2. Invalid Model

```ruby
def initialize(api_key:, model:, **options)
  raise BackendError, 'Model required' unless model
  # ...
end
```

**Error Message:** `"Model required"`

---

#### 3. API Failure

```ruby
rescue OpenAI::Error => e
  raise BackendError, "OpenAI API error: #{e.message}"
end
```

**Error Message:** `"OpenAI API error: Invalid API key provided"`

---

#### 4. Invalid Response Format

```ruby
def generate(messages, **options)
  response = @client.chat(parameters: params)

  unless response.dig('choices', 0, 'message', 'content')
    raise BackendError, 'Invalid response format'
  end

  response.dig('choices', 0, 'message', 'content')
end
```

**Error Message:** `"Invalid response format"`

---

#### 5. Network Errors

```ruby
rescue Faraday::ConnectionFailed => e
  raise BackendError, "Connection failed: #{e.message}"
rescue Faraday::TimeoutError => e
  raise BackendError, "Request timeout: #{e.message}"
end
```

**Error Messages:**
- `"Connection failed: Connection refused"`
- `"Request timeout: execution expired"`

### Error Message Guidelines

1. **Be Specific**: Include provider name and error type
2. **Preserve Original**: Store original exception in `cause`
3. **User-Friendly**: Avoid internal implementation details
4. **Actionable**: Suggest fixes when possible

**Good:**
```ruby
raise BackendError, 'API key required. Set OPENAI_API_KEY environment variable.'
```

**Bad:**
```ruby
raise BackendError, 'nil value in @api_key instance variable'
```

## OpenAI Backend Specification

This is the MVP backend implementation.

### Class Definition

```ruby
require 'openai'

module Russula
  module Backend
    class OpenAI < Base
      def initialize(api_key:, model:, **options)
        raise BackendError, 'API key required' unless api_key
        raise BackendError, 'Model required' unless model

        super(model: model, **options)
        @client = ::OpenAI::Client.new(access_token: api_key)
      end

      def generate(messages, **options)
        params = build_parameters(messages, options)

        response = @client.chat(parameters: params)

        unless response.dig('choices', 0, 'message', 'content')
          raise BackendError, 'Invalid response format'
        end

        response.dig('choices', 0, 'message', 'content')
      rescue ::OpenAI::Error => e
        raise BackendError, "OpenAI API error: #{e.message}"
      rescue Faraday::Error => e
        raise BackendError, "Network error: #{e.message}"
      rescue StandardError => e
        raise BackendError, "Generation failed: #{e.message}"
      end

      private

      def build_parameters(messages, call_options)
        merged_options = @options.merge(call_options)

        {
          model: @model,
          messages: translate_messages(messages),
          **merged_options
        }
      end

      def translate_messages(messages)
        messages.map do |msg|
          {
            "role" => msg[:role].to_s,
            "content" => msg[:content]
          }
        end
      end
    end
  end
end
```

### Supported Models

As of 2024-01:
- `gpt-4o`: Latest GPT-4 optimized model
- `gpt-4o-mini`: Smaller, faster GPT-4 optimized model
- `gpt-4-turbo`: GPT-4 Turbo with vision
- `gpt-4`: Original GPT-4
- `gpt-3.5-turbo`: GPT-3.5 Turbo

**Recommendation:** Use `gpt-4o-mini` for MVP (cost-effective, fast).

### Supported Options

All standard options plus OpenAI-specific options:

```ruby
backend = Backend::OpenAI.new(
  api_key: ENV['OPENAI_API_KEY'],
  model: 'gpt-4o-mini',

  # Standard options
  temperature: 0.7,
  max_tokens: 500,
  top_p: 1.0,
  stop: ["\n\n", "END"],
  presence_penalty: 0.0,
  frequency_penalty: 0.0,

  # OpenAI-specific
  organization: 'org-xxx',
  n: 1,
  logit_bias: {"50256" => -100},
  user: 'user-123'
)
```

### Response Structure

OpenAI returns:
```ruby
{
  "id" => "chatcmpl-xxx",
  "object" => "chat.completion",
  "created" => 1234567890,
  "model" => "gpt-4o-mini",
  "choices" => [
    {
      "index" => 0,
      "message" => {
        "role" => "assistant",
        "content" => "Generated text here"
      },
      "finish_reason" => "stop"
    }
  ],
  "usage" => {
    "prompt_tokens" => 10,
    "completion_tokens" => 20,
    "total_tokens" => 30
  }
}
```

**Extraction:**
```ruby
response.dig('choices', 0, 'message', 'content')
# => "Generated text here"
```

### Testing

See `spec/russula/backend_spec.rb` for expected behavior:

```ruby
describe 'Backend::OpenAI' do
  let(:backend) do
    Russula::Backend::OpenAI.new(
      api_key: ENV['OPENAI_API_KEY'] || 'test-key',
      model: 'gpt-4o-mini'
    )
  end

  describe '#generate' do
    it 'generates a response', :vcr do
      messages = [
        {role: :system, content: 'You are a helpful assistant.'},
        {role: :user, content: 'Say hello.'}
      ]

      response = backend.generate(messages)

      expect(response).to be_a(String)
      expect(response.length).to be > 0
    end
  end
end
```

## Backend Factory Pattern

The factory provides a unified creation interface.

### Factory Implementation

```ruby
module Russula
  module Backend
    def self.create(type:, **options)
      case type
      when :openai
        require_relative 'backend/openai'
        OpenAI.new(**options)
      when :anthropic
        require_relative 'backend/anthropic'
        Anthropic.new(**options)
      when :ollama
        require_relative 'backend/ollama'
        Ollama.new(**options)
      else
        raise BackendError, "Unsupported backend type: #{type}"
      end
    end
  end
end
```

### Usage

```ruby
# Direct instantiation
backend = Russula::Backend::OpenAI.new(
  api_key: key,
  model: 'gpt-4o-mini'
)

# Factory creation
backend = Russula::Backend.create(
  type: :openai,
  api_key: key,
  model: 'gpt-4o-mini'
)

# Via Session (uses factory internally)
session = Russula.start_session(
  backend: :openai,
  api_key: key,
  model: 'gpt-4o-mini'
)
```

### Error Handling

```ruby
backend = Russula::Backend.create(
  type: :unknown,
  api_key: key,
  model: 'some-model'
)
# => raises BackendError: "Unsupported backend type: unknown"
```

## Future Backend Patterns

### Anthropic Backend (Future)

```ruby
module Russula
  module Backend
    class Anthropic < Base
      def initialize(api_key:, model:, **options)
        raise BackendError, 'API key required' unless api_key
        raise BackendError, 'Model required' unless model

        super(model: model, **options)
        @client = ::Anthropic::Client.new(api_key: api_key)
      end

      def generate(messages, **options)
        params = build_parameters(messages, options)

        response = @client.messages.create(**params)

        response.content.first.text
      rescue ::Anthropic::Error => e
        raise BackendError, "Anthropic API error: #{e.message}"
      end

      private

      def build_parameters(messages, call_options)
        system_msg = messages.find { |m| m[:role] == :system }
        non_system = messages.reject { |m| m[:role] == :system }

        params = {
          model: @model,
          messages: translate_messages(non_system),
          max_tokens: call_options[:max_tokens] || @options[:max_tokens] || 1024,
          **@options.merge(call_options).except(:max_tokens)
        }

        params[:system] = system_msg[:content] if system_msg
        params
      end

      def translate_messages(messages)
        messages.map do |msg|
          {"role" => msg[:role].to_s, "content" => msg[:content]}
        end
      end
    end
  end
end
```

**Key Differences:**
- System prompt is separate parameter, not in messages
- `max_tokens` is REQUIRED by Anthropic
- Different response structure

### Ollama Backend (Future)

```ruby
module Russula
  module Backend
    class Ollama < Base
      def initialize(model:, base_url: 'http://localhost:11434', **options)
        raise BackendError, 'Model required' unless model

        super(model: model, **options)
        @base_url = base_url
        @client = ::Ollama::Client.new(base_url: @base_url)
      end

      def generate(messages, **options)
        params = build_parameters(messages, options)

        response = @client.chat(**params)

        response['message']['content']
      rescue ::Ollama::Error => e
        raise BackendError, "Ollama error: #{e.message}"
      rescue Faraday::ConnectionFailed => e
        raise BackendError, "Ollama server not reachable at #{@base_url}"
      end

      private

      def build_parameters(messages, call_options)
        {
          model: @model,
          messages: translate_messages(messages),
          **@options.merge(call_options)
        }
      end

      def translate_messages(messages)
        messages.map do |msg|
          {"role" => msg[:role].to_s, "content" => msg[:content]}
        end
      end
    end
  end
end
```

**Key Differences:**
- Runs locally (no API key)
- Custom base URL for server
- Simpler response structure

## Implementation Checklist

### Backend Base Class
- [ ] Define `Backend::Base` abstract class
- [ ] Implement `initialize(model:, **options)`
- [ ] Implement `attr_reader :model, :options`
- [ ] Implement `update_options(**new_options)`
- [ ] Raise `NotImplementedError` for `generate`

### OpenAI Backend
- [ ] Require `openai` gem
- [ ] Implement `initialize(api_key:, model:, **options)`
- [ ] Validate `api_key` and `model` presence
- [ ] Initialize OpenAI client
- [ ] Implement `generate(messages, **options)`
- [ ] Implement `build_parameters(messages, call_options)`
- [ ] Implement `translate_messages(messages)`
- [ ] Wrap OpenAI errors in `BackendError`
- [ ] Handle invalid response format
- [ ] Handle network errors

### Backend Factory
- [ ] Implement `Backend.create(type:, **options)`
- [ ] Support `:openai` type
- [ ] Raise error for unsupported types
- [ ] Lazy-require backend classes

### Error Handling
- [ ] Define `Russula::BackendError < Russula::Error`
- [ ] Add `cause` attribute to store original exception
- [ ] Wrap all provider errors
- [ ] Provide helpful error messages

### Testing
- [ ] Write specs for `Backend::Base`
- [ ] Write specs for `Backend::OpenAI#initialize`
- [ ] Write specs for `Backend::OpenAI#generate`
- [ ] Write specs for `Backend::OpenAI#update_options`
- [ ] Write specs for error cases
- [ ] Write specs for `Backend.create`
- [ ] Use VCR for API call recording

### Documentation
- [ ] Document supported models
- [ ] Document configuration options
- [ ] Document error types
- [ ] Provide usage examples

## See Also

- [Architecture Specification](ARCHITECTURE.md)
- [API Specification](API_SPECIFICATION.md)
- [Constraint System](CONSTRAINT_SYSTEM.md)
- [Validation Algorithm](VALIDATION_ALGORITHM.md)
