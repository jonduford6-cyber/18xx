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
