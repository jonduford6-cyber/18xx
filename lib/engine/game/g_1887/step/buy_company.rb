# frozen_string_literal: true

require_relative '../../../step/buy_company'
require_relative 'railway_only'

module Engine
  module Game
    module G1887
      module Step
        # 14: from phase 3 a Railway may buy, from its own player president,
        # one of the corporate-purchasable privates (game.rb,
        # purchasable_companies) at half to double face value, paid from its
        # treasury. The standard step and panel; only these checks are added.
        class BuyCompany < Engine::Step::BuyCompany
          include RailwayOnly

          def process_buy_company(action)
            entity = action.entity
            company = action.company
            unless @game.purchasable_companies(entity).include?(company)
              raise GameError, "#{entity.name} cannot buy #{company.name}"
            end
            if action.price > entity.cash
              raise GameError, "#{entity.name} has only #{@game.format_currency(entity.cash)}"
            end

            super
          end
        end
      end
    end
  end
end
