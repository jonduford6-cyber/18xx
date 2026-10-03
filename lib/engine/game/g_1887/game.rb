# frozen_string_literal: true

require_relative 'entities'
require_relative 'map'
require_relative 'meta'
require_relative 'corporation'
require_relative 'lombard'
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

        # Lombard Street (a minor that holds shares) appears among the
        # holders on every company card
        MINORS_CAN_OWN_SHARES = true

        # The bank never runs out (section 12): it can always pay, and the
        # game never ends because of it
        BANK_CASH = :unlimited

        # In an emergency a Railway may buy another Railway's train; the
        # president's contribution is not capped at face value
        EBUY_FROM_OTHERS = :always

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

        # Section 12: bankruptcy and a price reaching 516 end the game at
        # once. The first Diesel finishes the Operating Round set in
        # progress, then one final Stock Round and one final Operating Round
        # set (announce_final_rounds; the Confidence Track can add its own
        # reason with the same timing).
        # The Confidence Track reaching its last space (sections 12, 12.2):
        # the rest of that Stock Round, then one Operating Round set, then
        # the end (the engine's full_or). Only the first of the Diesel and
        # the track counts (first_ending); 516 and bankruptcy always end the
        # game at once.
        GAME_END_CHECK = {
          bankrupt: :immediate,
          stock_market: :immediate,
          diesel: :one_more_full_or_set,
          confidence: :full_or,
        }.freeze

        EVENTS_TEXT = Base::EVENTS_TEXT.merge(
          'close_privates' => ['Privates close',
                               'Baring & Robertson Credit, Petro & Ladd Construction Contract, ' \
                               'Robert Stephenson & Co. Locomotive Order, Henderson Transfer, La Porteña Works, ' \
                               'Anderson Paz Purchase Agreement, La Boca Docks Lease and Estancia Land Grant close ' \
                               '(Estancia pays its owner $50); Parana Ferry Company stays open but pays no income'],
          'diesel_bought' => ['Game end',
                              'The first Diesel ends the game after this Operating Round set, ' \
                              'one final Stock Round and one final Operating Round set'],
        ).freeze

        GAME_END_REASONS_TEXT = Base::GAME_END_REASONS_TEXT.merge(
          diesel: 'The first Diesel train is bought',
          confidence: 'The Confidence Track reaches its final space',
        ).freeze

        GAME_END_DESCRIPTION_REASON_MAP_TEXT = Base::GAME_END_DESCRIPTION_REASON_MAP_TEXT.merge(
          diesel: 'The first Diesel was bought',
          confidence: 'The Confidence Track reached its final space',
        ).freeze

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
          { name: '5', distance: 5, price: 400, rusts_on: 'D', num: 3, events: [{ 'type' => 'close_privates' }] },
          { name: '6', distance: 6, price: 500, num: 3 },
          { name: 'D', distance: 999, price: 700, num: 'unlimited', events: [{ 'type' => 'diesel_bought' }] },
        ].freeze

        # Section 14: a Concession closes at the start of its Railway's first
        # operating turn, after paying at the start of the round. (In 1887
        # home tokens are placed exactly then, at the start of each turn.)
        def place_home_token(corporation)
          super
          return unless (id = CONCESSIONS.key(corporation.id))

          concession = company_by_id(id)
          return if !concession || concession.closed?

          concession.close!
          @log << "#{concession.name} closes"
        end

        # Section 14, start of phase 5 (the first 5-train)
        PHASE_5_CLOSINGS = %w[BRC PLC RSL HT LPW APPA LBDL ELG].freeze
        ESTANCIA_BONUS = 50

        def event_close_privates!
          closing = PHASE_5_CLOSINGS.map { |id| company_by_id(id) }.compact.reject(&:closed?)
          @log << "-- The first 5-train was bought: #{closing.map(&:name).join(', ')} close --" unless closing.empty?
          closing.each do |company|
            owner = company.owner
            company.close!
            next if company.id != 'ELG' || !owner

            @bank.spend(ESTANCIA_BONUS, owner)
            @log << "#{owner.name} receives #{format_currency(ESTANCIA_BONUS)} from the bank as Estancia Land Grant closes"
          end
          ferry = company_by_id('PFC')
          return if !ferry || ferry.closed? || ferry.revenue.zero?

          ferry.revenue = 0
          @log << "#{ferry.name} stays open but pays no income from now on"
        end

        def event_diesel_bought!
          return if @diesel_bought

          @diesel_bought = true
          if @first_ending
            @log << 'The first Diesel was bought; the game already ends as the Confidence Track set (no change)'
            return
          end

          @first_ending = :diesel
          announce_final_rounds('The first Diesel was bought')
        end

        def announce_final_rounds(what)
          @log << "-- #{what}: the game ends after this Operating Round set, " \
                  'one final Stock Round and one final Operating Round set --'
        end

        def game_end_check_diesel?
          @first_ending == :diesel
        end

        def game_end_check_confidence?
          @first_ending == :confidence
        end

        # The final Stock Round and Operating Round set are marked as final
        def round_description(name, round_number = nil)
          return super if @finished

          if @final_turn && @turn == @final_turn
            "#{super} (final#{name == 'Stock' ? '' : ' set'})"
          elsif @first_ending == :confidence && @turn == @confidence_turn && name != 'Stock'
            "#{super} (final set)"
          else
            super
          end
        end

        # Section 12.2: the Confidence Track, 7 spaces, starting on space 1.
        # Each Lombard Street purchase (or start) moves it one space; shown
        # on Lombard Street's card and in the log.
        CONFIDENCE_SPACES = 7

        def confidence
          @confidence || 1
        end

        def advance_confidence!
          return if confidence >= CONFIDENCE_SPACES

          @confidence = confidence + 1
          @log << "The Confidence Track advances to space #{confidence} of #{CONFIDENCE_SPACES}"
          show_confidence
          return if confidence < CONFIDENCE_SPACES

          if @first_ending
            @log << 'The Confidence Track reached its final space; the game already ends as the first Diesel set ' \
                    '(no change)'
            return
          end

          @first_ending = :confidence
          @confidence_turn = @turn
          @log << '-- The Confidence Track reached its final space: the rest of this Stock Round is played, then ' \
                  'one final Operating Round set, then the game ends --'
          show_confidence
        end

        # Baring & Robertson Credit, once per game, in its owner's Stock Round
        # turn: the track back one space (only above space 1, never from 7)
        def confidence_pull_back_allowed?(player)
          brc = company_by_id('BRC')
          brc && !brc.closed? && brc.owner == player && !@confidence_pulled &&
            confidence > 1 && confidence < CONFIDENCE_SPACES
        end

        def pull_back_confidence!(player)
          @confidence_pulled = true
          @confidence = confidence - 1
          @log << "#{player.name} uses Baring & Robertson Credit: the Confidence Track goes back to space " \
                  "#{confidence} of #{CONFIDENCE_SPACES}"
          show_confidence
        end

        def show_confidence
          text = "Confidence Track: space #{confidence} of #{CONFIDENCE_SPACES}"
          text += ' (the game ends after the next Operating Round set)' if @first_ending == :confidence
          @confidence_ability ||= Engine::Ability::Description.new(type: 'description', description: text)
          @confidence_ability.description = text
          lombard.add_ability(@confidence_ability) unless lombard.all_abilities.include?(@confidence_ability)
        end

        # 50% of a company's certificates at most in the bank pool, for every
        # sale, Issue and Reissue; no limit with the optional rule
        def market_share_limit(corporation = nil)
          optional_rules.include?(:no_bank_pool_limit) ? 100 : super
        end

        # 11.3.5 / 11.3.1: one ordinary certificate a company may move from
        # its own treasury to the bank pool (never the president's, never a
        # held-back one), if the pool limit allows
        def issuable_share(corporation)
          return unless corporation.share_price

          share = corporation.shares_of(corporation).find { |s| s.buyable && !s.president }
          share if share && share_pool.fit_in_bank?(share.to_bundle)
        end

        # One of its own certificates a company may buy back from the bank
        # pool at the market price (BAGS and BAWR never redeem)
        def redeemable_share(corporation)
          return if PREFLOATED.key?(corporation.id) || !corporation.share_price

          share = share_pool.shares_of(corporation).find { |s| !s.president }
          share if share && corporation.cash >= corporation.share_price.price * share.num_shares
        end

        # Issue / Reissue: certificates from the company's treasury to the
        # bank pool, all at the current market price; then down one row per
        # certificate
        def issue_shares(corporation, shares, verb: 'issues')
          bundle = ShareBundle.new(shares)
          bundle.share_price = corporation.share_price.price
          share_pool.sell_shares(bundle, allow_president_change: false, silent: true)
          @log << "#{corporation.name} #{verb} #{share_pool.num_presentation(bundle)} of #{corporation.name} " \
                  "and receives #{format_currency(bundle.price)}"
          shares.size.times { price_down(corporation) }
        end

        def redeem_share(corporation, share)
          bundle = share.to_bundle
          bundle.share_price = corporation.share_price.price
          share_pool.buy_shares(corporation, bundle, allow_president_change: false, silent: true)
          @log << "#{corporation.name} redeems a #{bundle.percent}% share from the market for " \
                  "#{format_currency(bundle.price)}"
        end

        # Game over by bankruptcy: say who (the page header, Info tab)
        def game_ending_description
          bankrupt = @players.find(&:bankrupt)
          return super unless bankrupt

          "#{bankrupt.name} is bankrupt"
        end

        # A penalty: one space left (down a row at the left edge), as the
        # pass penalty
        def price_left(corporation)
          old = corporation.share_price
          @stock_market.move_left(corporation)
          log_share_price(corporation, old)
          recheck_operating_order
        end

        # A stock event: down one row (stays at the bottom row)
        def price_down(corporation)
          return unless (old = corporation.share_price)

          @stock_market.move_down(corporation)
          log_share_price(corporation, old)
          recheck_operating_order
        end

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
          seed_lombard
        end

        # Company cards show holdings for Lombard Street too (a minor), not
        # only for corporations
        def corporation_show_shares?(_corporation)
          true
        end

        def init_minors
          [G1887::Minor.new(sym: 'Lombard', name: 'Lombard Street', tokens: [],
                            color: '#1f3a5f', text_color: '#ffffff')]
        end

        def lombard
          @minors.first
        end

        # Section 3: Lombard Street starts with a 10% BAWR certificate from
        # the bank pool and the 10% certificate of the seed Railway not dealt
        # to a Construction Company
        def seed_lombard
          bawr = corporation_by_id('BAWR')
          share_pool.buy_shares(lombard, share_pool.shares_of(bawr).find { |s| !s.president },
                                exchange: :free, allow_president_change: false)
          fourth = SEED_RAILWAYS.map { |id| corporation_by_id(id) }
                     .find { |r| r.share_holders.keys.all? { |h| h == r } }
          give_seed(lombard, fourth) if fourth
          show_confidence
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

        # Entities tab: each player's column lists the corporations that
        # player controls in tree order, every corporation right after its
        # president (Finance House, its Construction Companies, their
        # Railways). The player's own Railways come first (BAGS, BAWR, then
        # by name); other siblings in operating order, then name. A
        # corporation caught in an unexpected loop of presidents goes last
        # in the first player's column, so no card is ever hidden.
        RAILWAY_ORDER = %w[BAGS BAWR].freeze

        def player_sort(entities)
          rank = ->(e) { [operating_order.index(e) || Float::INFINITY, e.name] }
          rail_first = lambda do |e|
            next [1, 0, 0, e.name] if e.minor? # Lombard Street, after the player's own Railways
            next [2, *rank.call(e)] unless tier(e) == 2

            [0, RAILWAY_ORDER.index(e.id) || RAILWAY_ORDER.size, 0, e.name]
          end
          children = entities.group_by(&:owner)
          placed = {}
          walk = lambda do |parent|
            (children[parent] || []).sort_by(&(parent.player? ? rail_first : rank)).flat_map do |c|
              next [] if placed[c]

              placed[c] = true
              [c, *walk.call(c)]
            end
          end
          ordered = @players.flat_map { |p| walk.call(p) }
          ordered.concat(entities.reject { |e| placed[e] }.sort_by(&rank))
          ordered.group_by { |e| (e.minor? ? e.owner : controller(e)) || @players.first }
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

        # 11.7 chain. A corporation receiving money from a company it
        # presides over moves one space right, then chooses to pay on or
        # withhold (a waiting list in the round, one corporation at a time).
        # Under $1 per share (amount div shares) it must withhold: the price
        # moves back left, so the net move is zero.
        def chain_receive(corp, amount, payer)
          chain_move(corp, :right)
          if amount.div(corp.total_shares) < 1
            @log << "#{corp.name} must withhold #{format_currency(amount)}: less than " \
                    "#{format_currency(1)} per share for its #{corp.total_shares} shares"
            chain_move(corp, :left)
          else
            @round.chain_pending << { corporation: corp, amount: amount, from: payer }
          end
        end

        # Pay on: whole dollars per share to the corporation's holders, from
        # its treasury. Its own Treasury certificates pay itself, the bank
        # pool's go to the bank, the remainder stays. Price one more space
        # right. A presiding corporation above then receives in turn.
        def chain_pay_on(corp, amount)
          per_share = amount.div(corp.total_shares)
          fmt = ->(v) { format_currency(v) }
          paid = {}
          (@players + @corporations + @minors).each do |holder|
            next if (pay = holder.num_shares_of(corp) * per_share).zero?

            corp.spend(pay, holder) unless holder == corp
            paid[holder] = pay
          end
          receivers = paid.sort_by { |_h, v| -v }.map { |h, v| "#{fmt[v]} to #{h.name}" }.join(', ')
          @log << "#{corp.name} pays out #{fmt[amount]}: #{fmt[per_share]} per share" \
                  "#{receivers.empty? ? '' : " (#{receivers})"}"
          if (pool = @share_pool.num_shares_of(corp) * per_share).positive?
            corp.spend(pool, @bank)
            @log << "#{fmt[pool]} for the bank pool's #{@share_pool.percent_of(corp)}% goes to the bank"
          end
          remainder = amount - (per_share * corp.total_shares)
          @log << "#{corp.name} keeps the #{fmt[remainder]} remainder" if remainder.positive?
          chain_move(corp, :right)
          parent = corp.owner
          chain_receive(parent, paid[parent], corp) if parent&.corporation? && paid[parent]
        end

        def chain_withhold(corp, amount)
          @log << "#{corp.name} withholds #{format_currency(amount)} (its price stays)"
        end

        def chain_move(corp, direction)
          return unless (old = corp.share_price)

          direction == :right ? @stock_market.move_right(corp) : @stock_market.move_left(corp)
          log_share_price(corp, old)
          recheck_operating_order
        end

        # 11.1: corporations operate in descending price order (ties by the
        # stack in the cell), rechecked after every mid-round price change
        # for those that have not operated yet. Call it after any price move
        # during an Operating Round.
        def recheck_operating_order
          @round.recalculate_order if @round.is_a?(Engine::Round::Operating)
        end

        # Section 3: Lombard Street starts a company like a player: par x 2
        # into the company (Lombard pays what it has, its owner the rest),
        # the bank subsidy as for any start (not ER), the marker waits for
        # the next Operating Round; Lombard is the president
        def lombard_start(company, share_price)
          amount = share_price.price * 2
          from_lombard = [lombard.cash, amount].min
          from_owner = amount - from_lombard
          owner = lombard.owner
          start_company(lombard, company, amount, payers: [[lombard, from_lombard], [owner, from_owner]])
          company.owner = lombard # the engine names only players and corporations president
          @log << "#{lombard.full_name} pays #{format_currency(from_lombard)} and #{owner.name} pays " \
                  "#{format_currency(from_owner)}; #{lombard.full_name} is the president of #{company.name}"
          check_presidency(company)
        end

        # Unstarted Construction Companies and startable Railways (never BAGS
        # or BAWR; Entre Rios from phase 4)
        def lombard_startable_companies
          startable_construction_companies + startable_railways
        end

        def can_par?(corporation, entity)
          return true if player_startable(entity).include?(corporation)

          lombard&.owner == entity && lombard_startable_companies.include?(corporation)
        end

        # The final Stock Round (after the Diesel)
        def final_stock_round?
          return false unless @round.is_a?(Engine::Round::Stock)

          (@final_turn && @turn == @final_turn) || (@first_ending == :confidence && @turn == @confidence_turn)
        end

        # One space lower on the market (left, or down a row at the edge)
        def lower_price(corporation)
          sp = corporation.share_price
          @stock_market.share_price(@stock_market.left(corporation, sp.coordinates)).price
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

        # 3.3 / 13.3: companies a player may start in a Stock Round as their
        # buy (Entre Rios from phase 4, while unstarted); the mechanism is
        # meant to be reused for restarting a retired Railway
        PLAYER_STARTABLE = %w[ER].freeze
        FOUNDING_FLOAT_POOL = 40 # floats when 60% has been sold
        FOUNDING_CAPITAL = 10 # the bank pays 10 x par at the float

        def player_startable(player)
          return [] if !player.player? || !@phase.available?('4')

          min = stock_market.par_prices.map(&:price).min
          PLAYER_STARTABLE.map { |id| corporation_by_id(id) }.select do |c|
            c.presidents_share.owner == c && player.cash >= min * 2 && control_ok?(player, c, c.presidents_share.percent)
          end
        end

        # The player pays par x 2 to the bank for the president's
        # certificate; the other certificates go to the bank pool, sold at
        # par until the company floats; no market price until then
        def player_start(player, company, share_price)
          price = share_price.price * 2
          company.founding = true
          company.par_price = share_price
          company.share_price = share_price # the founding price; the marker is not on the market
          company.ipoed = true
          @log << "#{player.name} starts #{company.name} at par #{format_currency(share_price.price)}, paying " \
                  "#{format_currency(price)} to the bank for the #{company.presidents_share.percent}% president's certificate"
          share_pool.buy_shares(player, company.presidents_share, exchange: :free, allow_president_change: false, silent: true)
          player.spend(price, @bank)
          company.owner = player
          rest = company.shares_of(company).reject(&:president)
          share_pool.transfer_shares(ShareBundle.new(rest), share_pool, allow_president_change: false)
          @log << "#{ShareBundle.new(rest).percent}% of #{company.name} is placed in the bank pool, at " \
                  "#{format_currency(share_price.price)} each until it floats"
        end

        # The float at 60% sold: 10 x par from the bank, the home station, the
        # marker at the start of the next Operating Round
        def founding_float_check(company)
          return if !company.founding || share_pool.percent_of(company) > FOUNDING_FLOAT_POOL

          company.founding = false
          capital = company.par_price.price * FOUNDING_CAPITAL
          @bank.spend(capital, company)
          @log << "#{company.name} floats (60% sold); the bank pays #{format_currency(capital)} into its treasury"
          place_home_token(company)
          (@pending_markers ||= []) << company
          @log << "#{company.name}'s price marker waits beside the market until the next Operating Round"
        end

        # 10.5 / 11.3.3: a Finance House starts a Construction Company, a
        # Construction Company starts a Railway. The whole amount goes into
        # the new company, which gets the bank subsidy (par x 1; not ER);
        # the starter takes the president's certificate. The price marker
        # waits beside the market until the next Operating Round (11.1), so
        # the new company cannot operate, or be traded, before then.
        def start_company(starter, company, amount, payers: [[starter, amount]])
          par = finance_house_par(amount)
          @log << "#{starter.name} starts #{company.name} with " \
                  "#{format_currency(amount)} (par #{format_currency(par.price)})"
          share_pool.buy_shares(starter, company.presidents_share, exchange: :free)
          payers.each { |payer, pay| payer.spend(pay, company) if pay.positive? }
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
            G1887::Step::IssueRedeem,
            G1887::Step::Track,
            G1887::Step::Token,
            G1887::Step::Route,
            G1887::Step::Dividend,
            G1887::Step::ChainDividend,
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

          return take_lombard(player, company) if company.id == 'LS'

          bags = BAGS_PRIVATES.include?(company.id)
          return give_pool_share(player, corporation_by_id('BAGS')) if bags

          return super unless (fh_id = CHARTERS[company.id])

          float_finance_house(player, company, corporation_by_id(fh_id), price)
        end

        # The Lombard Street private closes on purchase; its buyer becomes
        # Lombard Street's owner and acts for it
        def take_lombard(player, company)
          company.close!
          lombard.owner = player
          @log << "#{company.name} closes; #{player.name} becomes the owner of #{lombard.full_name}"
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

          top = president_after(railway)
          return if top == pres

          share_pool.change_president(railway.presidents_share, pres, top)
          railway.owner = top
          @log << "#{top.name} becomes the president of #{railway.name}"
        end

        # Who would be the president of the company if each holder's
        # percentage changed by `changes` ({holder => percent}). The
        # company's own treasury and the bank pool are never candidates.
        def president_after(corporation, changes = {})
          pres = corporation.owner
          return pres unless pres

          held = ->(h) { h.percent_of(corporation) + changes.fetch(h, 0) }
          players = pres.player? ? @players.rotate(@players.index(pres)) : @players
          corps = @corporations.reject { |c| c.closed? || c == corporation }
          top = [pres, *players, *@minors, *corps].max_by(&held) # Lombard Street counts like a player
          held[top] > held[pres] ? top : pres
        end

        # 10.2, 11.3: the bundles a player or corporation may sell, per
        # company: 1, 2, ... of its ordinary certificates (never a
        # president's or held-back one), only with a market price, within
        # the pool limit. Each bundle is a list of certificates.
        def legal_bundles(seller)
          seller.shares.group_by(&:corporation).flat_map do |corporation, shares|
            next [] if corporation == seller || !corporation.share_price || corporation.founding

            ordinary = shares.select { |sh| sh.buyable && !sh.president }.sort_by(&:id)
            (1..ordinary.size).map { |n| ordinary.first(n) }
                              .select { |some| share_pool.fit_in_bank?(ShareBundle.new(some)) }
          end
        end

        # Sells certificates of one company together to the bank pool at the
        # current price per certificate; a presidency swap once, after the
        # whole bundle; then the price drops one row per certificate
        def sell_bundle(shares)
          corporation = shares.first.corporation
          bundle = ShareBundle.new(shares)
          bundle.share_price = corporation.share_price.price
          share_pool.sell_shares(bundle, allow_president_change: false)
          check_presidency(corporation)
          shares.size.times { price_down(corporation) }
        end

        # 10.6: control. A player's control of a company counts the
        # certificates the player holds in it and those held by every
        # corporation down the player's chain of presidencies. Lombard Street
        # is its own actor: its holdings (and its chain's) do not count for
        # its owner, and its control is capped like a player's.
        CONTROL_LIMIT = 60

        # The actor whose control a holder's purchase counts toward: a
        # player or Lombard Street; for a corporation, the actor at the top
        # of its chain
        def control_actor(entity)
          entity = entity.owner while entity&.corporation?
          entity if entity&.player? || entity&.minor?
        end

        # The actor and every corporation down its chain
        def control_holders(actor)
          holders = [actor]
          loop do
            more = @corporations.select { |c| !c.closed? && holders.include?(c.owner) && !holders.include?(c) }
            break if more.empty?

            holders.concat(more)
          end
          holders
        end

        def control_percent(actor, corporation)
          control_holders(actor).sum { |h| h == corporation ? 0 : h.percent_of(corporation) }
        end

        # A purchase or start of `percent` of a company by `buyer` keeps its
        # actor's control at 60% or less
        def control_ok?(buyer, corporation, percent)
          actor = control_actor(buyer)
          return true unless actor

          control_percent(actor, corporation) + percent <= CONTROL_LIMIT
        end

        # 10.6 waivers: no forced sale of a company that has not yet completed
        # an Operating Round turn, or that would put more than 50% of it in
        # the bank pool (the bundle offered is then left out)
        def control_sale_waived?(corporation)
          !completed_operating_turn?(corporation)
        end

        # Railways, Finance Houses and Construction Companies alike
        def completed_operating_turn?(corporation)
          (@completed_operating_turns ||= []).include?(corporation)
        end

        def after_end_of_operating_turn(operator)
          super
          (@completed_operating_turns ||= []) << operator if operator.corporation? && !completed_operating_turn?(operator)
        end

        # The bundle a holder must sell of a company because its actor's
        # control is over 60%: the smallest legal bundle that brings control
        # to 60% or less, or all it may sell; nil if none is due or waived
        def forced_control_sale(holder, corporation)
          actor = control_actor(holder)
          return if !actor || holder.minor? # Lombard Street never sells

          excess = control_percent(actor, corporation) - CONTROL_LIMIT
          return if !excess.positive? || control_sale_waived?(corporation)

          ordinary = holder.shares_of(corporation).select { |sh| sh.buyable && !sh.president }.sort_by(&:id)
          return if ordinary.empty?

          needed = (1..ordinary.size).map { |n| ordinary.first(n) }.find { |some| some.sum(&:percent) >= excess } || ordinary
          # the second waiver: not while it would put more than 50% in the pool
          needed if legal_bundles(holder).include?(needed)
        end

        # A corporation's forced sales at its financial turn
        def forced_corporation_sales(corporation)
          corporation.shares.map(&:corporation).uniq.filter_map { |c| forced_control_sale(corporation, c) }
        end

        # A player's forced sales at the start of a Stock Round turn: only
        # when no corporation in the player's chain still holds that company
        # (corporations sell first, at their financial turns)
        def forced_player_sales(player)
          player.shares.map(&:corporation).uniq.filter_map do |c|
            next if control_holders(player).any? { |h| h.corporation? && h != c && h.percent_of(c).positive? }

            forced_control_sale(player, c)
          end
        end

        # Stock Round sales follow 1887's own rules: the presidency by 1887's
        # rule (corporations and Lombard Street count), one row down per
        # certificate, each move rechecking the order
        def sell_shares_and_change_price(bundle, allow_president_change: true, swap: nil, movement: nil)
          return super if swap || movement

          sell_bundle(bundle.shares)
        end

        # The bundle of `count` certificates of a company that a button
        # "sell:<company>:<count>" stands for
        def bundle_for(seller, corporation_id, count)
          corporation = corporation_by_id(corporation_id)
          legal_bundles(seller).find { |some| some.first.corporation == corporation && some.size == count.to_i }
        end

        # 11.9: the Bankruptcy button (standard screen) appears only when the
        # player at the top of an emergency cannot cover it (1887's Buy
        # Trains step decides)
        def can_go_bankrupt?(player, corporation)
          step = @round.steps.find { |s| s.is_a?(G1887::Step::BuyTrain) }
          step&.active? ? step.player_cannot_cover?(player, corporation) : false
        end

        # The standard emergency Issue panel's bundles (1887's Buy Trains
        # step decides)
        def emergency_issuable_bundles(corporation)
          step = @round.steps.find { |s| s.is_a?(G1887::Step::BuyTrain) }
          step&.active? ? step.issuable_shares(corporation) : []
        end

        # 11.3.1: up to how many certificates a company may reissue from its
        # own treasury at once (pool limit; no change of presidency)
        def reissuable_shares(corporation)
          return [] unless corporation.share_price

          shares = corporation.shares_of(corporation).select { |sh| sh.buyable && !sh.president }
          shares.size.downto(1).each do |n|
            some = shares.first(n)
            percent = some.sum(&:percent)
            next unless share_pool.percent_of(corporation) + percent <= market_share_limit(corporation)
            next unless president_after(corporation, corporation => -percent) == corporation.owner

            return some
          end
          []
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
