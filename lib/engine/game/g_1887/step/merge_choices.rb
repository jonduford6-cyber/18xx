# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G1887
      module Step
        # 11.3.4: after a merge, each holder of one unpaired unit chooses, in
        # stock market order: half the merged price in cash from the bank,
        # or pay the other half for a whole new certificate (only while one
        # nobody received (in the bank pool), and only if it can pay; Lombard
        # Street pays from its own treasury first, then its owner)
        class MergeChoices < Engine::Step::Base
          def actions(entity)
            return [] unless entity == current_entity

            %w[choose]
          end

          def active?
            !pending.empty?
          end

          def active_entities
            pending.empty? ? [] : [pending.first[0]]
          end

          def pending
            @round.merge_unpaired || []
          end

          def round_state
            { merge_unpaired: [], merge_spare: 0 }
          end

          def description
            'Unpaired Certificate'
          end

          def survivor
            pending.first[1]
          end

          def half
            survivor.share_price.price.div(2)
          end

          def payers(holder)
            holder.minor? ? [holder, holder.owner] : [holder]
          end

          def can_buy?(holder)
            @round.merge_spare.positive? && payers(holder).sum(&:cash) >= half
          end

          def choice_name
            current_entity.name
          end

          def choices
            holder = current_entity
            fmt = @game.format_currency(half)
            list = { 'cash' => "Take #{fmt}" }
            list['buy'] = "Buy 1 (#{fmt})" if can_buy?(holder)
            list
          end

          def process_choose(action)
            holder = action.entity
            raise GameError, "#{holder.name} has no unpaired certificate now" unless holder == current_entity

            corp = survivor
            if action.choice == 'buy'
              raise GameError, "#{holder.name} cannot buy a #{corp.name} certificate" unless can_buy?(holder)

              due = half
              payers(holder).each do |payer|
                amount = [due, payer.cash].min
                payer.spend(amount, @game.bank) if amount.positive?
                due -= amount
              end
              share = @game.share_pool.shares_of(corp).find { |s| !s.president }
              @game.share_pool.transfer_shares(share.to_bundle, holder, allow_president_change: false)
              @round.merge_spare -= 1
              @log << "#{holder.name} pays #{@game.format_currency(half)} for a #{share.percent}% #{corp.name} certificate"
            else
              @game.bank.spend(half, holder)
              @log << "#{holder.name} takes #{@game.format_currency(half)} for an unpaired #{corp.name} certificate"
            end
            pending.shift
          end
        end
      end
    end
  end
end
