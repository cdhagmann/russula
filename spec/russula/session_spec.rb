# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Russula::Session do
  describe '.new' do
    context 'with OpenAI backend' do
      it 'creates a session with default settings' do
        session = described_class.new(
          backend: :openai,
          api_key: 'test-key',
          model: 'gpt-4o-mini'
        )

        expect(session).to be_a(described_class)
        expect(session.backend).to be_a(Russula::Backend::OpenAI)
      end

      it 'raises error without API key' do
        expect do
          described_class.new(backend: :openai, model: 'gpt-4o-mini')
        end.to raise_error(Russula::BackendError, /API key required/)
      end

      it 'raises error without model' do
        expect do
          described_class.new(backend: :openai, api_key: 'test-key')
        end.to raise_error(Russula::BackendError, /Model required/)
      end
    end

    context 'with unsupported backend' do
      it 'raises error' do
        expect do
          described_class.new(backend: :unknown, api_key: 'key', model: 'model')
        end.to raise_error(Russula::BackendError, /Unsupported backend/)
      end
    end
  end

  describe '#push and #pop' do
    let(:session) do
      described_class.new(
        backend: :openai,
        api_key: 'test-key',
        model: 'gpt-4o-mini',
        temperature: 0.5
      )
    end

    it 'allows temporary configuration changes' do
      original_temp = session.options[:temperature]

      session.push(temperature: 0.9)
      expect(session.options[:temperature]).to eq(0.9)

      session.pop
      expect(session.options[:temperature]).to eq(original_temp)
    end

    it 'supports nested push/pop' do
      session.push(temperature: 0.7)
      session.push(temperature: 0.9)

      expect(session.options[:temperature]).to eq(0.9)

      session.pop
      expect(session.options[:temperature]).to eq(0.7)

      session.pop
      expect(session.options[:temperature]).to eq(0.5)
    end

    it 'raises error on pop without push' do
      expect do
        session.pop
      end.to raise_error(Russula::Error, /Cannot pop: configuration stack is empty/)
    end
  end

  describe '#instruct' do
    let(:session) do
      described_class.new(
        backend: :openai,
        api_key: ENV['OPENAI_API_KEY'] || 'test-key',
        model: 'gpt-4o-mini'
      )
    end

    context 'basic instruction without requirements', :vcr do
      it 'generates a response' do
        response = session.instruct('Say hello in one word.')

        expect(response).to be_a(Russula::ModelOutput)
        expect(response.value).to be_a(String)
        expect(response.value.length).to be > 0
      end
    end

    context 'with template variables' do
      it 'interpolates variables using ERB' do
        allow(session.backend).to receive(:generate).and_return('Hello, Alice!')

        session.instruct(
          'Say hello to <%= name %>.',
          user_variables: { name: 'Alice' }
        )

        expect(session.backend).to have_received(:generate) do |messages, _options|
          expect(messages.last[:content]).to include('Say hello to Alice.')
        end
      end
    end

    context 'with requirements' do
      it 'validates requirements are met' do
        # Smoke test: the requirements kwarg is accepted and the call succeeds.
        # The end-to-end validation behaviour is covered by validation_spec.rb.
        allow(session.backend).to receive(:generate).and_return('A polite, brief greeting.')

        expect do
          session.instruct(
            'Write a greeting.',
            requirements: [
              Russula.req('be polite'),
              Russula.req('be brief')
            ]
          )
        end.not_to raise_error
      end
    end
  end

  describe '#context' do
    let(:session) do
      described_class.new(
        backend: :openai,
        api_key: 'test-key',
        model: 'gpt-4o-mini'
      )
    end

    it 'maintains conversation history' do
      allow(session.backend).to receive(:generate).and_return('Response 1', 'Response 2')

      session.instruct('First prompt')
      session.instruct('Second prompt')

      expect(session.context.messages.count).to eq(4) # 2 user + 2 assistant
    end

    it 'allows accessing message history' do
      allow(session.backend).to receive(:generate).and_return('Hello')

      session.instruct('Say hello')

      messages = session.context.messages
      expect(messages.first[:role]).to eq(:user)
      expect(messages.first[:content]).to include('Say hello')
      expect(messages.last[:role]).to eq(:assistant)
      expect(messages.last[:content]).to eq('Hello')
    end
  end
end
