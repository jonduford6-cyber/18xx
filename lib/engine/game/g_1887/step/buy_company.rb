# frozen_string_literal: true

require_relative '../../../step/buy_company'
require_relative 'railway_only'

module Engine
  module Game
    module G1887
      module Step
        # 14: from phase 3 a Railway may buy, from the player at the top of
        # its chain of presidents, one of the corporate-purchasable privates
        # (game.rb, purchasable_companies) at half to double face value, paid
        # from its treasury. The standard step and panel; only these checks
        # are added. A Railway presided by a corporation buys only through the
        # first, non-blocking step (an optional extra action: no new step, no
        # Skip button); the blocking step at the end of the turn, with its
        # Skip button, stays for Railways with a player president.
        class BuyCompany < Engine::Step::BuyCompany
          include RailwayOnly

          def can_buy_company?(entity)
            return false if blocks? && !entity.owner&.player?

            super
          end

          def process_buy_company(action)
            entity = action.entity
            company = action.company
            unless @game.purchasable_companies(entity).include?(company)
              raise GameError, "#{entity.name} cannot buy #{company.name}"
            end
            raise GameError, "#{entity.name} has only #{@game.format_currency(entity.cash)}" if action.price > entity.cash

            super
          end
        end
      end
    end
  end
end
