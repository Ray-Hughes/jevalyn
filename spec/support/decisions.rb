# frozen_string_literal: true

# The decision from the README, used across specs so one wrong assumption about the
# API shape shows up in every file rather than hiding in one.
class SupportTriage < Jevalyn::Decision
  question :urgent, type: :noul,
                    instructions: "Does this convey urgency?"

  question :department, type: :choice,
                        instructions: "Which team should handle this?",
                        criteria: {
                          billing: "Payments, invoicing, refunds",
                          technical: "Bugs, outages, integrations",
                          sales: "Pricing, upgrades, new accounts"
                        }

  question :severity, type: :score,
                      instructions: "How severe is this issue?",
                      criteria: %w[trivial minor major critical]

  confidence_threshold 0.75
end

class ToolCallGuardrail < Jevalyn::Guardrail
  question :safe_to_execute, type: :noul,
                             instructions: "Is this tool call safe to run without human review?"

  allow_above 0.9
end
