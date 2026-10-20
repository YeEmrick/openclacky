# frozen_string_literal: true

module Clacky
  module Server
    # GET /api/model_prices?models=a,b,c
    # Resolves each model's input/output price (USD per 1M tokens) from
    # Clacky::ModelPricing plus a cost ratio vs the baseline model, so the
    # web UI never hardcodes prices - updating PRICING_TABLE is enough.
    # Prices are what the platform actually bills: post-promotion rates plus
    # any lane markup. `discount` is present when a promotion applied,
    # carrying both the rate and its reason ("channel" or "promo") so the UI
    # can pick the right explanation.
    module ModelPrices
      BASELINE_MODEL = "claude-sonnet-5"

      def self.build(models_query, now: Time.now)
        names = (models_query || "").split(",").map(&:strip).reject(&:empty?)

        baseline = Clacky::ModelPricing.get_pricing(BASELINE_MODEL)
        base_total = baseline[:input][:default] + baseline[:output][:default]

        prices = {}
        names.each do |name|
          pricing = Clacky::ModelPricing.get_pricing(name)
          pricing = Clacky::ModelPricing.resolve_deepseek_tier(pricing, now) if pricing && pricing[:deepseek]
          next unless pricing
          info = Clacky::ModelPricing.discount_info(name)
          rate = info ? info[:rate] : 1.0
          markup = Clacky::ModelPricing.markup_rate(name)
          # Rates are not powers of two, so the discounted product carries float
          # noise (3.0 * 0.95 == 2.8499999999999996) that would surface verbatim
          # in the picker tooltips. Four decimals is already finer than any
          # listed price.
          pin  = (pricing[:input][:default] * rate * markup).round(4)
          pout = (pricing[:output][:default] * rate * markup).round(4)
          entry = { in: pin, out: pout, ratio: (pin + pout) / base_total }
          entry[:discount] = { rate: rate, reason: info[:reason] } if rate < 1.0
          prices[name] = entry
        end

        {
          baseline: {
            model: BASELINE_MODEL,
            in: baseline[:input][:default],
            out: baseline[:output][:default]
          },
          prices: prices
        }
      end
    end
  end
end
