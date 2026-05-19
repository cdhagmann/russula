#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Sentiment Classification with Russula
#
# This example demonstrates the core Russula pattern:
# 1. Define a generative method with type constraints
# 2. Use instruct-validate-repair for robust generation
# 3. Combine requirements and checks for quality control

require 'bundler/setup'
require 'russula'

# Define a sentiment classifier using the Generative mixin
class SentimentClassifier
  include Russula::Generative

  # The generative DSL captures:
  # - Method name as the first argument
  # - Return type constraint via `returns:`
  # - Prompt template via the block return value (ERB-rendered against kwargs)
  generative :classify, returns: %i[positive negative neutral] do |text:|
    "Analyze the sentiment of the following text and classify it as positive, negative, or neutral: #{text}"
  end

  # Multiple generative methods can coexist
  generative :explain_sentiment, returns: String do |text:|
    "Explain in one sentence the sentiment expressed by the following text: #{text}"
  end
end

# Initialize a session
session = Russula.start_session(
  backend: :openai,
  api_key: ENV.fetch('OPENAI_API_KEY', nil),
  model: 'gpt-4o-mini'
)

# Create classifier instance
classifier = SentimentClassifier.new

# Example texts to classify
texts = [
  'I absolutely love this product! It exceeded all my expectations.',
  "This is the worst experience I've ever had. Completely disappointed.",
  'The item arrived on time and works as described.',
  "Not sure how I feel about this. It's okay, I guess."
]

puts "Sentiment Classification Demo\n#{'=' * 50}\n\n"

texts.each do |text|
  # Classify with automatic type validation
  sentiment = classifier.classify(session, text: text)

  puts "Text: #{text}"
  puts "Sentiment: #{sentiment}"
  puts '-' * 50
  puts
end

# Example with instruct and validation
puts "\nEmail Generation with Validation\n#{'=' * 50}\n\n"

email = session.instruct(
  'Write a professional email to a customer apologizing for a delayed shipment.',
  requirements: [
    Russula.req('use "Dear Valued Customer" as greeting'),
    Russula.req('mention a specific compensation offer'),
    Russula.req('keep under 200 words')
  ],
  checks: [
    Russula.check('maintain professional tone',
                  validation_fn: ->(text) { !text.match?(/hey|sup|yo/i) })
  ],
  strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 5)
)

puts email.value
puts "\n#{'=' * 50}"

# Example with temperature adjustment
puts "\nCreative vs. Deterministic Generation\n#{'=' * 50}\n\n"

puts 'Creative (temperature = 0.9):'
session.push(temperature: 0.9)
creative = session.instruct('Write a creative product tagline for eco-friendly water bottles.')
puts creative.value
session.pop

puts "\nDeterministic (temperature = 0.1):"
session.push(temperature: 0.1)
factual = session.instruct('Write a factual product description for eco-friendly water bottles.')
puts factual.value
session.pop

puts "\n#{'=' * 50}"
puts 'Demo completed!'
