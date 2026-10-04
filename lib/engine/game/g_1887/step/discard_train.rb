# frozen_string_literal: true

require_relative '../../../step/discard_train'
require_relative 'railway_only'

module Engine
  module Game
    module G1887
      module Step
        # A Railway over the train limit (the limit drops at the first 4- and
        # 6-train) discards the extras, its president choosing which. The
        # standard step; discarded trains are removed from the game
        # (DISCARDED_TRAINS = :remove), as in 1871.
        class DiscardTrain < Engine::Step::DiscardTrain
          include RailwayOnly

          def process_discard_train(action)
            train = action.train
            raise GameError, "#{train.name}-train is not #{action.entity.name}'s" unless action.entity.trains.include?(train)

            @game.depot.reclaim_train(train)
            @log << "#{action.entity.name} discards a #{train.name}-train; it is removed from the game"
          end
        end
      end
    end
  end
end
