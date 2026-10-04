# frozen_string_literal: true

require_relative '../../../step/reduce_tokens'

module Engine
  module Game
    module G1887
      module Step
        # 11.3.4: a merged Railway over its charter's station limit removes
        # tokens of its president's choice. The shared ReduceTokens step (its
        # remove-token action, map clicks and token merger, as 1828 and 1867
        # use it); only the limit is per charter instead of one game-wide
        # LIMIT_TOKENS_AFTER_MERGER.
        class MergeTokens < Engine::Step::ReduceTokens
          def limit(corporation = surviving)
            @game.class::STATION_LIMIT.fetch(corporation.id)
          end

          def description
            "Remove station tokens (limit #{limit})"
          end

          def tokens_above_limits?(surviving, others)
            tokens = surviving.tokens.map(&:hex).compact
            tokens.uniq.size != tokens.size ||
              tokens_in_same_hex(surviving, others) ||
              (surviving.tokens + others_tokens(others)).count(&:used) > limit(surviving)
          end

          # As the shared token merger, with the charter's own limit
          def move_tokens_to_surviving(surviving, others, price_for_new_token: 0, check_tokenable: false)
            used, unused = surviving.tokens.partition(&:used)
            moved = others_tokens(others).map do |token|
              new_token = Engine::Token.new(surviving, price: price_for_new_token)
              if token.hex
                used << new_token
                token.swap!(new_token, check_tokenable: check_tokenable)
              else
                unused << new_token
              end
              new_token.hex&.id
            end
            raise GameError, 'Used token above limit' if used.size > limit(surviving)

            surviving.tokens.clear
            surviving.tokens.concat((used + unused.sort_by(&:price)).first(limit(surviving)))
            @game.graph.clear_graph_for(surviving)
            others.each { |o| o.reset_tokens! if o.retired } # the retired charter's tokens back on its card
            moved
          end
        end
      end
    end
  end
end
