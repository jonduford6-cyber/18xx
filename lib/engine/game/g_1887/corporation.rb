# frozen_string_literal: true

require_relative '../../corporation'

module Engine
  module Game
    module G1887
      class Corporation < Engine::Corporation
        # Started by a player and not yet floated (3.3, 13.3): its other
        # certificates are in the bank pool, sold at par, paid to the bank
        attr_accessor :founding

        def floated?
          return false if @founding

          super
        end

        # 10.5: after the founding payment, Treasury certificates sell at the
        # market price (always_market_price). While a started company's
        # marker waits beside the market it has no market price yet, so its
        # par is still shown and used to place the marker.
        def par_price
          return if closed?

          (@always_market_price && @share_price) || @par_price
        end
      end
    end
  end
end
