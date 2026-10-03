# frozen_string_literal: true

require_relative '../../../round/operating'

module Engine
  module Game
    module G1887
      module Round
        class Operating < Engine::Round::Operating
          # As 1841: a corporation whose president is a corporation keeps
          # its turn while a player at the top of the chain controls it.
          # (The shared check ends the turn after one action whenever the
          # president is not a player.)
          # 11.1: re-sort the corporations still to operate by current price
          # (the ones that already operated keep their place); say so in the
          # log when the order changes
          def recalculate_order
            before = @entities.drop(@entity_index + 1)
            super
            after = @entities.drop(@entity_index + 1)
            return if after == before

            @log << "Operating order rechecked: #{after.map(&:name).join(', ')} still to operate"
          end

          # Any price change during a turn counts before the next corporation
          # is chosen
          def next_entity!
            recalculate_order
            super
          end

          def after_process(action)
            return if action.type == 'message'

            @current_operator_acted = true if action.entity.corporation == @current_operator

            if active_step
              entity = @entities[@entity_index]
              return if @game.controller(entity)&.player? || entity.receivership?
            end

            after_end_of_turn(@current_operator)

            next_entity! unless @game.finished
          end
        end
      end
    end
  end
end
