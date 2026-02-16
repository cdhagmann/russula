require_relative 'russula/version'
require_relative 'russula/session'
require_relative 'russula/generative'
require_relative 'russula/constraints'
require_relative 'russula/strategies'
require_relative 'russula/backend'

module Russula
  class Error < StandardError; end
  class ValidationError < Error; end
  class BackendError < Error; end

  # Start a new generative programming session
  #
  # @param backend [Symbol] Backend type (:openai, :anthropic, etc.)
  # @param model [String] Model identifier
  # @param api_key [String] API key for the backend
  # @param options [Hash] Additional backend-specific options
  # @return [Session] A new session instance
  def self.start_session(backend: :openai, model: nil, api_key: nil, **options)
    Session.new(backend: backend, model: model, api_key: api_key, **options)
  end
end
