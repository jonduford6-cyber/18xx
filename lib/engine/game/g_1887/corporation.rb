# frozen_string_literal: true

require_relative '../../corporation'

module Engine
  module Game
    module G1887
      class Corporation < Engine::Corporation
        # Started by a player and not yet floated (3.3, 13.3): its other
        # certificates are in the bank pool, sold at par, paid to the bank
        attr_accessor :founding

        # 11.3.4: the charter retired by a merge (out of the game for now)
        attr_reader :retired

        # Part B: a retired charter started again (no subsidy; a Railway
        # chooses its home station when it floats)
        attr_reader :restarted

        def floated?
          return false if @founding || @retired

          super
        end

        def initialize(**opts)
          super
          @token_prices = @tokens.map(&:price)
        end

        # A retired charter is reset as one never started: no president, no
        # marker, no history, no treasury, its tokens back on its charter
        def retire!
          @retired = true
          @owner = nil
          @floated = false
          @ipoed = false
          @founding = nil
          @share_price = nil
          @par_price = nil
          @trains = []
          @companies = []
          @cash = 0
          @operating_history = {}
          reset_tokens! if @tokens.none?(&:used)
        end

        def restart!
          @retired = false
          @restarted = true
          @capitalization = :incremental # no bank capital at the float (BAGS and BAWR were full)
          @coordinates = nil unless @token_prices.empty? # a Railway: its home is chosen at the start
        end

        def reset_tokens!
          @tokens = @token_prices.map { |price| Engine::Token.new(self, price: price) }
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
