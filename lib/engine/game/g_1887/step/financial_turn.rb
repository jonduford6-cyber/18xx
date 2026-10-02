# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G1887
      module Step
        # The operating turn of a Finance House or Construction Company.
        # Selling and the four financial actions (11.3) are not built yet,
        # so Pass is the only choice.
        class FinancialTurn < Engine::Step::Base
          ACTIONS = %w[pass].freeze

          def actions(entity)
            entity == current_entity ? ACTIONS : []
          end

          def active?
            @game.financial?(current_entity) && super
          end

          def description
            'Financial Turn'
          end

          def pass_description
            'Pass (price moves left)'
          end

          # 11.3: taking no action moves the price one space left (down a
          # row at the left edge of the market).
          def process_pass(action)
            super
            entity = action.entity
            old_price = entity.share_price
            @game.stock_market.move_left(entity)
            @game.log_share_price(entity, old_price)
          end
        end
      end
    end
  end
end
