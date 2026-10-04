# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G1887
      module Step
        # Contested merger: each voting block in turn, clockwise from the
        # proposer, casts all its votes yes or no (as 18Ireland's
        # MergerVote: standard Choose buttons). The heading names the holder
        # and its number of votes. The bank pool votes last, automatically
        # (Game#decide_vote!).
        class MergeVote < Engine::Step::Base
          def actions(entity)
            return [] if !active? || entity != current_entity

            %w[choose]
          end

          def round_state
            { to_vote: [], votes_yes: 0, votes_no: 0 }
          end

          def active?
            !@round.to_vote.empty?
          end

          def active_entities
            active? ? [@round.to_vote.first[0]] : []
          end

          def description
            'Vote on a Merger'
          end

          def choice_name
            _, holder, votes = @round.to_vote.first
            "#{holder.name}: #{votes} vote#{votes == 1 ? '' : 's'}"
          end

          def choices
            { 'yes' => 'Vote yes', 'no' => 'Vote no' }
          end

          def process_choose(action)
            player, holder, votes = @round.to_vote.first
            raise GameError, "It is #{player.name}'s vote" unless action.entity == player
            raise GameError, 'Vote yes or no' unless %w[yes no].include?(action.choice)

            if action.choice == 'yes'
              @round.votes_yes += votes
            else
              @round.votes_no += votes
            end
            who = holder == player ? player.name : "#{player.name} for #{holder.name}"
            @log << "#{who} votes #{action.choice} (#{votes} vote#{votes == 1 ? '' : 's'})"
            @round.to_vote.shift
            @game.decide_vote! if @round.to_vote.empty?
          end
        end
      end
    end
  end
end
