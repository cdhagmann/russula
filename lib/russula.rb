# frozen_string_literal: true

require_relative 'russula/version'

module Russula
  class Error < StandardError; end
  class ValidationError < Error; end
  class BackendError < Error; end

  # Start a new generative programming session
  #
  # @param backend [Symbol] Backend type (:openai, etc.)
  # @param model [String] Model identifier
  # @param api_key [String] API key for the backend
  # @param options [Hash] Additional backend-specific options
  # @return [Session] A new session instance
  def self.start_session(backend: :openai, model: nil, api_key: nil, **options)
    Session.new(backend: backend, model: model, api_key: api_key, **options)
  end

  # Build a Requirement (validated and included in the prompt).
  def self.req(description, validation_fn: nil)
    Requirement.new(description, validation_fn: validation_fn)
  end

  # Build a Check (validated but NOT included in the prompt — avoids negative priming).
  def self.check(description, validation_fn: nil)
    Check.new(description, validation_fn: validation_fn)
  end
end

require_relative 'russula/backend'
require_relative 'russula/constraints'
require_relative 'russula/strategies'
require_relative 'russula/generative'
require_relative 'russula/session'
