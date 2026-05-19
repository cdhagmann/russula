# frozen_string_literal: true

require 'erb'

module Russula
  module Generative
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def generative_methods
        @generative_methods ||= {}
      end

      def generative(name, returns:, &block)
        raise ArgumentError, 'block required' unless block

        generative_methods[name] = {
          return_type: returns,
          docstring: extract_docstring(block),
          block: block
        }
        define_generative_method(name, returns, block)
      end

      private

      def extract_docstring(block)
        return block.call if block.parameters.empty?

        stubs = block.parameters.each_with_object({}) do |(type, pname), h|
          h[pname] = '' if %i[keyreq key].include?(type) && pname
        end
        block.call(**stubs)
      end

      def define_generative_method(name, returns, block)
        define_method(name) do |session = nil, **kwargs|
          raise ArgumentError, 'session required' unless session.is_a?(Russula::Session)

          # The block is the prompt-builder: its return value is the rendered prompt.
          # Use plain Ruby string interpolation (#{var}) for kwarg substitution — block
          # defaults are honoured naturally without needing a separate template engine.
          prompt = block.parameters.empty? ? block.call : block.call(**kwargs)
          response = session.instruct(prompt)
          Russula::TypeConstraint.new(returns).coerce(response.value)
        end
      end
    end
  end
end
