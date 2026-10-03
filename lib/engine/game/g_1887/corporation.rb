# frozen_string_literal: true

require_relative '../../corporation'

module Engine
  module Game
    module G1887
      class Corporation < Engine::Corporation
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
