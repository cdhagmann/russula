require 'spec_helper'

RSpec.describe 'Instruct-Validate-Repair Loop' do
  let(:session) do
    Russula::Session.new(
      backend: :openai,
      api_key: ENV['OPENAI_API_KEY'] || 'test-key',
      model: 'gpt-4o-mini'
    )
  end

  describe 'rejection sampling strategy' do
    context 'when all requirements are met on first try' do
      it 'returns result without retrying' do
        allow(session.backend).to receive(:generate).and_return('Formal greeting here.')

        result = session.instruct(
          'Write a greeting.',
          requirements: [Russula.req('be formal')],
          strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3)
        )

        expect(session.backend).to have_received(:generate).once
        expect(result.value).to be_a(String)
      end
    end

    context 'when requirements fail initially' do
      it 'retries generation until requirements are met' do
        # First two calls fail validation, third succeeds
        call_count = 0
        allow(session.backend).to receive(:generate) do
          call_count += 1
          case call_count
          when 1 then 'hey'
          when 2 then 'hi there'
          else 'Dear Sir or Madam,'
          end
        end

        result = session.instruct(
          'Write a formal greeting.',
          requirements: [
            Russula.req('be formal', validation_fn: ->(text) { text.include?('Dear') })
          ],
          strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 5)
        )

        expect(call_count).to eq(3)
        expect(result.value).to include('Dear')
      end
    end

    context 'when budget is exhausted' do
      it 'raises error with sampling results' do
        allow(session.backend).to receive(:generate).and_return('invalid response')

        expect {
          session.instruct(
            'Write a greeting.',
            requirements: [
              Russula.req('must include "MAGIC_WORD"',
                         validation_fn: ->(text) { text.include?('MAGIC_WORD') })
            ],
            strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3)
          )
        }.to raise_error(Russula::ValidationError, /Budget exhausted/)
      end
    end
  end

  describe 'sampling results inspection' do
    it 'returns detailed results when requested' do
      allow(session.backend).to receive(:generate).and_return('First try', 'Second try')

      result = session.instruct(
        'Write a greeting.',
        requirements: [
          Russula.req('include "hello"',
                     validation_fn: ->(text) { text.downcase.include?('hello') })
        ],
        strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3),
        return_sampling_results: true
      )

      expect(result).to be_a(Russula::SamplingResult)
      expect(result.success).to be_in([true, false])
      expect(result.attempts).to be > 0
      expect(result.sample_generations).to be_an(Array)
    end

    it 'includes all attempted generations' do
      call_count = 0
      allow(session.backend).to receive(:generate) do
        call_count += 1
        "Attempt #{call_count}"
      end

      result = session.instruct(
        'Write text.',
        requirements: [
          Russula.req('include "SUCCESS"',
                     validation_fn: ->(text) { text.include?('SUCCESS') })
        ],
        strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3),
        return_sampling_results: true
      )

      expect(result.sample_generations.count).to eq(call_count)
      result.sample_generations.each_with_index do |gen, idx|
        expect(gen.value).to eq("Attempt #{idx + 1}")
      end
    end
  end

  describe 'requirement validation' do
    context 'with LLM-as-a-judge validation' do
      it 'uses LLM to validate requirements' do
        # Mock both generation and validation calls
        generation_count = 0
        allow(session.backend).to receive(:generate) do
          generation_count += 1
          if generation_count.odd?
            # Generation calls
            'A polite greeting'
          else
            # Validation calls - return "yes" or "no"
            'yes'
          end
        end

        result = session.instruct(
          'Write a greeting.',
          requirements: [Russula.req('be polite')],
          strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3)
        )

        # Should have made both generation and validation calls
        expect(generation_count).to be >= 2
        expect(result.value).to be_a(String)
      end
    end

    context 'with custom validation function' do
      it 'uses provided function for validation' do
        validation_called = false
        validator = lambda do |text|
          validation_called = true
          text.length > 10
        end

        allow(session.backend).to receive(:generate).and_return('This is a long enough greeting message.')

        result = session.instruct(
          'Write a greeting.',
          requirements: [Russula.req('be long enough', validation_fn: validator)],
          strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3)
        )

        expect(validation_called).to be true
        expect(result.value.length).to be > 10
      end
    end
  end

  describe 'check constraints' do
    it 'validates but does not include in prompt' do
      allow(session.backend).to receive(:generate).and_return('A positive message!')

      session.instruct(
        'Write a message.',
        checks: [
          Russula.check('avoid negative language',
                       validation_fn: ->(text) { !text.downcase.match?(/bad|terrible|awful/) })
        ],
        strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3)
      )

      # Check that prompt doesn't include the check constraint
      expect(session.backend).to have_received(:generate) do |messages, _options|
        prompt = messages.last[:content]
        expect(prompt).not_to include('avoid negative language')
      end
    end

    it 'still validates check constraints' do
      allow(session.backend).to receive(:generate).and_return('This is terrible and awful!')

      expect {
        session.instruct(
          'Write a message.',
          checks: [
            Russula.check('avoid negative words',
                         validation_fn: ->(text) { !text.match?(/terrible|awful/) })
          ],
          strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 2)
        )
      }.to raise_error(Russula::ValidationError, /Budget exhausted/)
    end
  end

  describe 'mixed requirements and checks' do
    it 'combines both constraint types' do
      allow(session.backend).to receive(:generate).and_return('Dear Customer, we are pleased to help!')

      result = session.instruct(
        'Write a greeting.',
        requirements: [
          Russula.req('be formal', validation_fn: ->(text) { text.include?('Dear') })
        ],
        checks: [
          Russula.check('avoid negative tone',
                       validation_fn: ->(text) { !text.match?(/unfortunately|regret/) })
        ],
        strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3)
      )

      expect(result.value).to include('Dear')
      expect(result.value).not_to match(/unfortunately|regret/)
    end
  end

  describe 'validation with session context' do
    it 'allows validators to access full context' do
      # Context-aware validator that checks conversation history
      context_validator = lambda do |context|
        # Ensure we have at least one previous message
        context.messages.count >= 2
      end

      allow(session.backend).to receive(:generate).and_return('Response')

      # First call to establish context
      session.instruct('First prompt')

      # Second call with context-aware validation
      result = session.instruct(
        'Second prompt',
        requirements: [
          Russula.req('maintain context', validation_fn: context_validator)
        ],
        strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 3)
      )

      expect(result.value).to be_a(String)
    end
  end
end
