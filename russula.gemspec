# frozen_string_literal: true

require_relative 'lib/russula/version'

Gem::Specification.new do |spec|
  spec.name          = 'russula'
  spec.version       = Russula::VERSION
  spec.authors       = ['Christopher Hagmann']
  spec.email         = ['your.email@example.com']

  spec.summary       = 'Structured generative programming for Ruby'
  spec.description   = 'A Ruby port of Mellea.ai bringing structured, type-safe LLM programming to Ruby and Rails'
  spec.homepage      = 'https://github.com/cdhagmann/russula'
  spec.license       = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob('{lib,spec}/**/*') + %w[LICENSE README.md]
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'ruby-openai', '~> 6.0'

  # Development dependencies are in Gemfile
end
