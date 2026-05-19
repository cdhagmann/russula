# frozen_string_literal: true

require 'erb'

module Russula
  class Context
    attr_reader :messages

    def initialize
      @messages = []
    end

    def add_message(role:, content:)
      @messages << { role: role, content: content }
    end
  end

  class Session
    SUPPORTED_BACKENDS = %i[openai].freeze

    attr_reader :backend, :context, :options

    def initialize(backend:, api_key: nil, model: nil, **opts)
      raise BackendError, "Unsupported backend: #{backend}" unless SUPPORTED_BACKENDS.include?(backend)
      raise BackendError, 'API key required' if api_key.nil? || api_key.to_s.empty?
      raise BackendError, 'Model required'   if model.nil? || model.to_s.empty?

      @backend = Backend.create(type: backend, api_key: api_key, model: model, **opts)
      @options = { api_key: api_key, model: model }.merge(opts)
      @context = Context.new
      @config_stack = []
    end

    def push(**new_opts)
      @config_stack.push(@options.dup)
      @options = @options.merge(new_opts)
      @backend.update_options(**new_opts)
    end

    def pop
      raise Error, 'Cannot pop: configuration stack is empty' if @config_stack.empty?

      @options = @config_stack.pop
      @backend.update_options(**@options.except(:api_key, :model))
    end

    # rubocop:disable Metrics/ParameterLists
    def instruct(prompt, requirements: [], checks: [], strategy: nil,
                 user_variables: {}, return_sampling_results: false)
      # rubocop:enable Metrics/ParameterLists
      if strategy
        strategy.sample(
          session: self, prompt: prompt, requirements: requirements,
          checks: checks, user_variables: user_variables,
          return_sampling_results: return_sampling_results
        )
      else
        text = single_shot_generate(prompt, requirements: requirements, user_variables: user_variables)
        ModelOutput.new(text)
      end
    end

    private

    def single_shot_generate(prompt, requirements:, user_variables:)
      rendered = render_template(prompt, user_variables)
      full_prompt = append_requirements(rendered, requirements)
      messages = build_messages(full_prompt)
      response = @backend.generate(messages, {})
      record_exchange(full_prompt, response)
      response
    end

    def render_template(template, vars)
      return template if vars.empty?

      ERB.new(template).result_with_hash(vars)
    end

    def append_requirements(prompt, requirements)
      visible = requirements.select(&:include_in_prompt)
      return prompt if visible.empty?

      "#{prompt}\n\nRequirements:\n#{visible.map { |r| "- #{r.description}" }.join("\n")}"
    end

    def build_messages(content)
      msgs = @context.messages.dup
      msgs << { role: :user, content: content }
      msgs
    end

    def record_exchange(user_content, assistant_content)
      @context.add_message(role: :user, content: user_content)
      @context.add_message(role: :assistant, content: assistant_content)
    end
  end
end
