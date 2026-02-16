# Russula

A Ruby port of [Mellea.ai](https://github.com/generative-computing/mellea), bringing structured generative programming to Ruby and Rails applications.

**Status:** Early development (v0.1.0 MVP in progress)

## Why Russula?

Russula enables Ruby developers to build robust, maintainable AI features using structured generative programming instead of brittle prompts and flaky agents. It's designed for production systems that need to work reliably, particularly in government and enterprise Rails applications.

**The opportunity:** Python-only tooling creates barriers for Ruby/Rails shops building AI features. Russula brings IBM Research's generative programming model to the Ruby ecosystem with a natural, idiomatic API.

## Core Concepts

Russula replaces large, brittle prompts with composable, validatable steps:

### 1. Generative Methods

Define LLM-powered functions using Ruby's metaprogramming:

```ruby
class SentimentClassifier
  include Russula::Generative

  # The method signature and docstring become the interface
  generative def classify(text:) -> [:positive, :negative]
    # Docstring guides the LLM
    "Classify the sentiment of the input text as 'positive' or 'negative'."
  end
end

session = Russula.start_session
classifier = SentimentClassifier.new
result = classifier.classify(session, text: "I love this!")
# => :positive
```

**Key benefits:**
- Type-constrained outputs using Ruby symbols and types
- Docstrings become prompts automatically
- Composable, testable functions instead of scattered prompt strings

### 2. Instruct-Validate-Repair Loop

Systematic retry logic until constraints are satisfied:

```ruby
session = Russula.start_session

email = session.instruct(
  "Write an email inviting interns to the office party.",
  requirements: [
    req("be formal"),
    req("use 'Dear interns' as greeting")
  ],
  strategy: RejectionSamplingStrategy.new(loop_budget: 5)
)
```

The loop automatically:
1. **Instructs** the LLM with your prompt and requirements
2. **Validates** output against requirements
3. **Repairs** by retrying if validation fails

### 3. Three-Tier Constraint System

**`req()` - Requirements** (included in prompt + validated):
```ruby
req("be formal")
```

**`check()` - Validation-only** (NOT in prompt, avoids negative priming):
```ruby
check("avoid negative language")
```

**Custom validators:**
```ruby
req("use only lowercase",
    validation_fn: ->(text) { text == text.downcase })
```

### 4. Session Management

Clean state management with hierarchical configuration:

```ruby
session = Russula.start_session(
  backend: :ollama,
  model: "ibm/granite4:micro-h"
)

# Temporary configuration changes
session.push(temperature: 0.7)
# ... operations with higher temperature ...
session.pop  # Revert to previous settings
```

## MVP Scope (v0.1.0)

The initial release focuses on the core programming model:

✅ **Included:**
- Session management wrapping `ruby-openai` or similar backends
- The instruct-validate-repair loop with rejection sampling
- Generative methods via Ruby metaprogramming
- Three-tier constraint system (req/check/custom)
- Type constraints using Ruby symbols and basic types
- Template support via ERB

🚫 **Deferred to later versions:**
- MCP/A2A integration
- LoRA fine-tuning utilities
- Kripke agent framework
- Advanced component DAG system
- Multi-provider backend abstraction (start with OpenAI-compatible only)

## Architecture Decisions

### Backend Strategy

Russula does NOT implement its own LLM client. Instead, it wraps existing Ruby LLM libraries:

- **Primary:** `ruby-openai` (most mature, Rails-friendly, multi-provider)
- **Future:** `llm.rb` or others as backends

This keeps Russula focused on the programming model layer, not HTTP/streaming/provider quirks.

### Ruby Translation Patterns

**Python decorator → Ruby mixin:**
```python
# Python (Mellea)
@generative
def classify(text: str) -> Literal["positive", "negative"]:
    """Docstring"""
```

```ruby
# Ruby (Russula)
generative def classify(text:) -> [:positive, :negative]
  "Docstring"
end
```

**Type constraints:**
- `Literal["a", "b"]` → `[:a, :b]` (Ruby symbols)
- `str` → `String`
- `int` → `Integer`
- Custom validators for complex types

**Templating:**
- Jinja2 → ERB
- Keep the `user_variables` hash pattern

## Design Philosophy

Following Mellea's principles:

1. **Structured Decomposition:** Break problems into validatable pieces
2. **Explicit Failure Modes:** Every LLM call has defined success criteria
3. **Selective Model Invocation:** Use LLMs for semantic reasoning, not arithmetic
4. **Verification-Circumscribed Calls:** Wrap every generation in validation
5. **Production-Ready:** Built for real systems, not research demos

As IBM Research states: "You don't need a cannon to shoot a bird." Russula enables smaller models to handle tasks through structured decomposition.

## Installation

```ruby
# Gemfile
gem 'russula', '~> 0.1.0'
```

```bash
bundle install
```

## Quick Start

```ruby
require 'russula'

# Start a session
session = Russula.start_session(
  backend: :openai,
  api_key: ENV['OPENAI_API_KEY'],
  model: 'gpt-4o-mini'
)

# Use instruct with validation
response = session.instruct(
  "List 3 Ruby web frameworks.",
  requirements: [
    req("include Rails"),
    req("format as a numbered list")
  ]
)

puts response.value
```

## Roadmap

### v0.1.0 (MVP)
- [x] Session management
- [ ] Basic instruct/validate/repair loop
- [ ] Generative method decorator
- [ ] Type constraints (symbols, basic types)
- [ ] Requirement/check/validator system
- [ ] OpenAI backend integration

### v0.2.0
- [ ] Multiple backend support (Anthropic, Ollama, etc.)
- [ ] Advanced type constraints (Sorbet/RBS integration)
- [ ] Component DAG for structured prompts
- [ ] Sampling result inspection

### v0.3.0+
- [ ] Rails integration helpers
- [ ] ActiveModel validators
- [ ] Streaming support
- [ ] Batch operations
- [ ] MCP protocol support

## Contributing

Russula is in early development. Contributions are welcome, especially:

- Backend integrations (Anthropic, Ollama, local models)
- Type system improvements (Sorbet, RBS)
- Rails-specific helpers
- Documentation and examples

## Credits

Russula is a Ruby port of [Mellea.ai](https://github.com/generative-computing/mellea) by IBM Research (Nathan Fulton, Hendrik Strobelt, and contributors).

The name "Russula" follows the botanical naming tradition:
- **Mellea** refers to honey fungus (*Armillaria mellea*)
- **Russula** is a genus of brittlegills mushrooms, chosen for its Ruby connection

## License

Apache License 2.0

This is a derivative work of Mellea.ai, also licensed under Apache 2.0. See [LICENSE](LICENSE) for details.

## Resources

- [Mellea.ai Documentation](https://docs.mellea.ai/)
- [Generative Computing - IBM Research](https://research.ibm.com/blog/generative-computing-mellea)
- [Mellea GitHub Repository](https://github.com/generative-computing/mellea)
