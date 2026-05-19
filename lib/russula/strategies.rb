# frozen_string_literal: true

module Russula
  class ModelOutput
    attr_reader :value, :metadata

    def initialize(value, metadata: {})
      @value = value
      @metadata = metadata
    end

    def to_s
      @value
    end
  end

  class SamplingResult
    attr_reader :success, :attempts, :sample_generations, :result

    def initialize(success:, attempts:, sample_generations:, result:)
      @success = success
      @attempts = attempts
      @sample_generations = sample_generations
      @result = result
    end
  end

  class RejectionSamplingStrategy
    attr_reader :loop_budget

    def initialize(loop_budget:)
      @loop_budget = loop_budget
    end

    # rubocop:disable Metrics/ParameterLists
    def sample(session:, prompt:, requirements:, checks:, user_variables:, return_sampling_results:)
      # rubocop:enable Metrics/ParameterLists
      generations = []
      attempts = 0

      @loop_budget.times do
        attempts += 1
        text = session.send(:single_shot_generate, prompt,
                            requirements: requirements, user_variables: user_variables)
        output = ModelOutput.new(text)
        generations << output

        if all_satisfied?(text, requirements, checks, session)
          return return_sampling_results ? success_result(attempts, generations, output) : output
        end
      end

      handle_exhaustion(attempts, generations, return_sampling_results)
    end

    private

    def all_satisfied?(text, requirements, checks, session)
      (requirements + checks).all? { |c| c.validate(text, session) }
    end

    def success_result(attempts, generations, output)
      SamplingResult.new(
        success: true, attempts: attempts,
        sample_generations: generations, result: output
      )
    end

    def handle_exhaustion(attempts, generations, return_sampling_results)
      raise ValidationError, "Budget exhausted after #{attempts} attempts" unless return_sampling_results

      SamplingResult.new(
        success: false, attempts: attempts,
        sample_generations: generations, result: generations.last
      )
    end
  end
end
