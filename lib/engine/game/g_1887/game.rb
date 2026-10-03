# frozen_string_literal: true

require_relative 'entities'
require_relative 'map'
require_relative 'meta'
require_relative 'corporation'
require_relative 'share_pool'
require_relative 'round/operating'
require_relative '../base'

module Engine
  module Game
    module G1887
      class Game < Game::Base
        include_meta(G1887::Meta)
        include Entities
        include Map

        CURRENCY_FORMAT_STR = '$%s'

        CORPORATION_CLASS = G1887::Corporation

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

        # 11.4: two track actions on two different hexes: two placements,
        # or one placement and one upgrade in either order (never two
        # upgrades, never the hex already built on this turn)
        TILE_LAYS = [
          { lay: true, upgrade: true, cost: 0 },
          { lay: true, upgrade: :not_if_upgraded, cost: 0, cannot_reuse_same_hex: true },
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
          { name: '6', distance: 6, price: 500, num: 3 },
          { name: 'D', distance: 999, price: 700, num: 'unlimited' },
        ].freeze

        # Optional rule: only two 6-trains
        def num_trains(train)
          return 2 if train[:name] == '6' && optional_rules.include?(:two_six_trains)

          super
        end

        FINANCE_HOUSES = %w[BB HAM MUR].freeze

        CONSTRUCTION_COS = %w[BWW J&MC MEIG].freeze
        SEED_RAILWAYS = %w[SFW BBNW ANW BAP].freeze

        def setup
          super
          deal_seed_certificates
          deal_corporate_seeds
          PREFLOATED.each { |id, price| prefloat(corporation_by_id(id), price) }
          mark_estancia
        end

        # Estancia Land Grant (4 players only) concerns J10: show its marker
        # there. Drawn only; with no blocks_hexes ability, track into J10 is
        # not blocked (its corporate purchase and closing are not built yet).
        def mark_estancia
          elg = company_by_id('ELG')
          hex_by_id('J10').tile.add_blocker!(elg) if elg
        end

        # Railways floated at Setup => their fixed starting price
        PREFLOATED = { 'BAGS' => 92, 'BAWR' => 76 }.freeze

        # 10% certificates kept back in a Railway's IPO, unbuyable: BAWR's
        # exchange certificates. (BAGS's three that come with BAGS_PRIVATES
        # wait in the bank pool, as 1871's do in its market.)
        HELD_OUT = { 'BAWR' => 3 }.freeze

        # Fixed price, held-out certificates reserved, the other unowned
        # 10% certificates to the bank pool, and 10x par from the bank.
        # The president's certificate stays put until the Concession
        # delivers it.
        def prefloat(railway, price)
          par = stock_market.par_prices.find { |p| p.price == price }
          stock_market.set_par(railway, par)
          railway.ipoed = true

          shares = railway.ipo_shares.reject(&:president)
          shares.pop(HELD_OUT.fetch(railway.id, 0)).each { |s| s.buyable = false }
          bundle = ShareBundle.new(shares)
          share_pool.transfer_shares(bundle, share_pool,
                                     allow_president_change: false)
          @log << "#{bundle.percent}% of #{railway.name} " \
                  'is placed in the bank pool'

          float_corporation(railway)
        end

        # One 20% seed in each Finance House to a random player;
        # with 4 players the one left over gets a 10% BAGS seed.
        def deal_seed_certificates
          players = @players.sort_by { rand }
          FINANCE_HOUSES.zip(players) do |id, player|
            give_seed(player, corporation_by_id(id))
          end
          give_seed(players[3], corporation_by_id('BAGS')) if players[3]
        end

        # Each Finance House gets 20% of a random Construction Company;
        # each Construction Company gets 10% of a random Railway.
        # The fourth Railway is left undealt.
        def deal_corporate_seeds
          deal_to_corporations(FINANCE_HOUSES, CONSTRUCTION_COS)
          deal_to_corporations(CONSTRUCTION_COS, SEED_RAILWAYS)
        end

        def deal_to_corporations(holder_ids, target_ids)
          targets = target_ids.sort_by { rand }
          holder_ids.zip(targets) do |holder, target|
            give_seed(corporation_by_id(holder), corporation_by_id(target))
          end
        end

        def give_seed(holder, corporation)
          share = corporation.ipo_shares.reject(&:president).first
          share_pool.buy_shares(holder, share, exchange: :free)
        end

        MUST_BID_INCREMENT_MULTIPLE = true

        # Memoized like 1871: Base#next_round! calls init_round again, which
        # must not deal the auction piles a second time.
        def init_round
          @init_round ||= Engine::Round::Auction.new(self, [G1887::Step::Auction])
        end

        # 1887 has no initial offering: unsold certificates sit in the
        # corporation's own treasury (wording only, as 1817 and 1846 do)
        def ipo_name(_entity = nil)
          'Treasury'
        end

        # Only BAWR holds certificates back: its exchange shares (as 1871
        # names its own)
        def ipo_reserved_name(_entity = nil)
          'Exchange'
        end

        # Corporate presidency (as 1841): the human at the top of a chain of
        # corporate presidents acts for every corporation in it. Uses the
        # engine's loop-safe Corporation#player; nil if nobody controls it.
        def controller(entity)
          entity&.corporation? ? entity.player : entity
        end

        def acting_for_entity(entity)
          return controller(entity) if entity&.corporation? && controller(entity)

          super
        end

        # Entities tab: group corporations under their controlling human
        def player_sort(entities)
          entities.sort_by { |e| [operating_order.index(e) || Float::INFINITY, e.name] }
            .group_by { |e| acting_for_entity(e) }
        end

        # Show share quantities as percentages on cards, the spreadsheet and
        # buy/sell buttons (opt-in read by the views): a share unit is 20%
        # for Finance Houses and Construction Companies but 10% for Railways
        def shares_as_percent?
          true
        end

        def init_share_pool
          G1887::SharePool.new(self, allow_president_sale: self.class::PRESIDENT_SALES_TO_MARKET)
        end

        def stock_round
          Engine::Round::Stock.new(self, [
            Engine::Step::DiscardTrain,
            Engine::Step::Exchange,
            Engine::Step::SpecialTrack,
            G1887::Step::BuySellParShares,
          ])
        end

        # As 1871: make sure privates and unsold companies (the auction
        # piles, which have no owner) show their values on the player card.
        def show_value_of_companies?(_owner)
          true
        end

        # Finance Houses and Construction Companies take a financial turn
        # instead of the railway steps
        def financial?(entity)
          return false unless entity&.corporation?

          (FINANCE_HOUSES + CONSTRUCTION_COS).include?(entity.id)
        end

        def finance_house?(entity)
          entity&.corporation? && FINANCE_HOUSES.include?(entity.id)
        end

        # 0 Finance House, 1 Construction Company, 2 Railway: a corporation
        # buys only from a higher tier number (11.3.3)
        def tier(corporation)
          return 0 if finance_house?(corporation)

          financial?(corporation) ? 1 : 2
        end

        # 11.3.3 Buy: one certificate at the target's market price, paid
        # from the buyer's treasury into the target's treasury (from its
        # Treasury) or to the bank (from the market). The target's price
        # does not move. Then the presidency check, swap included.
        def corporate_buy(buyer, share, price)
          target = share.corporation
          treasury = share.owner == target
          @log << "#{buyer.name} buys a #{share.percent}% share of #{target.name} " \
                  "from #{treasury ? 'the Treasury' : 'the market'} for #{format_currency(price)}"
          share_pool.transfer_shares(share.to_bundle, buyer, spender: buyer,
                                                             receiver: treasury ? target : @bank,
                                                             price: price,
                                                             allow_president_change: false)
          check_presidency(target)
        end

        # Not yet started: the president's certificate is in its treasury
        def startable_construction_companies
          CONSTRUCTION_COS.map { |id| corporation_by_id(id) }
            .select { |c| c.presidents_share.owner == c }
        end

        # Railways a Construction Company may start (10.5): the seed
        # Railways, and Entre Rios from phase 4 (the first 4-train)
        def startable_railways
          ids = SEED_RAILWAYS + (@phase.available?('4') ? %w[ER] : [])
          ids.map { |id| corporation_by_id(id) }.select { |c| c.presidents_share.owner == c }
        end

        # Started without the bank subsidy
        NO_SUBSIDY = %w[ER].freeze

        # 10.5 / 11.3.3: a Finance House starts a Construction Company, a
        # Construction Company starts a Railway. The whole amount goes into
        # the new company, which gets the bank subsidy (par x 1; not ER);
        # the starter takes the president's certificate. The price marker
        # waits beside the market until the next Operating Round (11.1), so
        # the new company cannot operate, or be traded, before then.
        def start_company(starter, company, amount)
          par = finance_house_par(amount)
          @log << "#{starter.name} starts #{company.name} with " \
                  "#{format_currency(amount)} (par #{format_currency(par.price)})"
          share_pool.buy_shares(starter, company.presidents_share, exchange: :free)
          starter.spend(amount, company)
          unless NO_SUBSIDY.include?(company.id)
            @bank.spend(par.price, company)
            @log << "bank pays #{company.name} subsidy #{format_currency(par.price)}"
          end
          company.par_price = par
          (@pending_markers ||= []) << company
          @log << "#{company.name}'s price marker waits beside the market " \
                  'until the next Operating Round'
        end

        # Pending markers go on the market at par, on the bottom of the stack
        def place_pending_markers
          (@pending_markers || []).each do |company|
            stock_market.set_par(company, company.par_price)
            @log << "#{company.name}'s price marker is placed at " \
                    "#{format_currency(company.par_price.price)}"
          end
          @pending_markers = []
        end

        def operating_round(round_num)
          place_pending_markers
          G1887::Round::Operating.new(self, [
            G1887::Step::FinancialTurn,
            G1887::Step::Bankrupt,
            G1887::Step::Exchange,
            G1887::Step::SpecialTrack,
            G1887::Step::BuyCompany,
            G1887::Step::Track,
            G1887::Step::Token,
            G1887::Step::Route,
            G1887::Step::Dividend,
            G1887::Step::DiscardTrain,
            G1887::Step::BuyTrain,
            [G1887::Step::BuyCompany, { blocks: true }],
          ], round_num: round_num)
        end

        # Market tab: the shared page shows this table below the grid (1846
        # uses it for price-movement rules). 1887 lists each cell holding
        # two or more corporations, top of the stack (operates first) to
        # bottom. With no shared cell only the headings show.
        def price_movement_chart
          cells = @stock_market.market.flatten.compact
            .select { |sp| sp.corporations.size > 1 }
            .sort_by { |sp| -sp.price }
          rows = cells.map do |sp|
            [format_currency(sp.price), sp.corporations.map(&:name).join(', ')]
          end
          [['Price', 'Stack, top to bottom'], *rows]
        end

        # First Stock Round: least cash first, seating order breaks ties
        def reorder_players(order = nil, **kwargs)
          order ||= :least_cash if @round.is_a?(Engine::Round::Auction)
          super(order, **kwargs)
        end

        # Charter private => the Finance House it floats
        CHARTERS = { 'BARC' => 'BB', 'HAMC' => 'HAM', 'MURC' => 'MUR' }.freeze

        # Concession private => the Railway whose president's cert it gives
        CONCESSIONS = { 'BAGSC' => 'BAGS', 'BAWRC' => 'BAWR' }.freeze

        def after_buy_company(player, company, price)
          if (rail_id = CONCESSIONS[company.id])
            return give_presidency(player, corporation_by_id(rail_id))
          end

          bags = BAGS_PRIVATES.include?(company.id)
          return give_pool_share(player, corporation_by_id('BAGS')) if bags

          return super unless (fh_id = CHARTERS[company.id])

          float_finance_house(player, company, corporation_by_id(fh_id), price)
        end

        # Privates that each come with one 10% BAGS certificate from the
        # bank pool (free; the price does not move)
        BAGS_PRIVATES = %w[BRC PLC RSL].freeze

        # Both hand-overs skip the engine's own president check, which
        # crashes while the president's certificate is unsold, and run
        # check_presidency instead.
        def give_pool_share(player, railway)
          share = share_pool.shares_of(railway).first
          share_pool.buy_shares(player, share, exchange: :free,
                                               allow_president_change: false)
          check_presidency(railway)
        end

        def give_presidency(player, railway)
          share_pool.buy_shares(player, railway.presidents_share,
                                exchange: :free,
                                allow_president_change: false)
          railway.owner = player
          @log << "#{player.name} becomes the president of #{railway.name}"
          check_presidency(railway)
        end

        # Rulebook 10.3: a holder (player or corporation) holding strictly
        # more than the president takes over, swapping ordinary certificates
        # of equal value for the president's certificate. Does nothing until
        # the president's certificate has been delivered. Ties keep the
        # president; between tied challengers players come before
        # corporations (as 1841), players nearest clockwise from the
        # president first.
        def check_presidency(railway)
          pres = railway.owner
          return unless pres

          held = ->(h) { h.percent_of(railway) }
          players = pres.player? ? @players.rotate(@players.index(pres)) : @players
          corps = @corporations.reject { |c| c.closed? || c == railway }
          top = [pres, *players, *corps].max_by(&held)
          return unless held[top] > held[pres]

          share_pool.change_president(railway.presidents_share, pres, top)
          railway.owner = top
          @log << "#{top.name} becomes the president of #{railway.name}"
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
