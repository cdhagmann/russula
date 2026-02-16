# Implementation Guide

This guide helps you implement the Russula library based on the specifications we've created.

## Overview

All specs are written in `spec/` directory and define the expected API. Your job is to implement the classes in `lib/russula/` to make these specs pass.

## Implementation Order

Follow this order to build incrementally:

### Phase 1: Foundation (Core Infrastructure)

**1.1. Backend Base Class** (`lib/russula/backend/base.rb`)
```ruby
module Russula
  module Backend
    class Base
      attr_reader :model, :options

      def initialize(model:, **options)
        @model = model
        @options = options
      end

      def generate(messages, **options)
        raise NotImplementedError
      end

      def update_options(**new_options)
        @options.merge!(new_options)
      end
    end
  end
end
```

**1.2. OpenAI Backend** (`lib/russula/backend/openai.rb`)
```ruby
require 'openai'

module Russula
  module Backend
    class OpenAI < Base
      def initialize(api_key:, model:, **options)
        raise BackendError, 'API key required' unless api_key
        raise BackendError, 'Model required' unless model

        super(model: model, **options)
        @client = OpenAI::Client.new(access_token: api_key)
      end

      def generate(messages, **options)
        # Implement OpenAI API call
        # See spec/russula/backend_spec.rb for expected behavior
      end
    end
  end
end
```

**1.3. Backend Factory** (`lib/russula/backend.rb`)
```ruby
module Russula
  module Backend
    def self.create(type:, **options)
      case type
      when :openai
        require_relative 'backend/openai'
        OpenAI.new(**options)
      else
        raise BackendError, "Unsupported backend type: #{type}"
      end
    end
  end
end
```

**Test**: Run `bundle exec rspec spec/russula/backend_spec.rb`

### Phase 2: Context and Session

**2.1. Context Class** (`lib/russula/context.rb`)
```ruby
module Russula
  class Context
    attr_reader :messages

    def initialize
      @messages = []
    end

    def add_message(role:, content:)
      @messages << { role: role, content: content }
    end

    def clear
      @messages.clear
    end
  end
end
```

**2.2. ModelOutput Class** (`lib/russula/model_output.rb`)
```ruby
module Russula
  class ModelOutput
    attr_reader :value, :metadata

    def initialize(value, metadata: {})
      @value = value
      @metadata = metadata
    end

    def to_s
      @value
    end
  end
end
```

**2.3. Session Class** (`lib/russula/session.rb`)
```ruby
module Russula
  class Session
    attr_reader :backend, :context, :options

    def initialize(backend:, model:, api_key: nil, **options)
      @backend = Backend.create(type: backend, model: model, api_key: api_key, **options)
      @context = Context.new
      @options = options
      @config_stack = []
    end

    def push(**new_options)
      # Save current state and update options
      # See spec/russula/session_spec.rb for behavior
    end

    def pop
      # Restore previous state
      # See spec/russula/session_spec.rb for behavior
    end

    def instruct(prompt, requirements: [], checks: [], strategy: nil,
                 user_variables: {}, return_sampling_results: false)
      # Core generation method
      # See spec/russula/session_spec.rb and validation_spec.rb
    end

    private

    def render_template(template, variables)
      # Use ERB to interpolate variables
      require 'erb'
      ERB.new(template).result_with_hash(variables)
    end
  end
end
```

**Test**: Run `bundle exec rspec spec/russula/session_spec.rb`

### Phase 3: Constraints System

**3.1. Requirement Class** (`lib/russula/constraints.rb`)
```ruby
module Russula
  class Requirement
    attr_reader :description, :validation_fn, :include_in_prompt

    def initialize(description, validation_fn: nil)
      @description = description
      @validation_fn = validation_fn
      @include_in_prompt = true
    end

    def validate(text_or_context, session)
      if @validation_fn
        # Use custom validator
        @validation_fn.call(text_or_context)
      else
        # Use LLM-as-a-judge
        llm_validate(text_or_context, session)
      end
    end

    def use_llm_validation?
      @validation_fn.nil?
    end

    private

    def llm_validate(text, session)
      # Ask LLM if requirement is satisfied
      # Return true/false based on response
    end
  end

  class Check < Requirement
    def initialize(description, validation_fn: nil)
      super
      @include_in_prompt = false
    end
  end

  def self.req(description, validation_fn: nil)
    Requirement.new(description, validation_fn: validation_fn)
  end

  def self.check(description, validation_fn: nil)
    Check.new(description, validation_fn: validation_fn)
  end
end
```

**3.2. Type Constraints** (add to `lib/russula/constraints.rb`)
```ruby
module Russula
  class TypeConstraint
    def initialize(type)
      @type = type
    end

    def validate(value)
      case @type
      when Array
        @type.include?(value)
      when Class
        value.is_a?(@type)
      else
        false
      end
    end

    def coerce(value)
      # Convert string to appropriate type
      # See spec/russula/constraints_spec.rb for cases
    end
  end
end
```

**Test**: Run `bundle exec rspec spec/russula/constraints_spec.rb`

### Phase 4: Validation Strategy

**4.1. SamplingResult Class** (`lib/russula/strategies.rb`)
```ruby
module Russula
  class SamplingResult
    attr_reader :success, :attempts, :sample_generations, :result

    def initialize(success:, attempts:, sample_generations:, result:)
      @success = success
      @attempts = attempts
      @sample_generations = sample_generations
      @result = result
    end
  end
end
```

**4.2. RejectionSamplingStrategy** (add to `lib/russula/strategies.rb`)
```ruby
module Russula
  class RejectionSamplingStrategy
    attr_reader :loop_budget

    def initialize(loop_budget:)
      @loop_budget = loop_budget
    end

    def sample(session, prompt, requirements: [], checks: [])
      attempts = 0
      generations = []
      all_constraints = requirements + checks

      @loop_budget.times do
        attempts += 1

        # Generate response
        response = session.backend.generate(/* ... */)
        generations << ModelOutput.new(response)

        # Validate all constraints
        if all_constraints.all? { |c| c.validate(response, session) }
          return SamplingResult.new(
            success: true,
            attempts: attempts,
            sample_generations: generations,
            result: generations.last
          )
        end
      end

      # Budget exhausted
      raise ValidationError, "Budget exhausted after #{attempts} attempts"
    end
  end
end
```

**Test**: Run `bundle exec rspec spec/russula/validation_spec.rb`

### Phase 5: Generative Methods

**5.1. Generative Mixin** (`lib/russula/generative.rb`)
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
        # This is tricky - need to capture:
        # 1. Method name
        # 2. Return type constraint (from -> [:a, :b])
        # 3. Docstring
        # 4. Original method implementation

        # Use method_added hook
        # See spec/russula/generative_spec.rb for expected behavior
      end

      def method_added(method_name)
        # Hook to capture generative method definitions
      end
    end
  end
end
```

**Note**: This is the most complex part. You'll need to:
1. Parse the `-> [...]` syntax for return types
2. Capture the method's docstring
3. Wrap the original method to inject session handling
4. Apply type constraints to the return value

**Test**: Run `bundle exec rspec spec/russula/generative_spec.rb`

### Phase 6: Integration

**6.1. Main Entry Point** (`lib/russula.rb`)

Ensure all requires are in place:
```ruby
require_relative 'russula/version'
require_relative 'russula/context'
require_relative 'russula/model_output'
require_relative 'russula/session'
require_relative 'russula/generative'
require_relative 'russula/constraints'
require_relative 'russula/strategies'
require_relative 'russula/backend'
```

**Test**: Run `bundle exec rspec spec/integration/complete_workflow_spec.rb`

## Testing Strategy

### Run All Tests
```bash
bundle exec rspec
```

### Run Specific Test File
```bash
bundle exec rspec spec/russula/session_spec.rb
```

### Run Specific Test
```bash
bundle exec rspec spec/russula/session_spec.rb:10
```

### With Coverage
```bash
bundle exec rspec --format documentation
```

## Common Implementation Challenges

### 1. Generative Method Syntax

The `generative def method -> [:a, :b]` syntax is custom. You have two options:

**Option A**: Use method_added hook
```ruby
def self.method_added(method_name)
  if @pending_generative
    # Process the method
    @pending_generative = false
  end
end

def generative(definition)
  @pending_generative = true
  definition
end
```

**Option B**: Use block syntax
```ruby
generative def: :classify, returns: [:positive, :negative] do |text:|
  "Classify: #{text}"
end
```

### 2. ERB Template Rendering

Use `ERB.new(template).result_with_hash(variables)`:
```ruby
require 'erb'

def render_template(template, variables)
  ERB.new(template).result_with_hash(variables)
end
```

### 3. LLM-as-a-Judge Validation

Construct a validation prompt:
```ruby
def llm_validate(text, requirement, session)
  prompt = <<~PROMPT
    Does the following text satisfy the requirement: "#{requirement.description}"?

    Text: #{text}

    Answer only 'yes' or 'no'.
  PROMPT

  response = session.backend.generate([{ role: :user, content: prompt }])
  response.strip.downcase.match?(/^yes|true|correct/)
end
```

### 4. Type Coercion

Handle common type conversions:
```ruby
def coerce_to_type(value, type)
  case type
  when Array
    # Symbol enumeration
    raise unless type.all? { |t| t.is_a?(Symbol) }
    sym = value.to_sym
    raise unless type.include?(sym)
    sym
  when Integer
    Integer(value)
  when Float
    Float(value)
  when Hash
    JSON.parse(value)
  # ...
  end
end
```

## Debugging Tips

### 1. Use Pry for Interactive Debugging
```ruby
require 'pry'
binding.pry  # Drop into debugger
```

### 2. Enable VCR Debugging
```ruby
VCR.configure do |config|
  config.debug_logger = File.open('vcr.log', 'w')
end
```

### 3. Mock API Calls During Development
```ruby
allow(session.backend).to receive(:generate).and_return('mock response')
```

## Next Steps After Implementation

1. **Run full test suite**: `bundle exec rspec`
2. **Check code style**: `bundle exec rubocop`
3. **Test examples**: `bundle exec rake examples`
4. **Build gem**: `bundle exec rake build`
5. **Update README** with any API changes
6. **Write more examples** in `examples/`

## Getting Help

- Check `spec/` files for expected behavior
- Review `PROJECT_SUMMARY.md` for architecture overview
- Reference Mellea.ai documentation for inspiration
- Open GitHub issues for questions

Good luck! 🍄
