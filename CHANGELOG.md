# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project structure
- Core `Session` class for managing LLM interactions
- `Generative` mixin for creating LLM-powered methods
- Instruct-validate-repair loop with rejection sampling
- Three-tier constraint system (requirements, checks, custom validators)
- Type constraints for symbols, basic types, and structured data
- OpenAI backend integration via `ruby-openai`
- Session state management with push/pop semantics
- ERB template support for dynamic prompts
- Comprehensive test suite with RSpec
- Integration tests for complete workflows

### Documentation
- README with architecture overview and usage examples
- Inline documentation for public APIs
- Spec examples demonstrating all major features

## [0.1.0] - TBD

Initial MVP release focusing on core generative programming patterns.

### Features
- Session management wrapping ruby-openai backend
- Generative method decorator via Ruby metaprogramming
- Instruct-validate-repair loop with configurable retry budgets
- Type-safe outputs using Ruby symbols and basic types
- Custom validation functions
- LLM-as-a-judge validation
- Hierarchical configuration with push/pop
- Template interpolation via ERB

### Scope Decisions
Deferred to future versions:
- MCP/A2A integration
- LoRA fine-tuning utilities
- Kripke agent framework
- Advanced component DAG system
- Multi-provider backend abstraction (only OpenAI in v0.1.0)
- Streaming support
- Batch operations

[Unreleased]: https://github.com/cdhagmann/russula/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cdhagmann/russula/releases/tag/v0.1.0
