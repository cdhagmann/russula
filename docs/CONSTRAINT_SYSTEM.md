# Constraint System Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-02-16

## Table of Contents

1. [Overview](#overview)
2. [Three-Tier System](#three-tier-system)
3. [Requirement Specification](#requirement-specification)
4. [Check Specification](#check-specification)
5. [Custom Validator Protocol](#custom-validator-protocol)
6. [LLM-as-a-Judge Algorithm](#llm-as-a-judge-algorithm)
7. [Constraint Evaluation Order](#constraint-evaluation-order)
8. [Failure Modes](#failure-modes)

## Overview

Russula's constraint system enables declarative specification of generation requirements and validation criteria. The system is designed to be:

- **Explicit**: Requirements are clearly stated, not implicit in prompts
- **Composable**: Multiple constraints can be combined
- **Flexible**: Supports both LLM-based and programmatic validation
- **Psychologically Aware**: Avoids negative priming through the check mechanism

### Design Philosophy

Traditional prompt engineering often suffers from:
1. **Implicit requirements** buried in prose
2. **Negative priming** ("don't do X" makes the model think about X)
3. **Unreliable validation** (hoping the model follows instructions)

Russula solves this by separating concerns:
- **Requirements**: Explicit expectations added to prompts
- **Checks**: Post-generation validation without negative priming
- **Validators**: Programmatic or LLM-based verification

## Three-Tier System

The constraint system has three tiers:

### Tier 1: Requirements
- **Included in prompt**: YES
- **Validated**: YES
- **Purpose**: Explicit expectations the model should meet
- **Use case**: Positive guidance ("be polite", "include greeting")

### Tier 2: Checks
- **Included in prompt**: NO
- **Validated**: YES
- **Purpose**: Validation criteria that shouldn't prime the model
- **Use case**: Negative criteria ("avoid profanity", "no passive voice")

### Tier 3: Type Constraints
- **Included in prompt**: NO (enforced via return type)
- **Validated**: YES
- **Purpose**: Structural output requirements
- **Use case**: Ensure output matches expected type (see [TYPE_SYSTEM.md](TYPE_SYSTEM.md))

## Requirement Specification

### Definition

A **Requirement** is a constraint that:
1. Is added to the generation prompt
2. Is validated after generation
3. Provides positive guidance to the model

### Creation

```ruby
requirement = Russula.req(description, validation_fn: nil)
```

**Parameters:**
- `description` (String): Human-readable requirement
- `validation_fn` (Proc, optional): Custom validation function

### Prompt Inclusion Rules

Requirements are included in the prompt using this template:

```
[Original Prompt]

Requirements:
- [Requirement 1 description]
- [Requirement 2 description]
- ...
```

**Example:**

```ruby
session.instruct(
  'Write an email inviting the team to a party.',
  requirements: [
    Russula.req('use "Dear Team" as greeting'),
    Russula.req('mention the date Friday, March 15th')
  ]
)
```

**Resulting Prompt:**
```
Write an email inviting the team to a party.

Requirements:
- use "Dear Team" as greeting
- mention the date Friday, March 15th
```

### Validation Behavior

After generation, each requirement is validated:

1. **If `validation_fn` provided:**
   - Call `validation_fn` with generated text or context
   - Return boolean result

2. **If no `validation_fn`:**
   - Use LLM-as-a-judge validation
   - Ask the LLM if the requirement is satisfied
   - Parse yes/no response

### Interface

```ruby
class Requirement
  attr_reader :description, :validation_fn

  def initialize(description, validation_fn: nil)
    @description = description
    @validation_fn = validation_fn
  end

  def validate(text_or_context, session)
    if @validation_fn
      call_custom_validator(text_or_context)
    else
      llm_as_judge_validate(text_or_context, session)
    end
  end

  def include_in_prompt
    true
  end

  def use_llm_validation?
    @validation_fn.nil?
  end
end
```

### Examples

**Simple requirement with LLM validation:**
```ruby
req('be polite and professional')
# Added to prompt, validated by LLM
```

**Requirement with custom validator:**
```ruby
req('contain greeting',
    validation_fn: ->(text) { text.match?(/hello|hi|dear/i) })
# Added to prompt, validated programmatically
```

**Requirement with length constraint:**
```ruby
req('be brief (under 100 words)',
    validation_fn: ->(text) { text.split.count < 100 })
# Added to prompt, validated programmatically
```

## Check Specification

### Definition

A **Check** is a constraint that:
1. Is NOT added to the generation prompt
2. Is validated after generation
3. Avoids negative priming the model

### Why Checks Exist (Negative Priming)

**Problem:** Telling an LLM "don't do X" makes it think about X, increasing the likelihood of X.

Example:
- Prompt: "Write a story. Don't include violence."
- Result: Model is primed to think about violence, may generate violent content.

**Solution:** Use a check instead:
```ruby
session.instruct(
  'Write a story.',
  checks: [
    Russula.check('no violence',
                  validation_fn: ->(text) { !text.match?(/blood|kill|weapon/i) })
  ]
)
```

The prompt is simply "Write a story." but the output is validated for violence.

### Creation

```ruby
check = Russula.check(description, validation_fn: nil)
```

**Parameters:** Same as `req`

### Validation Behavior

Identical to Requirements:
1. Custom validator if provided
2. LLM-as-a-judge otherwise

**Key Difference:** The description is never shown to the model during generation.

### Interface

```ruby
class Check < Requirement
  def include_in_prompt
    false  # Never included in prompt
  end
end
```

Checks inherit from `Requirement` but override `include_in_prompt`.

### Examples

**Avoid profanity (negative criterion):**
```ruby
check('no profanity',
      validation_fn: ->(text) { !text.match?(/damn|hell|shit/i) })
```

**Avoid passive voice (LLM-judged):**
```ruby
check('avoid passive voice')
# Not in prompt, but validated by LLM after generation
```

**Ensure brevity without priming:**
```ruby
check('under 50 words',
      validation_fn: ->(text) { text.split.count < 50 })
```

## Custom Validator Protocol

### Function Signatures

Validators can have two signatures:

#### 1. Text Validator
```ruby
Proc(String) -> Boolean
```

**Input:** Generated text as string
**Output:** `true` if valid, `false` otherwise

**Example:**
```ruby
->(text) { text.length < 100 }
```

#### 2. Context Validator
```ruby
Proc(Context) -> Boolean
```

**Input:** Full conversation context
**Output:** `true` if valid, `false` otherwise

**Example:**
```ruby
lambda { |context|
  # Ensure at least 2 messages in history
  context.messages.count >= 2
}
```

### Signature Detection

The validation engine determines which signature to use:

```ruby
def call_custom_validator(text_or_context)
  if @validation_fn.arity == 1
    # Could be text or context validator
    # Try passing text first, fall back to context
    begin
      @validation_fn.call(text_or_context.is_a?(String) ? text_or_context : text_or_context.messages.last[:content])
    rescue ArgumentError
      @validation_fn.call(text_or_context)
    end
  else
    @validation_fn.call(text_or_context)
  end
end
```

**Recommendation:** Use lambda for context validators, proc/stabby lambda for text validators.

### Return Values

Validators MUST return a boolean:
- `true`: Constraint satisfied
- `false`: Constraint violated

**Non-boolean returns are treated as errors.**

### Error Handling

If a custom validator raises an exception:

```ruby
def call_custom_validator(text_or_context)
  @validation_fn.call(text_or_context)
rescue StandardError => e
  raise Russula::ValidationError,
        "Validator for '#{@description}' raised: #{e.message}"
end
```

**Best Practice:** Validators should handle edge cases and return `false` instead of raising.

### Examples

**Simple text validator:**
```ruby
req('contain keyword',
    validation_fn: ->(text) { text.include?('keyword') })
```

**Complex text validator:**
```ruby
req('valid email format',
    validation_fn: lambda { |text|
      text.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
    })
```

**Context-aware validator:**
```ruby
req('maintain conversation flow',
    validation_fn: lambda { |context|
      # Ensure response references previous user message
      last_user_msg = context.messages.reverse.find { |m| m[:role] == :user }
      last_assistant_msg = context.messages.last

      last_user_msg && last_assistant_msg &&
        last_assistant_msg[:content].length > 0
    })
```

## LLM-as-a-Judge Algorithm

When no custom validator is provided, Russula uses the LLM to validate requirements.

### Prompt Template

```ruby
VALIDATION_TEMPLATE = <<~PROMPT
  Does the following text satisfy this requirement: "%{requirement}"?

  Text:
  %{text}

  Answer only 'yes' or 'no'.
PROMPT
```

### Validation Process

```ruby
def llm_as_judge_validate(text, session)
  # 1. Construct validation prompt
  prompt = format(VALIDATION_TEMPLATE,
                  requirement: @description,
                  text: text)

  # 2. Call LLM with validation prompt
  response = session.backend.generate([
    {role: :user, content: prompt}
  ])

  # 3. Parse response
  parse_boolean_response(response)
end
```

### Response Parsing

The parser accepts multiple affirmative/negative forms:

**Affirmative Responses** (return `true`):
- "yes"
- "Yes"
- "YES"
- "true"
- "True"
- "TRUE"
- "correct"
- "Correct"
- Responses starting with "yes" (e.g., "Yes, it does")

**Negative Responses** (return `false`):
- "no"
- "No"
- "NO"
- "false"
- "False"
- "FALSE"
- "incorrect"
- "Incorrect"
- Responses starting with "no" (e.g., "No, it doesn't")

**Implementation:**
```ruby
def parse_boolean_response(response)
  normalized = response.strip.downcase

  # Check affirmative
  return true if normalized.match?(/^(yes|true|correct)/)

  # Check negative
  return false if normalized.match?(/^(no|false|incorrect)/)

  # Ambiguous response - default to false
  false
end
```

### Ambiguous Responses

If the LLM returns an unexpected response (e.g., "maybe", "unclear"), the validator **defaults to `false`** (failed validation).

**Rationale:** Conservative approach favors false negatives over false positives.

### Examples

**Requirement:** "be polite"

**Validation Prompt:**
```
Does the following text satisfy this requirement: "be polite"?

Text:
Hey there! How can I help you today?

Answer only 'yes' or 'no'.
```

**LLM Response:** "Yes"
**Result:** `true` (requirement satisfied)

---

**Requirement:** "include a greeting"

**Validation Prompt:**
```
Does the following text satisfy this requirement: "include a greeting"?

Text:
The meeting is scheduled for 3pm.

Answer only 'yes' or 'no'.
```

**LLM Response:** "No"
**Result:** `false` (requirement not satisfied)

## Constraint Evaluation Order

### Evaluation Sequence

1. **Generation**: Backend generates text
2. **Type Validation** (if applicable): Check return type constraint
3. **Requirement Validation**: Validate all requirements
4. **Check Validation**: Validate all checks

### Short-Circuit Logic

**Current Behavior (MVP):**
- All constraints are evaluated even if one fails
- This provides complete feedback on what's wrong

**Future Optimization:**
- Short-circuit on first failure for performance
- Configurable via strategy option

### Evaluation Example

```ruby
session.instruct(
  'Write a greeting',
  requirements: [
    req('be polite'),           # Evaluated 1st
    req('include "hello"')      # Evaluated 2nd
  ],
  checks: [
    check('no slang'),          # Evaluated 3rd
    check('under 50 words')     # Evaluated 4th
  ]
)
```

**Evaluation Flow:**
```
1. Generate text
2. Validate: "be polite" -> true
3. Validate: "include hello" -> true
4. Validate: "no slang" -> true
5. Validate: "under 50 words" -> true
6. All pass -> Return success
```

If any step fails, the result is recorded and the loop may retry (depending on strategy).

### Parallel Validation (Future)

Constraints could be validated in parallel for performance:

```ruby
results = constraints.map do |constraint|
  Thread.new { constraint.validate(text, session) }
end.map(&:value)

all_pass = results.all?
```

**Trade-off:** Increases LLM API calls but reduces latency.

## Failure Modes

### Validation Failures

**Scenario:** One or more constraints fail validation

**Behavior:**
1. Strategy records failure
2. Strategy retries (if budget remaining)
3. If budget exhausted: Raise `ValidationError`

**Error Details:**
```ruby
raise Russula::ValidationError,
      "Validation failed after #{attempts} attempts. " \
      "Failed constraints: #{failed_constraint_descriptions.join(', ')}"
```

### Custom Validator Errors

**Scenario:** Custom validator raises exception

**Behavior:**
```ruby
rescue StandardError => e
  raise Russula::ValidationError,
        "Validator for '#{description}' raised: #{e.message}"
```

**Implication:** Validator errors are treated as validation failures, not implementation bugs.

### LLM-as-a-Judge Failures

**Scenario:** LLM returns unexpected response or fails

**Behavior:**
1. Parse attempt with lenient parsing
2. Default to `false` if ambiguous
3. If backend error: Propagate as `BackendError`

### Type Constraint Violations

**Scenario:** Generated text doesn't match return type constraint

**Behavior:**
- Raise `ValidationError` immediately
- No retry (type violations are contract violations, not fixable by retry)

## Best Practices

### When to Use Requirements

✅ **Use requirements for:**
- Positive expectations ("be formal", "include greeting")
- Structural requirements ("use bullet points")
- Content inclusions ("mention the date")

❌ **Avoid requirements for:**
- Negative criteria ("don't be rude") → Use checks instead
- Complex logic → Use custom validators

### When to Use Checks

✅ **Use checks for:**
- Negative criteria ("no profanity", "avoid passive voice")
- Silent validation (don't want to prime the model)
- Post-generation filtering

❌ **Avoid checks for:**
- Positive guidance → Use requirements instead

### When to Use Custom Validators

✅ **Use custom validators for:**
- Programmatic checks (length, regex, format)
- Performance (faster than LLM-as-a-judge)
- Deterministic validation

❌ **Avoid custom validators for:**
- Subjective criteria → Use LLM-as-a-judge
- Complex semantic validation → Use LLM-as-a-judge

## Examples

### Complete Example: Email Generation

```ruby
email = session.instruct(
  'Write a professional email to the customer about their delayed order.',
  requirements: [
    req('use "Dear Valued Customer" as greeting'),
    req('apologize for the delay'),
    req('offer 10% discount as compensation'),
    req('include expected delivery date')
  ],
  checks: [
    check('no negative language',
          validation_fn: ->(text) { !text.match?(/unfortunately|regret|problem/i) }),
    check('under 200 words',
          validation_fn: ->(text) { text.split.count < 200 })
  ],
  strategy: Russula::RejectionSamplingStrategy.new(loop_budget: 5)
)
```

**Prompt sent to LLM:**
```
Write a professional email to the customer about their delayed order.

Requirements:
- use "Dear Valued Customer" as greeting
- apologize for the delay
- offer 10% discount as compensation
- include expected delivery date
```

**Validation:**
- All 4 requirements validated (likely via LLM-as-a-judge)
- Both checks validated (via custom functions)
- Up to 5 retries if any fail

## See Also

- [Architecture Specification](ARCHITECTURE.md)
- [API Specification](API_SPECIFICATION.md)
- [Validation Algorithm](VALIDATION_ALGORITHM.md)
- [Type System](TYPE_SYSTEM.md)
