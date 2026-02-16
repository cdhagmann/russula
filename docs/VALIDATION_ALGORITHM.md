# Validation Algorithm Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-02-16

## Table of Contents

1. [Overview](#overview)
2. [Algorithm Overview](#algorithm-overview)
3. [Rejection Sampling Strategy](#rejection-sampling-strategy)
4. [Generation Phase](#generation-phase)
5. [Validation Phase](#validation-phase)
6. [Repair Phase](#repair-phase)
7. [Success Criteria](#success-criteria)
8. [Failure Handling](#failure-handling)
9. [Sampling Result Structure](#sampling-result-structure)
10. [Performance Considerations](#performance-considerations)

## Overview

The validation algorithm implements the **instruct-validate-repair loop**, also known as **rejection sampling**. This transforms unreliable LLM outputs into robust, constraint-satisfying results through systematic retry logic.

### Core Concept

```
Loop (up to N times):
  1. INSTRUCT: Generate output from LLM
  2. VALIDATE: Check all constraints
  3. REPAIR: If failed, retry with new generation
  4. RETURN: If succeeded, return result
```

### Design Goals

- **Reliability**: Ensure outputs meet specified constraints
- **Efficiency**: Minimize unnecessary LLM calls
- **Transparency**: Provide detailed results for debugging
- **Configurability**: Allow tuning of retry budgets

## Algorithm Overview

### High-Level Flow

```
┌─────────────────────────────────────────┐
│  session.instruct(prompt,               │
│    requirements: [...],                 │
│    checks: [...],                       │
│    strategy: RejectionSampling(budget)) │
└──────────────┬──────────────────────────┘
               │
               ▼
      ┌────────────────────┐
      │ Render ERB template │
      └────────┬────────────┘
               │
               ▼
      ┌─────────────────────┐
      │ Build final prompt  │
      │ (add requirements)  │
      └────────┬────────────┘
               │
               ▼
     ┌──────────────────────────┐
     │ Strategy.sample()        │
     │  ┌───────────────────┐   │
     │  │ GENERATION LOOP   │   │
     │  │ (up to budget)    │   │
     │  │                   │   │
     │  │ 1. Generate       │   │
     │  │ 2. Validate all   │   │
     │  │ 3. Success?       │   │
     │  │    → Return       │   │
     │  │    Fail           │   │
     │  │    → Retry        │   │
     │  └───────────────────┘   │
     └──────────┬───────────────┘
                │
      ┌─────────┴──────────┐
      │                    │
      ▼                    ▼
  ┌─────────┐      ┌──────────────┐
  │ Success │      │ Budget       │
  │ Return  │      │ Exhausted    │
  │ Result  │      │ Raise Error  │
  └─────────┘      └──────────────┘
```

### Pseudocode

```ruby
def sample(prompt, requirements, checks, loop_budget)
  attempts = 0
  generations = []
  all_constraints = requirements + checks

  loop_budget.times do
    attempts += 1

    # GENERATION PHASE
    text = backend.generate(messages_with_prompt(prompt))
    generation = ModelOutput.new(text)
    generations << generation

    # VALIDATION PHASE
    all_pass = all_constraints.all? { |c| c.validate(text, session) }

    # SUCCESS CHECK
    if all_pass
      return SamplingResult.new(
        success: true,
        attempts: attempts,
        sample_generations: generations,
        result: generation
      )
    end

    # REPAIR PHASE (implicit: loop continues)
  end

  # FAILURE (budget exhausted)
  raise ValidationError,
        "Budget exhausted after #{attempts} attempts"
end
```

## Rejection Sampling Strategy

### Initialization

```ruby
class RejectionSamplingStrategy
  attr_reader :loop_budget

  def initialize(loop_budget:)
    raise ArgumentError, "loop_budget must be positive" if loop_budget <= 0

    @loop_budget = loop_budget
  end
end
```

**Parameters:**
- `loop_budget` (Integer): Maximum number of generation attempts
  - Must be positive (> 0)
  - Typical values: 3-10
  - Higher values increase reliability but cost

### Loop Mechanics

The strategy executes up to `loop_budget` iterations:

```ruby
loop_budget.times do |iteration|
  attempt_number = iteration + 1

  # Generate
  # Validate
  # Return if success
  # Continue if failure
end

# If loop completes without return: budget exhausted
```

### Budget Enforcement

**Strict Enforcement:**
- Exactly `loop_budget` attempts maximum
- No exceptions or extensions
- After `loop_budget` failures, raise error

**Counting:**
- Each call to `backend.generate()` counts as one attempt
- Validation calls do NOT count toward budget
- Failed generations count toward budget

## Generation Phase

### Prompt Construction

1. **Start with base prompt:**
   ```ruby
   base_prompt = user_provided_prompt
   ```

2. **Render ERB template:**
   ```ruby
   rendered_prompt = ERB.new(base_prompt).result_with_hash(user_variables)
   ```

3. **Add requirements:**
   ```ruby
   requirements_text = requirements.map(&:description).join("\n- ")

   if requirements.any?
     final_prompt = "#{rendered_prompt}\n\nRequirements:\n- #{requirements_text}"
   else
     final_prompt = rendered_prompt
   end
   ```

4. **Checks are NOT added to prompt** (by design)

### Message Construction

Build message array for backend:

```ruby
def messages_with_prompt(prompt)
  # Start with context history
  messages = session.context.messages.dup

  # Add new user message
  messages << {role: :user, content: prompt}

  messages
end
```

### Generation Call

```ruby
text = session.backend.generate(
  messages_with_prompt(final_prompt),
  **session.options
)
```

**Options** may include:
- `temperature`
- `max_tokens`
- Backend-specific options

### Context Update

After generation, update context:

```ruby
# Add user message
session.context.add_message(role: :user, content: final_prompt)

# Add assistant response
session.context.add_message(role: :assistant, content: text)
```

**Note:** In MVP, context is updated immediately. Future: may buffer until validation succeeds.

## Validation Phase

### Requirement Validation

For each requirement:

```ruby
requirements.each do |req|
  unless req.validate(text, session)
    # Record failure
    failed_requirements << req
  end
end
```

**Validation methods:**
1. Custom validator (if provided)
2. LLM-as-a-judge (if no validator)

See [CONSTRAINT_SYSTEM.md](CONSTRAINT_SYSTEM.md) for details.

### Check Validation

For each check:

```ruby
checks.each do |check|
  unless check.validate(text, session)
    # Record failure
    failed_checks << check
  end
end
```

**Same validation methods as requirements**, but checks were never in the prompt.

### Short-Circuit Logic

**Current (MVP):**
```ruby
# Evaluate all constraints
all_pass = all_constraints.all? { |c| c.validate(text, session) }
```

**Future Optimization:**
```ruby
# Short-circuit on first failure
all_pass = all_constraints.all? do |c|
  result = c.validate(text, session)
  return false unless result  # Stop on first failure
  true
end
```

**Trade-off:**
- Current: Complete feedback (know all failures)
- Future: Faster validation (stop early)

### Parallel Validation (Future)

Constraints could be validated concurrently:

```ruby
results = Parallel.map(all_constraints) do |constraint|
  constraint.validate(text, session)
end

all_pass = results.all?
```

**Benefits:**
- Reduced latency (parallel LLM calls)

**Costs:**
- More LLM API calls
- Increased cost

## Repair Phase

### Retry Logic

If validation fails and budget remains:

```ruby
if all_pass
  # Success: return
else
  # Failure: continue loop (implicit retry)
  next
end
```

The "repair" is simply generating a new output. No explicit repair mechanism in MVP.

### Context Preservation

**Current (MVP):**
- Failed generations remain in context
- Next generation sees previous attempts

**Future:**
- Option to remove failed generations from context
- "Clean slate" retries

**Configuration:**
```ruby
# Future API
strategy = RejectionSamplingStrategy.new(
  loop_budget: 5,
  preserve_failed_attempts: false  # Don't pollute context
)
```

### Prompt Variation (Future)

To avoid repeating the same generation:

```ruby
# Future: Vary prompt on retries
if attempt > 1
  prompt = "#{original_prompt}\n\n(Previous attempt didn't meet requirements. Please try again.)"
end
```

## Success Criteria

Generation succeeds when:

```ruby
requirements.all? { |r| r.validate(text, session) } &&
checks.all? { |c| c.validate(text, session) }
```

**All constraints must pass** for success. No partial success.

### Early Success

If first generation passes all constraints:
- Return immediately (no retries needed)
- Budget not fully consumed

### Result Construction

On success:

```ruby
SamplingResult.new(
  success: true,
  attempts: actual_attempts,
  sample_generations: all_generations_array,
  result: successful_generation
)
```

## Failure Handling

### Budget Exhaustion

If all `loop_budget` attempts fail:

```ruby
raise Russula::ValidationError,
      "Validation failed after #{loop_budget} attempts. " \
      "Failed constraints: #{failed_constraint_names.join(', ')}"
```

**Error includes:**
- Number of attempts
- Which constraints failed
- Optionally: sample generations (for debugging)

### Validation Error Structure

```ruby
class ValidationError < Error
  attr_reader :attempts, :sample_generations, :failed_constraints

  def initialize(message, attempts:, sample_generations:, failed_constraints:)
    super(message)
    @attempts = attempts
    @sample_generations = sample_generations
    @failed_constraints = failed_constraints
  end
end
```

**Usage:**
```ruby
begin
  result = session.instruct(prompt, requirements: [...], strategy: ...)
rescue Russula::ValidationError => e
  puts "Failed after #{e.attempts} attempts"
  puts "Failed constraints: #{e.failed_constraints.map(&:description).join(', ')}"
  puts "Last attempt: #{e.sample_generations.last.value}"
end
```

### Backend Errors

If backend fails during generation:

```ruby
begin
  text = backend.generate(messages)
rescue StandardError => e
  raise Russula::BackendError, "Generation failed: #{e.message}"
end
```

**Behavior:**
- Backend errors propagate immediately
- No retry for backend errors (in MVP)
- Future: Configurable retry for transient errors

## Sampling Result Structure

### SamplingResult Class

```ruby
class SamplingResult
  attr_reader :success, :attempts, :sample_generations, :result

  def initialize(success:, attempts:, sample_generations:, result:)
    @success = success
    @attempts = attempts
    @sample_generations = sample_generations
    @result = result
  end
end
```

### Attributes

**`success` (Boolean):**
- `true`: Validation succeeded
- `false`: Budget exhausted without success

**`attempts` (Integer):**
- Number of generation attempts made
- Range: 1 to `loop_budget`

**`sample_generations` (Array<ModelOutput>):**
- All generated outputs (successful and failed)
- Ordered chronologically
- Each has `.value` (text) and `.metadata` (optional)

**`result` (ModelOutput):**
- The final generation
- If `success: true`: The successful generation
- If `success: false`: The last failed generation

### Usage

**Default (simple):**
```ruby
output = session.instruct(prompt, strategy: ...)
# Returns ModelOutput directly
puts output.value
```

**Detailed results:**
```ruby
result = session.instruct(
  prompt,
  strategy: ...,
  return_sampling_results: true
)

if result.success
  puts "Success after #{result.attempts} attempts"
  puts result.result.value
else
  puts "Failed after #{result.attempts} attempts"
  puts "All attempts:"
  result.sample_generations.each_with_index do |gen, i|
    puts "#{i + 1}. #{gen.value}"
  end
end
```

## Performance Considerations

### When to Use Sampling

**Use rejection sampling when:**
- Constraints are critical (must be satisfied)
- Some outputs may not meet requirements
- Cost of validation < cost of wrong output

**Avoid rejection sampling when:**
- No constraints (just generate)
- Constraints are always satisfied (wasted budget)
- Latency is critical (retries add latency)

### Optimizing Budget

**Choosing `loop_budget`:**

| Budget | Success Rate | Cost | Latency | Use Case |
|--------|--------------|------|---------|----------|
| 1      | Low          | Low  | Low     | Optional validation |
| 3      | Medium       | Medium | Medium | Typical constraints |
| 5      | High         | High | High    | Strict requirements |
| 10+    | Very High    | Very High | Very High | Critical applications |

**Formula (approximate):**
```
Probability of success with budget B:
  P(success) ≈ 1 - (1 - p)^B

where p = probability single attempt succeeds
```

**Example:**
- If `p = 0.5` (50% single-attempt success rate)
- Budget = 3: P(success) ≈ 87.5%
- Budget = 5: P(success) ≈ 96.9%

### Reducing Validation Cost

1. **Use custom validators** instead of LLM-as-a-judge
   - Faster
   - Cheaper
   - Deterministic

2. **Short-circuit validation** (future)
   - Stop on first failure
   - Reduces validation calls

3. **Parallel validation** (future)
   - Concurrent constraint checking
   - Lower latency

### Caching (Future)

Cache validation results:

```ruby
# Future feature
validation_cache = {}

def validate_with_cache(constraint, text)
  cache_key = "#{constraint.description}:#{text.hash}"

  validation_cache[cache_key] ||= constraint.validate(text, session)
end
```

## Advanced Scenarios

### Progressive Constraint Relaxation (Future)

If validation keeps failing, relax constraints:

```ruby
# Future API
strategy = AdaptiveStrategy.new(
  loop_budget: 10,
  relax_after: 5  # After 5 failures, drop least important constraints
)
```

### Constraint Prioritization (Future)

Some constraints are more important:

```ruby
# Future API
req('critical constraint', priority: :high)
req('nice to have', priority: :low)

# Strategy tries to satisfy high-priority constraints first
```

### Best-of-N Sampling (Future)

Generate N candidates, pick best:

```ruby
# Future API
strategy = BestOfNStrategy.new(
  n: 5,
  scoring_fn: ->(text) { text.length }  # Prefer longer
)
```

## Examples

### Example 1: Simple Validation

```ruby
result = session.instruct(
  'Write a greeting',
  requirements: [req('be polite')],
  strategy: RejectionSamplingStrategy.new(loop_budget: 3)
)

# Possible outcomes:
# - Attempt 1 passes: return after 1 attempt
# - Attempt 1 fails, 2 passes: return after 2 attempts
# - All 3 fail: raise ValidationError
```

### Example 2: Complex Constraints

```ruby
result = session.instruct(
  'Write an email',
  requirements: [
    req('use "Dear" greeting'),
    req('mention deadline'),
    req('under 100 words', validation_fn: ->(t) { t.split.count < 100 })
  ],
  checks: [
    check('no apologies', validation_fn: ->(t) { !t.match?(/sorry|apologize/i) })
  ],
  strategy: RejectionSamplingStrategy.new(loop_budget: 5),
  return_sampling_results: true
)

if result.success
  puts "Generated email after #{result.attempts} attempts:"
  puts result.result.value
else
  puts "Failed to generate valid email after #{result.attempts} attempts"
  puts "Attempts:"
  result.sample_generations.each_with_index do |gen, i|
    puts "\n--- Attempt #{i + 1} ---"
    puts gen.value
  end
end
```

### Example 3: No Validation (Simple Generation)

```ruby
# No strategy = no validation loop
result = session.instruct('Write a haiku')

# Just one generation, no retries
puts result.value
```

## See Also

- [Architecture Specification](ARCHITECTURE.md)
- [API Specification](API_SPECIFICATION.md)
- [Constraint System](CONSTRAINT_SYSTEM.md)
- [Type System](TYPE_SYSTEM.md)
