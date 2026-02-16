# Contributing to Russula

Thank you for your interest in contributing to Russula! This guide will help you get started.

## Project Vision

Russula is a Ruby port of Mellea.ai, focused on bringing structured generative programming to Ruby and Rails applications. Our goal is to provide a production-ready, type-safe, and maintainable alternative to brittle prompts and flaky agents.

**Design Principles:**
1. **Ruby-idiomatic API** - Use Ruby's metaprogramming strengths, not just translate Python patterns
2. **Production-ready** - Real systems need reliability, not research features
3. **Focused scope** - Programming model layer, not LLM client implementation
4. **Type safety** - Leverage Ruby type systems (Sorbet, RBS) where possible
5. **Rails-friendly** - Easy integration with Rails applications

## Development Setup

### Prerequisites

- Ruby 3.0 or higher
- Bundler
- An OpenAI API key (for testing)

### Getting Started

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/russula.git
   cd russula
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Set up environment variables:
   ```bash
   cp .env.example .env
   # Edit .env and add your API keys
   ```

4. Run the test suite:
   ```bash
   bundle exec rspec
   ```

## Project Structure

```
russula/
├── lib/
│   ├── russula.rb              # Main entry point
│   └── russula/
│       ├── version.rb          # Version constant
│       ├── session.rb          # Session management
│       ├── generative.rb       # Generative method mixin
│       ├── constraints.rb      # Requirement/Check/Type constraints
│       ├── strategies.rb       # Sampling strategies
│       └── backend/            # LLM backend adapters
│           ├── base.rb
│           └── openai.rb
├── spec/
│   ├── spec_helper.rb
│   ├── russula/                # Unit tests
│   └── integration/            # Integration tests
└── examples/                   # Example usage scripts
```

## Testing Guidelines

### Writing Tests

We use RSpec for testing. All new features should include tests.

**Test Structure:**
- Unit tests in `spec/russula/` for individual components
- Integration tests in `spec/integration/` for complete workflows
- Use VCR for recording HTTP interactions (to avoid API costs during development)

**Example test:**
```ruby
RSpec.describe Russula::Session do
  let(:session) do
    Russula::Session.new(
      backend: :openai,
      api_key: 'test-key',
      model: 'gpt-4o-mini'
    )
  end

  it 'creates a session successfully' do
    expect(session).to be_a(Russula::Session)
  end
end
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific file
bundle exec rspec spec/russula/session_spec.rb

# Run with coverage
bundle exec rspec --format documentation
```

### VCR Cassettes

VCR records HTTP interactions for deterministic testing:
- First run makes real API calls and records them
- Subsequent runs use recorded responses
- Cassettes are stored in `spec/fixtures/vcr_cassettes/`
- **Do not commit cassettes with real API keys!**

To re-record cassettes:
```bash
rm -rf spec/fixtures/vcr_cassettes/
bundle exec rspec
```

## Code Style

We follow standard Ruby style guidelines:

```bash
# Check style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a
```

**Key conventions:**
- Use 2 spaces for indentation
- Maximum line length: 120 characters
- Use `frozen_string_literal: true` magic comment
- Prefer keyword arguments for public APIs
- Use descriptive variable names

## Contributing Areas

### High Priority

**1. Backend Integrations**
- Anthropic Claude support
- Ollama local models
- AWS Bedrock
- Azure OpenAI

**2. Type System Enhancements**
- Sorbet signatures
- RBS type definitions
- Better structured type constraints

**3. Rails Integration**
- ActiveModel validators
- Generators for common patterns
- Caching strategies
- Background job integration

**4. Documentation**
- More usage examples
- API reference
- Rails integration guide
- Performance optimization guide

### Medium Priority

**5. Validation Improvements**
- Parallel validation strategies
- Custom validation DSL
- Validation result inspection

**6. Component DAG System**
- Structured prompt composition
- Reusable prompt fragments
- Prompt versioning

**7. Streaming Support**
- Server-sent events
- Progressive validation
- Incremental type checking

### Future Considerations

- MCP protocol integration
- Multi-model orchestration
- Fine-tuning utilities
- Agent framework (Kripke-style)

## Pull Request Process

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write tests first (TDD encouraged)
   - Implement the feature
   - Ensure all tests pass
   - Add documentation

3. **Commit your changes**
   ```bash
   git add .
   git commit -m "Add feature: brief description"
   ```

4. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   ```
   Then create a pull request on GitHub.

5. **PR Requirements**
   - [ ] All tests pass
   - [ ] Code style checks pass (rubocop)
   - [ ] New features have tests
   - [ ] Documentation updated (if needed)
   - [ ] CHANGELOG.md updated

## Design Decisions

When contributing, keep these design principles in mind:

### 1. Ruby-Native Patterns

Use Ruby idioms, not Python translations:
```ruby
# Good - Ruby metaprogramming
generative def classify(text:) -> [:positive, :negative]
  "Classify sentiment"
end

# Avoid - Forcing Python patterns
@generative
def classify(text):
  """Classify sentiment"""
```

### 2. Backend Abstraction

Russula wraps existing Ruby LLM libraries instead of implementing HTTP clients:
```ruby
# Good - Wrap existing library
class Backend::OpenAI
  def initialize(api_key:)
    @client = OpenAI::Client.new(access_token: api_key)
  end
end

# Avoid - Reimplementing HTTP
class Backend::OpenAI
  def initialize(api_key:)
    @api_key = api_key
    # Don't implement Net::HTTP logic here
  end
end
```

### 3. Type Safety First

Leverage Ruby's type systems:
```ruby
# Good - Clear type constraints
generative def extract(text:) -> Hash
  "Extract structured data as JSON"
end

# Consider - Sorbet signatures (future)
sig { params(session: Session, text: String).returns(Hash) }
def extract(session, text:)
  # ...
end
```

## Questions?

- **General questions:** Open a GitHub Discussion
- **Bug reports:** Open a GitHub Issue
- **Security issues:** Email [SECURITY_EMAIL] (do not open public issue)

## Code of Conduct

Be respectful, inclusive, and constructive. We're all here to make Ruby AI development better.

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0, same as the project.

---

Thank you for contributing to Russula! 🍄
