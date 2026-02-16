require 'spec_helper'

RSpec.describe Russula::Constraints do
  describe 'Requirement' do
    describe '.req' do
      it 'creates a requirement with description' do
        requirement = Russula.req('be polite')

        expect(requirement).to be_a(Russula::Requirement)
        expect(requirement.description).to eq('be polite')
        expect(requirement.include_in_prompt).to be true
      end

      it 'accepts a custom validation function' do
        validator = ->(text) { text.length > 10 }
        requirement = Russula.req('be long', validation_fn: validator)

        expect(requirement.validation_fn).to eq(validator)
      end

      it 'defaults to LLM validation when no function provided' do
        requirement = Russula.req('be formal')

        expect(requirement.validation_fn).to be_nil
        expect(requirement.use_llm_validation?).to be true
      end
    end

    describe '#validate' do
      context 'with custom validation function' do
        it 'returns true when validation passes' do
          requirement = Russula.req(
            'contain "hello"',
            validation_fn: ->(text) { text.include?('hello') }
          )

          expect(requirement.validate('hello world', nil)).to be true
        end

        it 'returns false when validation fails' do
          requirement = Russula.req(
            'contain "hello"',
            validation_fn: ->(text) { text.include?('hello') }
          )

          expect(requirement.validate('goodbye world', nil)).to be false
        end
      end

      context 'with LLM validation' do
        let(:session) do
          Russula::Session.new(
            backend: :openai,
            api_key: 'test-key',
            model: 'gpt-4o-mini'
          )
        end

        it 'uses LLM to judge requirement satisfaction' do
          requirement = Russula.req('be polite')

          allow(session.backend).to receive(:generate).and_return('yes')

          result = requirement.validate('Please and thank you.', session)
          expect(result).to be true

          expect(session.backend).to have_received(:generate) do |messages, _options|
            prompt = messages.last[:content]
            expect(prompt).to include('be polite')
            expect(prompt).to include('Please and thank you.')
          end
        end

        it 'interprets "no" response as failed validation' do
          requirement = Russula.req('be polite')

          allow(session.backend).to receive(:generate).and_return('no')

          result = requirement.validate('Hey you!', session)
          expect(result).to be false
        end

        it 'handles various affirmative responses' do
          requirement = Russula.req('be formal')

          ['yes', 'Yes', 'YES', 'true', 'True', 'correct', 'Correct'].each do |response|
            allow(session.backend).to receive(:generate).and_return(response)
            expect(requirement.validate('Dear Sir,', session)).to be true
          end
        end

        it 'handles various negative responses' do
          requirement = Russula.req('be formal')

          ['no', 'No', 'NO', 'false', 'False', 'incorrect', 'Incorrect'].each do |response|
            allow(session.backend).to receive(:generate).and_return(response)
            expect(requirement.validate('hey', session)).to be false
          end
        end
      end

      context 'with context-aware validation function' do
        it 'receives session context' do
          context_checked = false
          requirement = Russula.req(
            'maintain conversation flow',
            validation_fn: lambda { |context|
              context_checked = true
              context.messages.count > 0
            }
          )

          session = Russula::Session.new(
            backend: :openai,
            api_key: 'test-key',
            model: 'gpt-4o-mini'
          )

          # Validation function should receive context, not just text
          result = requirement.validate(session.context, session)

          expect(context_checked).to be true
        end
      end
    end
  end

  describe 'Check' do
    describe '.check' do
      it 'creates a check constraint' do
        check = Russula.check('avoid negativity')

        expect(check).to be_a(Russula::Check)
        expect(check.description).to eq('avoid negativity')
        expect(check.include_in_prompt).to be false
      end

      it 'accepts a custom validation function' do
        validator = ->(text) { !text.match?(/bad|terrible/) }
        check = Russula.check('no negative words', validation_fn: validator)

        expect(check.validation_fn).to eq(validator)
      end
    end

    describe '#validate' do
      it 'validates without being in prompt' do
        check = Russula.check(
          'no profanity',
          validation_fn: ->(text) { !text.match?(/damn|hell/) }
        )

        expect(check.validate('This is fine.', nil)).to be true
        expect(check.validate('This is damn wrong.', nil)).to be false
        expect(check.include_in_prompt).to be false
      end
    end
  end

  describe 'Type constraints' do
    describe 'Symbol enumeration' do
      it 'validates symbol matches enumeration' do
        constraint = Russula::TypeConstraint.new([:positive, :negative, :neutral])

        expect(constraint.validate(:positive)).to be true
        expect(constraint.validate(:negative)).to be true
        expect(constraint.validate(:neutral)).to be true
        expect(constraint.validate(:invalid)).to be false
      end

      it 'coerces string to symbol' do
        constraint = Russula::TypeConstraint.new([:positive, :negative])

        expect(constraint.coerce('positive')).to eq(:positive)
        expect(constraint.coerce('negative')).to eq(:negative)
      end

      it 'raises error for invalid string' do
        constraint = Russula::TypeConstraint.new([:positive, :negative])

        expect {
          constraint.coerce('invalid')
        }.to raise_error(Russula::ValidationError, /must be one of/)
      end
    end

    describe 'Class type constraints' do
      it 'validates instance of class' do
        constraint = Russula::TypeConstraint.new(String)

        expect(constraint.validate('text')).to be true
        expect(constraint.validate(123)).to be false
      end

      it 'validates Integer' do
        constraint = Russula::TypeConstraint.new(Integer)

        expect(constraint.validate(42)).to be true
        expect(constraint.validate('42')).to be false
      end

      it 'coerces string to Integer' do
        constraint = Russula::TypeConstraint.new(Integer)

        expect(constraint.coerce('42')).to eq(42)
        expect(constraint.coerce('123')).to eq(123)
      end

      it 'coerces string to Float' do
        constraint = Russula::TypeConstraint.new(Float)

        expect(constraint.coerce('3.14')).to eq(3.14)
        expect(constraint.coerce('2.5')).to eq(2.5)
      end

      it 'raises error for invalid coercion' do
        constraint = Russula::TypeConstraint.new(Integer)

        expect {
          constraint.coerce('not a number')
        }.to raise_error(Russula::ValidationError, /Invalid Integer/)
      end
    end

    describe 'Hash type constraint' do
      it 'validates Hash instances' do
        constraint = Russula::TypeConstraint.new(Hash)

        expect(constraint.validate({ name: 'Alice' })).to be true
        expect(constraint.validate('not a hash')).to be false
      end

      it 'coerces JSON string to Hash' do
        constraint = Russula::TypeConstraint.new(Hash)
        json_string = '{"name": "Alice", "age": 30}'

        result = constraint.coerce(json_string)

        expect(result).to be_a(Hash)
        expect(result['name']).to eq('Alice')
        expect(result['age']).to eq(30)
      end

      it 'raises error for invalid JSON' do
        constraint = Russula::TypeConstraint.new(Hash)

        expect {
          constraint.coerce('not valid json')
        }.to raise_error(Russula::ValidationError, /Invalid JSON/)
      end
    end

    describe 'Array type constraint' do
      it 'validates Array instances' do
        constraint = Russula::TypeConstraint.new(Array)

        expect(constraint.validate([1, 2, 3])).to be true
        expect(constraint.validate('not an array')).to be false
      end

      it 'coerces JSON string to Array' do
        constraint = Russula::TypeConstraint.new(Array)
        json_string = '["a", "b", "c"]'

        result = constraint.coerce(json_string)

        expect(result).to be_a(Array)
        expect(result).to eq(['a', 'b', 'c'])
      end
    end
  end

  describe 'Combining constraints' do
    let(:session) do
      Russula::Session.new(
        backend: :openai,
        api_key: 'test-key',
        model: 'gpt-4o-mini'
      )
    end

    it 'allows multiple requirements' do
      requirements = [
        Russula.req('be polite', validation_fn: ->(text) { text.include?('please') }),
        Russula.req('be brief', validation_fn: ->(text) { text.length < 50 })
      ]

      text = 'Please help me with this task.'

      expect(requirements.all? { |req| req.validate(text, session) }).to be true
    end

    it 'fails if any requirement fails' do
      requirements = [
        Russula.req('be polite', validation_fn: ->(text) { text.include?('please') }),
        Russula.req('be brief', validation_fn: ->(text) { text.length < 10 })
      ]

      text = 'Please help me with this task.'

      expect(requirements.all? { |req| req.validate(text, session) }).to be false
    end

    it 'combines requirements and checks' do
      requirements = [
        Russula.req('be polite', validation_fn: ->(text) { text.include?('please') })
      ]
      checks = [
        Russula.check('no shouting', validation_fn: ->(text) { text != text.upcase })
      ]

      text = 'Please help me.'

      all_valid = requirements.all? { |req| req.validate(text, session) } &&
                  checks.all? { |check| check.validate(text, session) }

      expect(all_valid).to be true
    end
  end
end
