# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Russula::Backend do
  describe 'Backend::OpenAI' do
    let(:backend) do
      Russula::Backend::OpenAI.new(
        api_key: ENV['OPENAI_API_KEY'] || 'test-key',
        model: 'gpt-4o-mini'
      )
    end

    describe '#initialize' do
      it 'creates a backend with API key and model' do
        expect(backend).to be_a(Russula::Backend::OpenAI)
        expect(backend.model).to eq('gpt-4o-mini')
      end

      it 'raises error without API key' do
        expect do
          Russula::Backend::OpenAI.new(model: 'gpt-4o-mini')
        end.to raise_error(Russula::BackendError, /API key required/)
      end

      it 'raises error without model' do
        expect do
          Russula::Backend::OpenAI.new(api_key: 'test-key')
        end.to raise_error(Russula::BackendError, /Model required/)
      end
    end

    describe '#generate' do
      context 'with valid messages', :vcr do
        it 'generates a response' do
          messages = [
            { role: :system, content: 'You are a helpful assistant.' },
            { role: :user, content: 'Say hello.' }
          ]

          response = backend.generate(messages)

          expect(response).to be_a(String)
          expect(response.length).to be > 0
        end
      end

      context 'with options' do
        it 'passes temperature to the API' do
          messages = [{ role: :user, content: 'Hello' }]

          # Mock the client to verify options are passed
          client = instance_double(OpenAI::Client)
          allow(OpenAI::Client).to receive(:new).and_return(client)
          allow(client).to receive(:chat).and_return(
            { 'choices' => [{ 'message' => { 'content' => 'Response' } }] }
          )

          backend_with_temp = Russula::Backend::OpenAI.new(
            api_key: 'test-key',
            model: 'gpt-4o-mini',
            temperature: 0.7
          )

          backend_with_temp.generate(messages)

          expect(client).to have_received(:chat) do |params|
            expect(params[:parameters][:temperature]).to eq(0.7)
          end
        end

        it 'passes max_tokens to the API' do
          messages = [{ role: :user, content: 'Hello' }]

          client = instance_double(OpenAI::Client)
          allow(OpenAI::Client).to receive(:new).and_return(client)
          allow(client).to receive(:chat).and_return(
            { 'choices' => [{ 'message' => { 'content' => 'Response' } }] }
          )

          backend_with_max = Russula::Backend::OpenAI.new(
            api_key: 'test-key',
            model: 'gpt-4o-mini',
            max_tokens: 500
          )

          backend_with_max.generate(messages)

          expect(client).to have_received(:chat) do |params|
            expect(params[:parameters][:max_tokens]).to eq(500)
          end
        end
      end

      context 'error handling' do
        it 'raises BackendError on API failure' do
          messages = [{ role: :user, content: 'Hello' }]

          client = instance_double(OpenAI::Client)
          allow(OpenAI::Client).to receive(:new).and_return(client)
          allow(client).to receive(:chat).and_raise(StandardError.new('API Error'))

          expect do
            backend.generate(messages)
          end.to raise_error(Russula::BackendError, /API Error/)
        end

        it 'raises BackendError on invalid response format' do
          messages = [{ role: :user, content: 'Hello' }]

          client = instance_double(OpenAI::Client)
          allow(OpenAI::Client).to receive(:new).and_return(client)
          allow(client).to receive(:chat).and_return({}) # Invalid response

          expect do
            backend.generate(messages)
          end.to raise_error(Russula::BackendError, /Invalid response/)
        end
      end
    end

    describe '#update_options' do
      it 'allows updating backend options' do
        backend.update_options(temperature: 0.9, max_tokens: 1000)

        expect(backend.options[:temperature]).to eq(0.9)
        expect(backend.options[:max_tokens]).to eq(1000)
      end

      it 'merges with existing options' do
        backend_with_temp = Russula::Backend::OpenAI.new(
          api_key: 'test-key',
          model: 'gpt-4o-mini',
          temperature: 0.5
        )

        backend_with_temp.update_options(max_tokens: 500)

        expect(backend_with_temp.options[:temperature]).to eq(0.5)
        expect(backend_with_temp.options[:max_tokens]).to eq(500)
      end
    end
  end

  describe 'Backend factory' do
    it 'creates OpenAI backend' do
      backend = described_class.create(
        type: :openai,
        api_key: 'test-key',
        model: 'gpt-4o-mini'
      )

      expect(backend).to be_a(Russula::Backend::OpenAI)
    end

    it 'raises error for unsupported backend type' do
      expect do
        described_class.create(
          type: :unknown,
          api_key: 'test-key',
          model: 'some-model'
        )
      end.to raise_error(Russula::BackendError, /Unsupported backend type/)
    end
  end
end
