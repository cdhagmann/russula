# frozen_string_literal: true

require 'json'

module Russula
  module Constraints; end

  class Requirement
    attr_reader :description, :validation_fn, :include_in_prompt

    def initialize(description, validation_fn: nil)
      @description = description
      @validation_fn = validation_fn
      @include_in_prompt = true
    end

    def use_llm_validation?
      @validation_fn.nil?
    end

    def validate(value, session)
      return run_custom_validator(value, session) unless use_llm_validation?

      run_llm_judge(value.to_s, session)
    end

    private

    # Validators named `|context|` operate on session.context; everything else
    # receives the generated text (or whatever the caller passed as `value`).
    def run_custom_validator(value, session)
      first_param = @validation_fn.parameters.first
      if first_param && first_param.last == :context && session
        @validation_fn.call(session.context)
      else
        @validation_fn.call(value)
      end
    end

    def run_llm_judge(text, session)
      prompt = "Does the following text satisfy this requirement: '#{@description}'? " \
               "Respond yes or no.\n\nText: #{text}"
      response = session.backend.generate([{ role: :user, content: prompt }], {})
      parse_judge_response(response)
    end

    # Returns Boolean; not a true predicate (it parses input), so keep verb form.
    def parse_judge_response(response) # rubocop:disable Naming/PredicateMethod
      return true  if response.match?(/\A\s*(yes|true|correct)/i)
      return false if response.match?(/\A\s*(no|false|incorrect)/i)

      false
    end
  end

  class Check < Requirement
    def initialize(description, validation_fn: nil)
      super
      @include_in_prompt = false
    end
  end

  class TypeConstraint
    def initialize(type)
      @type = type
    end

    # Public API verb (matches spec contract `.validate(value)`); returns Boolean.
    def validate(value) # rubocop:disable Naming/PredicateMethod
      @type.is_a?(Array) ? @type.include?(value) : value.is_a?(@type)
    end

    def coerce(value)
      return coerce_enum(value) if @type.is_a?(Array)

      send(:"coerce_#{@type.name.downcase}", value)
    end

    private

    def coerce_enum(value)
      sym = value.is_a?(Symbol) ? value : value.to_s.strip.downcase.to_sym
      return sym if @type.include?(sym)

      raise ValidationError,
            "Invalid return value: '#{value}' must be one of: #{@type.join(', ')}"
    end

    def coerce_string(value)
      return value if value.is_a?(String)

      raise ValidationError, "Invalid String: #{value.inspect}"
    end

    def coerce_integer(value)
      Integer(value)
    rescue ArgumentError, TypeError
      raise ValidationError, "Invalid Integer: #{value.inspect}"
    end

    def coerce_float(value)
      Float(value)
    rescue ArgumentError, TypeError
      raise ValidationError, "Invalid Float: #{value.inspect}"
    end

    def coerce_hash(value)
      return value if value.is_a?(Hash)

      JSON.parse(value)
    rescue JSON::ParserError
      raise ValidationError, "Invalid JSON for Hash: #{value.inspect}"
    end

    def coerce_array(value)
      return value if value.is_a?(Array)

      JSON.parse(value)
    rescue JSON::ParserError
      raise ValidationError, "Invalid JSON for Array: #{value.inspect}"
    end
  end
end
