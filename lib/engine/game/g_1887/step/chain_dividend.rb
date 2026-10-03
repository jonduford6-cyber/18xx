# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G1887
      module Step
        # 11.7: a corporation that received money from a company it
        # presides over pays it on or withholds it, before the Railway goes
        # on to buy trains. One corporation at a time, from the round's
        # waiting list (filled by Game#chain_receive). The player at the
        # top of the chain acts. Buttons, as for Buy.
        class ChainDividend < Engine::Step::Base
          def round_state
            super.merge(chain_pending: [])
          end

          def pending
            @round.chain_pending
          end

          def active?
            !pending.empty?
          end

          def active_entities
            pending.empty? ? [] : [pending.first[:corporation]]
          end

          def actions(entity)
            entity == current_entity ? %w[choose] : []
          end

          def description
            'Pay or Withhold'
          end

          def choice_name
            entry = pending.first
            "#{entry[:corporation].name} receives #{@game.format_currency(entry[:amount])} from #{entry[:from].name}"
          end

          def choices
            entry = pending.first
            corp = entry[:corporation]
            amount = @game.format_currency(entry[:amount])
            per_share = @game.format_currency(entry[:amount].div(corp.total_shares))
            {
              'payout' => "Pay out #{amount} (#{per_share} per share, price moves right)",
              'withhold' => "Withhold (#{amount} stays in #{corp.name}, price stays)",
            }
          end

          def process_choose(action)
            entry = pending.first
            raise GameError, "#{action.entity.name} has no payment to pay or withhold" unless action.entity == entry[:corporation]
            raise GameError, "Unknown choice #{action.choice}" unless choices.key?(action.choice)

            pending.shift
            if action.choice == 'payout'
              @game.chain_pay_on(entry[:corporation], entry[:amount])
            else
              @game.chain_withhold(entry[:corporation], entry[:amount])
            end
          end
        end
      end
    end
  end
end
