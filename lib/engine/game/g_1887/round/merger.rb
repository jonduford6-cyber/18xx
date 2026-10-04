# frozen_string_literal: true

require_relative '../../../round/merger'

module Engine
  module Game
    module G1887
      module Round
        # The merger variants' Merger Round (after each Operating Round set),
        # as 18Ireland's: the players in priority order each propose one
        # merger or pass, round the table until all have passed in turn; a
        # player who passed may propose later. The resolution steps
        # (unpaired choices, tokens, trains) run inside it.
        class Merger < Engine::Round::Merger
          def self.round_name
            'Merger Round'
          end

          def self.short_name
            'MR'
          end

          def select_entities
            @game.players.reject(&:bankrupt)
          end

          def setup
            super
            skip_steps
            next_entity! if !finished? && !active_step
          end

          def after_process(action)
            return if action.free?
            return if active_step

            next_entity!
          end

          def next_entity!
            next_entity_index! if @entities.any?
            return if @entities.all?(&:passed?)

            @steps.each(&:unpass!)
            @steps.each(&:setup)
            skip_steps
            next_entity! if !finished? && !active_step # nothing to propose: passes
          end

          def finished?
            @game.finished || @entities.all?(&:passed?)
          end
        end
      end
    end
  end
end
