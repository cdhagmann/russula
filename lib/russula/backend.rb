# frozen_string_literal: true

require 'openai'

module Russula
  module Backend
    class Base
      attr_reader :model, :options

      def initialize(model:, **options)
        @model = model
        @options = options
      end

      def generate(_messages, _options = {})
        raise NotImplementedError
      end

      def update_options(**new_options)
        @options = @options.merge(new_options)
      end
    end

    class OpenAI < Base
      def initialize(api_key: nil, model: nil, **options)
        raise BackendError, 'API key required' if api_key.nil? || api_key.to_s.empty?
        raise BackendError, 'Model required'   if model.nil? || model.to_s.empty?

        super(model: model, **options)
        @client = ::OpenAI::Client.new(access_token: api_key)
      end

      def generate(messages, options = {})
        params = build_parameters(messages, options)
        response = @client.chat(parameters: params)
        extract_content(response)
      rescue BackendError
        raise
      rescue StandardError => e
        raise BackendError, e.message
      end

      private

      def build_parameters(messages, options)
        merged = @options.merge(options)
        {
          model: @model,
          messages: messages.map { |m| { role: m[:role].to_s, content: m[:content] } },
          temperature: merged[:temperature],
          max_tokens: merged[:max_tokens]
        }.compact
      end

      def extract_content(response)
        content = response.dig('choices', 0, 'message', 'content')
        raise BackendError, 'Invalid response from OpenAI' if content.nil?

        content
      end
    end

    def self.create(type:, **opts)
      case type
      when :openai then OpenAI.new(**opts)
      else raise BackendError, "Unsupported backend type: #{type}"
      end
    end
  end
end
