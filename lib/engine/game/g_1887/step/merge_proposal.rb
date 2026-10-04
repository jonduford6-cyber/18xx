# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G1887
      module Step
        # Merger Round: the current player proposes one merger (Contested
        # merger: put to a vote) or passes. Standard Choose buttons
        # ("Propose BAGS+SFW") and the standard Pass button.
        class MergeProposal < Engine::Step::Base
          def actions(entity)
            return [] if entity != current_entity || !entity.player? || options(entity).empty?

            %w[choose pass]
          end

          def round_state
            { merged: [], rejected: [], proposal: nil }
          end

          def description
            'Merger Round'
          end

          def pass_description
            'Pass'
          end

          def options(entity)
            @game.proposal_options(entity, 'Propose')
          end

          def choice_name
            current_entity.name
          end

          def choices
            options(current_entity).to_h { |choice, label, _, _| [choice, label] }
          end

          def process_choose(action)
            player = action.entity
            option = options(player).find { |choice, _, _, _| choice == action.choice }
            raise GameError, "#{player.name} cannot propose that merger now" unless option

            player.unpass!
            _, _, survivor, retired = option
            @round.proposal = { proposer: player, survivor: survivor, retired: retired }
            start_vote(player, survivor, retired)
            pass! # the proposal is the player's turn
          end

          def start_vote(player, survivor, retired)
            @log << "#{player.name} proposes a merger of #{survivor.name} and #{retired.name} " \
                    "(#{survivor.name} keeps its charter)"
            @round.to_vote = @game.vote_blocks(player, survivor, retired).map { |p, h, n| [p, h, n] }
            @round.votes_yes = 0
            @round.votes_no = 0
            @game.decide_vote! if @round.to_vote.empty?
          end

          def process_pass(action)
            action.entity.pass!
            @log << "#{action.entity.name} passes"
            pass!
          end

          def skip!
            current_entity&.pass!
            pass!
          end
        end
      end
    end
  end
end
