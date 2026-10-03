# frozen_string_literal: true

require_relative '../../../step/bankrupt'
require_relative 'railway_only'

module Engine
  module Game
    module G1887
      module Step
        # 11.9, 12: the standard "Declare Bankruptcy" button, shown only when
        # the player at the top of an emergency cannot cover it. The game
        # ends at once; the player keeps their cash, certificates and
        # privates and is scored on them like everyone else.
        class Bankrupt < Engine::Step::Bankrupt
          include RailwayOnly

          def process_bankrupt(action)
            railway = action.entity
            buy = @round.steps.find { |s| s.is_a?(G1887::Step::BuyTrain) }
            player = buy&.top_player(railway)
            if !player || !@game.can_go_bankrupt?(player, railway)
              raise GameError, "#{railway.name}'s train can still be paid for: bankruptcy is not allowed"
            end

            @log << "-- #{player.name} is bankrupt: cannot cover the #{@game.format_currency(buy.shortfall(railway))} " \
                    "still missing for #{railway.name}'s train. The game ends --"
            @game.declare_bankrupt(player)
          end
        end
      end
    end
  end
end
