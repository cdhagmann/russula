# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Russula::Generative do
  describe 'generative method definition' do
    let(:test_class) do
      Class.new do
        include Russula::Generative

        generative :classify_sentiment, returns: %i[positive negative neutral] do |text:|
          "Classify the sentiment of the input text as positive, negative, or neutral. Input: #{text}"
        end

        generative :summarize, returns: String do |text:, max_words: 50|
          "Summarize the input text in at most #{max_words} words. Input: #{text}"
        end
      end
    end

    let(:session) do
      Russula::Session.new(
        backend: :openai,
        api_key: ENV['OPENAI_API_KEY'] || 'test-key',
        model: 'gpt-4o-mini'
      )
    end

    it 'creates a callable method' do
      instance = test_class.new
      expect(instance).to respond_to(:classify_sentiment)
    end

    it 'requires session as first argument' do
      instance = test_class.new

      expect do
        instance.classify_sentiment(text: 'I love this!')
      end.to raise_error(ArgumentError, /session required/)
    end

    it 'validates return type constraints' do
      instance = test_class.new
      allow(session.backend).to receive(:generate).and_return('happy')

      expect do
        instance.classify_sentiment(session, text: 'I love this!')
      end.to raise_error(Russula::ValidationError, /Invalid return value.*must be one of/)
    end

    it 'accepts valid return type' do
      instance = test_class.new
      allow(session.backend).to receive(:generate).and_return('positive')

      result = instance.classify_sentiment(session, text: 'I love this!')
      expect(result).to eq(:positive)
    end

    it 'coerces string response to symbol for symbol constraints' do
      instance = test_class.new
      allow(session.backend).to receive(:generate).and_return('negative')

      result = instance.classify_sentiment(session, text: 'This is terrible.')
      expect(result).to eq(:negative)
    end

    it 'supports template interpolation in docstrings' do
      instance = test_class.new
      allow(session.backend).to receive(:generate).and_return('A short summary.')

      instance.summarize(session, text: 'Long text here...', max_words: 25)

      expect(session.backend).to have_received(:generate) do |messages, _options|
        prompt = messages.last[:content]
        expect(prompt).to include('at most 25 words')
      end
    end

    it 'validates String return type' do
      instance = test_class.new
      allow(session.backend).to receive(:generate).and_return('A summary.')

      result = instance.summarize(session, text: 'Long text...')
      expect(result).to be_a(String)
    end
  end

  describe 'method metadata' do
    let(:test_class) do
      Class.new do
        include Russula::Generative

        generative :example_method, returns: %i[a b] do
          'Example docstring'
        end
      end
    end

    it 'stores return type constraint metadata' do
      metadata = test_class.generative_methods[:example_method]
      expect(metadata[:return_type]).to eq(%i[a b])
    end

    it 'stores docstring metadata' do
      metadata = test_class.generative_methods[:example_method]
      expect(metadata[:docstring]).to eq('Example docstring')
    end
  end

  describe 'complex scenarios' do
    let(:test_class) do
      Class.new do
        include Russula::Generative

        generative :extract_info, returns: Hash do |text:|
          "Extract name, age, and city from the text and return as a hash. Input: #{text}"
        end
      end
    end

    let(:session) do
      Russula::Session.new(
        backend: :openai,
        api_key: 'test-key',
        model: 'gpt-4o-mini'
      )
    end

    it 'can handle Hash return types' do
      instance = test_class.new
      allow(session.backend).to receive(:generate).and_return(
        '{"name": "Alice", "age": 30, "city": "NYC"}'
      )

      # This would require JSON parsing logic
      expect do
        instance.extract_info(session, text: 'Alice is 30 and lives in NYC.')
      end.not_to raise_error
    end
  end

  describe 'integration with session context' do
    let(:test_class) do
      Class.new do
        include Russula::Generative

        generative :continue_story, returns: String do |prompt:|
          "Continue the story from the previous context. Prompt: #{prompt}"
        end
      end
    end

    let(:session) do
      Russula::Session.new(
        backend: :openai,
        api_key: 'test-key',
        model: 'gpt-4o-mini'
      )
    end

    it 'maintains context across generative calls' do
      instance = test_class.new
      allow(session.backend).to receive(:generate).and_return('Story part 1', 'Story part 2')

      instance.continue_story(session, prompt: 'Once upon a time...')
      instance.continue_story(session, prompt: 'What happened next?')

      # Context should have all messages
      expect(session.context.messages.count).to eq(4) # 2 user + 2 assistant
    end
  end
end
