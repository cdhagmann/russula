# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Complete Workflow Integration' do
  let(:session) do
    Russula::Session.new(
      backend: :openai,
      api_key: ENV['OPENAI_API_KEY'] || 'test-key',
      model: 'gpt-4o-mini'
    )
  end

  describe 'Email generation with validation' do
    it 'generates a validated email', :vcr do
      email = session.instruct(
        'Write an email inviting the team to a celebration party.',
        requirements: [
          Russula.req('use "Dear Team" as greeting',
                      validation_fn: ->(text) { text.include?('Dear Team') }),
          Russula.req('mention the date Friday, March 15th',
                      validation_fn: ->(text) { text.include?('March 15') })
        ],
        checks: [
          Russula.check('avoid negative language',
                        validation_fn: ->(text) { !text.match?(/unfortunately|regret|sorry/) })
        ],
        strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 5)
      )

      expect(email.value).to include('Dear Team')
      expect(email.value).to include('March 15')
      expect(email.value).not_to match(/unfortunately|regret|sorry/)
    end
  end

  describe 'Sentiment classification with generative method' do
    let(:classifier_class) do
      Class.new do
        include Russula::Generative

        generative :classify, returns: %i[positive negative neutral] do |text:|
          "Classify the sentiment of the following text as positive, negative, or neutral. Input: #{text}"
        end
      end
    end

    it 'classifies sentiment correctly', :vcr do
      classifier = classifier_class.new

      # Mock for deterministic testing
      allow(session.backend).to receive(:generate).and_return('positive')

      result = classifier.classify(session, text: 'I absolutely love this product!')

      expect(result).to eq(:positive)
    end
  end

  describe 'Multi-step workflow with context' do
    let(:story_class) do
      Class.new do
        include Russula::Generative

        generative :start_story, returns: String do |theme:|
          "Write the opening paragraph of a story with theme: #{theme}"
        end

        generative :continue_story, returns: String do
          'Continue the story from where we left off, maintaining consistency.'
        end
      end
    end

    it 'maintains context across multiple generative calls', :vcr do
      writer = story_class.new

      allow(session.backend).to receive(:generate).and_return(
        'Once upon a time in a digital forest...',
        'The protagonist discovered a hidden algorithm...'
      )

      opening = writer.start_story(session, theme: 'technology')
      continuation = writer.continue_story(session)

      expect(opening).to be_a(String)
      expect(continuation).to be_a(String)
      expect(session.context.messages.count).to eq(4) # 2 user + 2 assistant
    end
  end

  describe 'Structured data extraction' do
    let(:extractor_class) do
      Class.new do
        include Russula::Generative

        generative :extract_contact_info, returns: Hash do |text:|
          "Extract name, email, and phone number from the text and return as JSON. Input: #{text}"
        end
      end
    end

    it 'extracts and validates structured data', :vcr do
      extractor = extractor_class.new

      json_response = '{"name": "Alice Smith", "email": "alice@example.com", "phone": "555-0123"}'
      allow(session.backend).to receive(:generate).and_return(json_response)

      result = extractor.extract_contact_info(
        session,
        text: 'Contact Alice Smith at alice@example.com or call 555-0123'
      )

      expect(result).to be_a(Hash)
      expect(result['name']).to eq('Alice Smith')
      expect(result['email']).to eq('alice@example.com')
      expect(result['phone']).to eq('555-0123')
    end
  end

  describe 'Temperature adjustment with push/pop' do
    it 'allows temporary configuration changes', :vcr do
      allow(session.backend).to receive(:generate).and_return(
        'Creative response',
        'Deterministic response'
      )

      # Creative generation with high temperature
      session.push(temperature: 0.9)
      creative = session.instruct('Write a creative opening line.')
      session.pop

      # Deterministic generation with low temperature
      session.push(temperature: 0.1)
      factual = session.instruct('State the capital of France.')
      session.pop

      expect(creative.value).to be_a(String)
      expect(factual.value).to be_a(String)
    end
  end

  describe 'Complex validation with sampling results' do
    it 'provides detailed sampling information', :vcr do
      call_count = 0
      allow(session.backend).to receive(:generate) do
        call_count += 1
        if call_count >= 3
          'This summary is concise and clear.'
        else
          'This is a very long summary that goes on and on with too many details.'
        end
      end

      result = session.instruct(
        'Summarize the concept of generative programming.',
        requirements: [
          Russula.req('keep under 100 characters',
                      validation_fn: ->(text) { text.length < 100 })
        ],
        strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 5),
        return_sampling_results: true
      )

      expect(result).to be_a(Russula::SamplingResult)
      expect(result.success).to be true
      expect(result.attempts).to eq(3)
      expect(result.sample_generations.count).to eq(3)

      # Final result should meet requirements
      expect(result.result.value.length).to be < 100
    end
  end

  describe 'Template interpolation with ERB' do
    it 'supports complex templating' do
      allow(session.backend).to receive(:generate).and_return('Email generated')

      session.instruct(
        'Write an email to <%= recipient %> about <%= topic %> for <%= date %>.',
        user_variables: {
          recipient: 'the engineering team',
          topic: 'the upcoming release',
          date: 'next Tuesday'
        }
      )

      expect(session.backend).to have_received(:generate) do |messages, _options|
        prompt = messages.last[:content]
        expect(prompt).to include('the engineering team')
        expect(prompt).to include('the upcoming release')
        expect(prompt).to include('next Tuesday')
      end
    end
  end

  describe 'Error handling' do
    it 'raises clear error when validation budget exhausted' do
      allow(session.backend).to receive(:generate).and_return('Never valid')

      expect do
        session.instruct(
          'Generate text.',
          requirements: [
            Russula.req('include MAGIC_WORD',
                        validation_fn: ->(text) { text.include?('MAGIC_WORD') })
          ],
          strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 2)
        )
      end.to raise_error(Russula::ValidationError) do |error|
        expect(error.message).to include('Budget exhausted')
        expect(error.message).to include('2 attempts')
      end
    end

    it 'raises clear error for type constraint violations' do
      classifier_class = Class.new do
        include Russula::Generative

        generative :classify, returns: %i[a b c] do |text:|
          "Classify the text. Input: #{text}"
        end
      end

      classifier = classifier_class.new
      allow(session.backend).to receive(:generate).and_return('invalid_option')

      expect do
        classifier.classify(session, text: 'Some text')
      end.to raise_error(Russula::ValidationError, /must be one of: a, b, c/)
    end
  end
end
