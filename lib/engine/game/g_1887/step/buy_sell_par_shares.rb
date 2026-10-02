# frozen_string_literal: true

require_relative '../../../step/buy_sell_par_shares'

module Engine
  module Game
    module G1887
      module Step
        # Players never start (par) a corporation. They may buy only an
        # ordinary certificate of a corporation with a market price, from
        # the bank pool or from that corporation's own treasury.
        class BuySellParShares < Engine::Step::BuySellParShares
          def can_ipo_any?(_entity)
            false
          end

          def can_buy?(entity, bundle)
            return false unless bundle

            corporation = bundle.corporation
            return false unless corporation.share_price
            return false if bundle.presidents_share

            sources = [corporation, @game.share_pool]
            return false unless sources.include?(bundle.owner)

            super
          end

          # Only a corporation's own certificates, not seeds it holds
          def can_buy_any_from_ipo?(entity)
            @game.corporations.any? do |c|
              c.share_price && can_buy_shares?(entity, c.shares_of(c))
            end
          end
        end
      end
    end
  end
end
