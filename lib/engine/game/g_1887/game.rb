# frozen_string_literal: true

require_relative 'entities'
require_relative 'map'
require_relative 'meta'
require_relative '../base'

module Engine
  module Game
    module G1887
      class Game < Game::Base
        include_meta(G1887::Meta)
        include Entities
        include Map

        CURRENCY_FORMAT_STR = '$%s'

        # Placeholder: 1887.json does not give a bank size.
        BANK_CASH = 12_000

        CERT_LIMIT = { 3 => 20, 4 => 16 }.freeze

        STARTING_CASH = { 3 => 700, 4 => 520 }.freeze

        # The top-right cell (516) is marked 'e': reaching it ends the game.
        MARKET = [
          %w[194 210 226 245 264 285 308 333 359 388 419 453 489 516e],
          %w[161 174 188 203 219 237 256 276 298 322 348 376 406 438],
          %w[134 144 156p 168 182 197 212 229 248 267 289 312 337],
          %w[111 120 130p 140 152 164 177 191 206 223 241 260],
          %w[93 100 108p 117 126 136 147 159 171 185 200],
          %w[79 85 92p 99 107 116 125 135 146 158],
          %w[65 70 76p 82 89 96 103 112 121 131],
          %w[51 56 60p 66 71 77 83 88 95],
          %w[43 46 50 54 58 63 68 73],
          %w[35 38 41 45 48 52 57],
          %w[29 32 34 37 40 44],
          %w[24 26 28 31 33],
          %w[20 22 25 27],
        ].freeze

        GAME_END_CHECK = { bankrupt: :immediate, stock_market: :immediate, bank: :full_or }.freeze

        PHASES = [
          {
            name: '2',
            train_limit: 4,
            tiles: [:yellow],
            operating_rounds: 1,
          },
          {
            name: '3',
            on: '3',
            train_limit: 4,
            tiles: %i[yellow green],
            operating_rounds: 2,
          },
          {
            name: '4',
            on: '4',
            train_limit: 3,
            tiles: %i[yellow green],
            operating_rounds: 2,
          },
          {
            name: '5',
            on: '5',
            train_limit: 3,
            tiles: %i[yellow green brown],
            operating_rounds: 3,
          },
          {
            name: '6',
            on: '6',
            train_limit: 2,
            tiles: %i[yellow green brown],
            operating_rounds: 3,
          },
          {
            name: 'D',
            on: 'D',
            train_limit: 2,
            tiles: %i[yellow green brown],
            operating_rounds: 3,
          },
        ].freeze

        TRAINS = [
          { name: '2', distance: 2, price: 80, rusts_on: '4', num: 7 },
          { name: '3', distance: 3, price: 150, rusts_on: '5', num: 5 },
          { name: '4', distance: 4, price: 250, rusts_on: '6', num: 3 },
          { name: '5', distance: 5, price: 400, rusts_on: 'D', num: 3 },
          { name: '6', distance: 6, price: 500, num: 2 },
          { name: 'D', distance: 999, price: 700, num: 'unlimited' },
        ].freeze

        # Charter private => the Finance House it floats
        CHARTERS = { 'BARC' => 'BB', 'HAMC' => 'HAM', 'MURC' => 'MUR' }.freeze

        def after_buy_company(player, company, price)
          return super unless (fh_id = CHARTERS[company.id])

          float_finance_house(player, company, corporation_by_id(fh_id), price)
        end

        def float_finance_house(player, charter, fh, price)
          stock_market.set_par(fh, finance_house_par(price))
          share_pool.buy_shares(player, fh.presidents_share, exchange: :free)

          @bank.spend(price, fh)
          @log << "#{fh.name} receives #{format_currency(price)} " \
                  "(the winning bid for #{charter.name})"

          charter.close!
          @log << "#{charter.name} closes"
        end

        # Highest par price not above half the winning bid
        def finance_house_par(price)
          pars = stock_market.par_prices.sort_by(&:price)
          pars.reverse.find { |p| p.price * 2 <= price } || pars.first
        end
      end
    end
  end
end
