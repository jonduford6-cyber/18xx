# frozen_string_literal: true

require_relative 'entities'
require_relative 'map'
require_relative 'meta'
require_relative 'corporation'
require_relative 'lombard'
require_relative 'share_pool'
require_relative 'round/operating'
require_relative 'round/merger'
require_relative 'merge'
require_relative '../base'

module Engine
  module Game
    module G1887
      class Game < Game::Base
        include G1887::Merge
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

        # 5.3 / 5.4: selling is allowed in every Stock Round, the first one
        # included; a turn is sell, buy one certificate, then sell again
        SELL_AFTER = :any_time
        SELL_BUY_ORDER = :sell_buy_sell

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
                               '(Estancia pays its owner $50); Paraná Ferry Company stays open but pays no income'],
          'kilometric_clawback' => ['Kilometric Guarantee closes',
                                    'A Railway owning it pays the bank $15 per station token'],
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

        # The phase table on the Info tab: the same status as before, with
        # 1887's own wording (display only)
        STATUS_TEXT = Base::STATUS_TEXT.merge(
          'can_buy_companies' =>
            ['Railways may buy private companies',
             'From phase 3 a Railway may buy a private company from the player at the top of its chain. ' \
             'Most private companies close at phase 5. The Paraná Ferry Company stays open and can still be bought.'],
        ).freeze

        # The Info tab prints the buying status on phases 3 and 4 only; the
        # phase data itself (read by the engine) keeps it on from phase 3 on,
        # because the Paraná Ferry Company can still be bought later
        INFO_STATUS_PHASES = %w[3 4].freeze

        def info_phase_status(phase)
          INFO_STATUS_PHASES.include?(phase[:name]) ? phase[:status] : nil
        end

        # A train discarded over the limit is removed from the game (as in 1871)
        DISCARDED_TRAINS = :remove

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
            status: ['can_buy_companies'],
            train_limit: 4,
            tiles: %i[yellow green],
            operating_rounds: 2,
          },
          {
            name: '4',
            on: '4',
            status: ['can_buy_companies'],
            train_limit: 3,
            tiles: %i[yellow green],
            operating_rounds: 2,
          },
          {
            name: '5',
            on: '5',
            status: ['can_buy_companies'],
            train_limit: 3,
            tiles: %i[yellow green brown],
            operating_rounds: 3,
          },
          {
            name: '6',
            on: '6',
            status: ['can_buy_companies'],
            train_limit: 2,
            tiles: %i[yellow green brown],
            operating_rounds: 3,
          },
          {
            name: 'D',
            on: 'D',
            status: ['can_buy_companies'],
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
          { name: '6', distance: 6, price: 500, num: 3, events: [{ 'type' => 'kilometric_clawback' }] },
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

        # 14: from phase 3 a Railway's president may sell the Railway one of
        # these privates, at half to double face value, from their own hand
        CORPORATE_PURCHASABLE = %w[PLC RSL KG LBDL PFC ELG].freeze

        # The privates the current (or given) Railway may buy: those owned by
        # the player who acts for it, the player at the top of its chain of
        # presidents (for a chain ending at Lombard Street, its owner).
        def purchasable_companies(entity = nil)
          entity ||= @round&.current_entity
          return [] if !entity&.corporation? || financial?(entity)
          return [] unless (player = purchasing_player(entity))

          player.companies.select { |c| CORPORATE_PURCHASABLE.include?(c.id) && !c.closed? }
        end

        def purchasing_player(entity)
          top = control_actor(entity)
          top = top.owner if top&.minor? # Lombard Street: its owner
          top if top&.player?
        end

        # 14, Robert Stephenson & Co. Locomotive Order: its owner (a player
        # or a Railway) receives 10% of the price of the first train bought
        # from the depot in each Operating Round set. It closes with the
        # first 5-train before paying for it.
        def stephenson_pays!(buyer, train, price)
          rsl = company_by_id('RSL')
          return if !rsl || rsl.closed? || !rsl.owner || @stephenson_paid_turn == @turn

          @stephenson_paid_turn = @turn
          amount = price / 10
          @bank.spend(amount, rsl.owner)
          @log << "#{rsl.owner.name} receives #{format_currency(amount)} from #{rsl.name} " \
                  "(10% of #{buyer.name}'s #{train.name}-train)"
        end

        # 14, Kilometric Guarantee: nothing while a player owns it. A Railway
        # owning it receives, at the start of each Operating Round, $15 per
        # station token it has on the map ($7 from phase 5). At phase 6 the
        # Railway pays the bank $15 per token (all its cash if short) and the
        # private closes.
        KILOMETRIC = 15
        KILOMETRIC_LATE = 7

        def placed_tokens(corporation)
          corporation.tokens.count { |t| t.used && t.city }
        end

        def payout_companies(ignore: [])
          super
          kg = company_by_id('KG')
          railway = kg&.owner
          return if !railway&.corporation? || kg.closed?

          tokens = placed_tokens(railway)
          per = %w[5 6 D].include?(@phase.name) ? KILOMETRIC_LATE : KILOMETRIC
          return if tokens.zero?

          @bank.spend(per * tokens, railway)
          @log << "#{railway.name} receives #{format_currency(per * tokens)} from #{kg.name} " \
                  "(#{tokens} station token#{tokens == 1 ? '' : 's'} x #{format_currency(per)})"
        end

        def event_kilometric_clawback!
          kg = company_by_id('KG')
          return if !kg || kg.closed?

          railway = kg.owner
          if railway&.corporation?
            tokens = placed_tokens(railway)
            due = KILOMETRIC * tokens
            paid = [due, railway.cash].min
            railway.spend(paid, @bank) if paid.positive?
            short = paid < due ? ", all its cash; #{format_currency(due)} due" : ''
            @log << "#{railway.name} pays the bank #{format_currency(paid)} for #{kg.name} " \
                    "(#{tokens} station token#{tokens == 1 ? '' : 's'} x #{format_currency(KILOMETRIC)}#{short})"
          end
          kg.close!
          @log << "#{kg.name} closes"
        end

        # Section 14, start of phase 5 (the first 5-train)
        PHASE_5_CLOSINGS = %w[BRC PLC RSL HT LPW APPA LBDL ELG].freeze
        ESTANCIA_BONUS = 50

        # 10.4: Henderson Transfer, La Porteña Works and Anderson Paz Purchase
        # Agreement each exchange, in a Stock Round, for one of BAWR's three
        # held-back 10% certificates, at no cost; the private closes
        EXCHANGE_PRIVATES = %w[HT LPW APPA].freeze

        def exchange_privates(player)
          player.companies.select { |c| EXCHANGE_PRIVATES.include?(c.id) && !c.closed? }
        end

        def held_back_bawr
          bawr = corporation_by_id('BAWR')
          bawr.shares_of(bawr).reject { |s| s.buyable || s.president }
        end

        def exchange_bawr!(company, forced: false)
          owner = company.owner
          share = held_back_bawr.first
          return company.close! if !share || !owner&.player?

          bawr = share.corporation
          share.buyable = true
          share_pool.transfer_shares(share.to_bundle, owner, allow_president_change: false)
          company.close!
          @log << if forced
                    "#{company.name} closes; #{owner.name} receives a 10% #{bawr.name} certificate (forced exchange)"
                  else
                    "#{owner.name} exchanges #{company.name} for a 10% #{bawr.name} certificate; #{company.name} closes"
                  end
          check_presidency(bawr)
        end

        def event_close_privates!
          # 10.4 / 14: unused exchange privates deliver their certificate first
          EXCHANGE_PRIVATES.map { |id| company_by_id(id) }.compact.reject(&:closed?).each do |company|
            exchange_bawr!(company, forced: true) if company.owner&.player?
          end
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

        # Optional rules: only two 6-trains; four 4-trains
        def num_trains(train)
          return 2 if train[:name] == '6' && optional_rules.include?(:two_six_trains)
          return 4 if train[:name] == '4' && optional_rules.include?(:four_four_trains)

          super
        end

        # Optional rule: permanent 5-trains. The 5-train rusts nothing and is
        # never rusted; the 6-train rusts the 3-trains; the Diesel rusts the
        # 4-trains. (The 4-train still rusts the 2-trains.) The Info tab's
        # train table reads these values.
        def game_trains
          return super unless optional_rules.include?(:permanent_five_trains)

          super.map do |train|
            case train[:name]
            when '3' then train.merge(rusts_on: '6')
            when '4' then train.merge(rusts_on: 'D')
            when '5' then train.reject { |key, _| key == :rusts_on }
            else train
            end
          end
        end

        # Optional rule: higher revenues. Every stop a train counts (city,
        # town or off-board) is worth $10 more. All revenue sums (the route
        # screen, the auto-router, dividends, the last run) come through here;
        # the numbers printed on the tiles do not change.
        HIGHER_REVENUE_PER_STOP = 10

        def revenue_for(route, stops)
          revenue = super
          return revenue unless optional_rules.include?(:higher_revenues)

          revenue + (HIGHER_REVENUE_PER_STOP * stops.size)
        end

        FINANCE_HOUSES = %w[BB HAM MUR].freeze

        CONSTRUCTION_COS = %w[BWW J&MC MEIG].freeze
        SEED_RAILWAYS = %w[SFW BBNW ANW BAP].freeze

        def setup
          # A safety net behind the creation form's MUTEX_RULES (an imported
          # or hand-made game could still carry both)
          if optional_rules.include?(:contested_merger) && optional_rules.include?(:purchase_of_control)
            raise GameError, 'Choose at most one merger style: Contested merger or Purchase of control, not both'
          end

          super
          # 2: the seating order, as the players were seated when the game
          # began (a list of ids nothing re-sorts: @players is re-sorted into
          # priority order after the auction and every Stock Round)
          @seating = @players.map(&:id)
          deal_seed_certificates
          deal_corporate_seeds
          name_charter_seeds
          PREFLOATED.each { |id, price| prefloat(corporation_by_id(id), price) }
          seed_lombard
        end

        # Every merger rule that says "clockwise" (9.4 who gets the new shares,
        # 16.5 the vote, 16.6 the auction) follows the seating, not the
        # priority cards: the players round the table, starting with
        # `player` (or from the first seat)
        def clockwise_from(player = nil)
          ring = @players.sort_by { |p| @seating.index(p.id) || 0 }
          at = player && ring.index(player)
          at ? ring.rotate(at) : ring
        end

        # 5.7: a tie for a presidency goes by the CURRENT turn order (the
        # order of the player list, which the priority cards set): the
        # players starting with `player` (or from the first in the list)
        def turn_order_from(player = nil)
          at = player && @players.index(player)
          at ? @players.rotate(at) : @players
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

        # Estancia Land Grant (4 players only): its standard blocks_hexes
        # ability marks J10 and keeps track out of it until a Railway owns the
        # private (the marker is then removed) or it closes at phase 5
        def hex_blocked_by_ability?(entity, ability, hex, tile = nil)
          return false if ability.owner.id == 'ELG' && ability.owner.owner&.corporation?

          super
        end

        def after_sell_company(buyer, company, price, seller)
          super
          return unless company.id == 'ELG'

          hex_by_id('J10').tile.remove_blocker!(company)
        end

        # La Boca Docks Lease: the terrain cost of the first tile its Railway
        # lays on Buenos Aires (F16) or the approach with a printed cost (E17)
        # is not charged, once only. A player-owned La Boca does nothing.
        LA_BOCA_HEXES = %w[F16 E17].freeze

        # 8.3: the terrain cost printed on the map is paid from the Railway's
        # Treasury every time a tile is laid on the hex and every time a tile
        # on it is upgraded (the standard cost belongs to the tile laid, so
        # only the first one would pay it)
        def upgrade_cost(tile, hex, entity, spender)
          cost = hex.original_tile.upgrades.sum(&:cost)
          la_boca = company_by_id('LBDL')
          return cost if !cost.positive? || !LA_BOCA_HEXES.include?(hex.id) || !la_boca || la_boca.closed?
          return cost if la_boca.owner != entity || !entity.corporation? || @la_boca_used

          @la_boca_used = true
          @log << "#{la_boca.name}: #{entity.name} pays no terrain cost on #{hex.id} (#{format_currency(cost)})"
          0
        end

        # Paraná Ferry Company: only a Railway owning it may run a route over
        # F24 or G21 (the way to the Atlantic Export)
        FERRY_HEXES = %w[F24 G21].freeze

        def check_other(route)
          super
          return if (route.all_hexes.map(&:id) & FERRY_HEXES).empty?

          ferry = company_by_id('PFC')
          return if ferry && !ferry.closed? && ferry.owner == route.corporation

          raise GameError, "Only a Railway owning #{ferry&.name || 'the Paraná Ferry Company'} may run over F24 or G21"
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

        # Each Charter card names the Construction Company seed share its
        # Finance House really holds (dealt at random, so the text is made
        # after the deal)
        def name_charter_seeds
          CHARTERS.each do |sym, fh_id|
            fh = corporation_by_id(fh_id)
            cc = fh.shares.map(&:corporation).find { |c| CONSTRUCTION_COS.include?(c.id) }
            next unless cc

            plain = ->(c) { "#{c.full_name.sub(/ \((FH|CC)\)\z/, '')} (#{finance_house?(c) ? 'FH' : 'CC'})" }
            company_by_id(sym).desc =
              "40% president's certificate for #{plain.call(fh)}. Purchasing this floats #{plain.call(fh)}; the winning " \
              "bid is paid into its treasury, and the buyer sets its par value. #{plain.call(fh)} itself holds a 20% seed " \
              "share in #{plain.call(cc)} (#{cc.name}). It belongs to the Finance House, not to the buyer. " \
              'Closes upon receipt of charter.'
          end
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

        # Opt-in (read by the corporation card and the Buy/Sell buttons): show
        # share COUNTS, as 1830 does (the president's certificate counts 2; a
        # Railway has 10 shares, a Finance House or Construction Company 5).
        # Player cards and the spreadsheet stay in percent.
        def shares_as_count?
          true
        end

        # The number of shares in a list of certificates (the president's
        # certificate counts as two)
        def count_of(shares)
          shares.sum(&:percent).div(shares.first.corporation.share_percent)
        end

        # One Sell button per number of shares: ordinary certificates are
        # sold first, the president's certificate only when the count is more
        # than the seller's ordinary shares (display only: the engine still
        # accepts every bundle it accepted before)
        def sellable_bundles(player, corporation)
          best = {}
          super.each do |bundle|
            have = best[bundle.num_shares]
            best[bundle.num_shares] = bundle if !have || (have.presidents_share && !bundle.presidents_share)
          end
          best.sort.map(&:last)
        end

        def init_share_pool
          G1887::SharePool.new(self, allow_president_sale: self.class::PRESIDENT_SALES_TO_MARKET)
        end

        def stock_round
          Engine::Round::Stock.new(self, [
            G1887::Step::HomeToken,
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
          start = corp.share_price
          chain_move(corp, :right)
          if amount.div(corp.total_shares) < 1
            @log << "#{corp.name} must withhold #{format_currency(amount)}: less than " \
                    "#{format_currency(1)} per share for its #{corp.total_shares} shares"
            chain_restore(corp, start) # 8.7: it ends where it started
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

        # A forced withhold puts the marker back on the cell it started on
        # (at the right edge "right" is up a row, so a move left would not
        # lead back)
        def chain_restore(corp, start)
          return unless (old = corp.share_price) && start && old != start

          @stock_market.move(corp, start.coordinates, force: true)
          log_share_price(corp, old)
          recheck_operating_order
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

        # Not yet started (the president's certificate is in its treasury),
        # never started or retired by a merge
        def startable_construction_companies
          CONSTRUCTION_COS.map { |id| corporation_by_id(id) }
            .select { |c| c.presidents_share.owner == c }
        end

        # Railways a Construction Company may start (10.5): the seed
        # Railways, Entre Rios from phase 4 (the first 4-train), and any
        # retired Railway that has a city it may choose as its home
        def startable_railways
          ids = SEED_RAILWAYS + (@phase.available?('4') ? %w[ER] : [])
          fresh = ids.map { |id| corporation_by_id(id) }.select { |c| c.presidents_share.owner == c && !c.retired }
          fresh + restartable_railways
        end

        # Part B: retired Railways that can start again (their home, chosen and
        # placed at the start: any city with an open station space connected by
        # track to Buenos Aires; none, no start)
        def restartable_railways
          @corporations.select { |c| c.retired && tier(c) == 2 && !home_token_locations(c).empty? }
        end

        # Part B: retired Finance Houses a player may start again in a Stock
        # Round (any amount of at least $120, in $5 steps, into its treasury)
        FINANCE_HOUSE_RESTART_MIN = 120

        def restartable_finance_houses(player)
          return [] if !player.player? || player.cash < FINANCE_HOUSE_RESTART_MIN || !certificate_room_for_start?(player)

          @corporations.select { |c| c.retired && finance_house?(c) && control_ok?(player, c, c.presidents_share.percent) }
        end

        # The cities a restarted Railway may choose as its home: an open
        # station space, connected by track to Buenos Aires (F16)
        def home_token_locations(corporation)
          start = hex_by_id('F16')
          seen = { start => true }
          queue = [start]
          until queue.empty?
            hex = queue.shift
            hex.tile.exits.each do |edge|
              other = hex.neighbors[edge]
              next if !other || seen[other] || !other.tile.exits.include?(hex.invert(edge))

              seen[other] = true
              queue << other
            end
          end
          seen.keys.select { |h| h.tile.cities.any? { |city| city.tokenable?(corporation, free: true) } }
        end

        # Part B: a player starts a retired Finance House again: the amount
        # into its treasury, par the highest not above half, the 40%
        # president's certificate; it floats at once, no subsidy; the marker
        # waits for the next Operating Round
        def restart_finance_house!(player, house, amount)
          house.restart!
          par = finance_house_par(amount)
          @log << "#{player.name} starts #{house.name} again with #{format_currency(amount)} (par " \
                  "#{format_currency(par.price)}), paid into its treasury; #{player.name} is its president"
          share_pool.buy_shares(player, house.presidents_share, exchange: :free, allow_president_change: false, silent: true)
          house.owner = player
          player.spend(amount, house)
          house.par_price = par
          house.ipoed = true
          (@pending_markers ||= []) << house
          @log << "#{house.name}'s price marker waits beside the market until the next Operating Round"
        end

        # Started without the bank subsidy (and every restarted charter)
        NO_SUBSIDY = %w[ER].freeze

        # 3.3 / 13.3: companies a player may start in a Stock Round as their
        # buy (Entre Rios from phase 4, while unstarted); the mechanism is
        # meant to be reused for restarting a retired Railway
        PLAYER_STARTABLE = %w[ER].freeze
        FOUNDING_FLOAT_POOL = 40 # floats when 60% has been sold
        FOUNDING_CAPITAL = 10 # the bank pays 10 x par at the float

        def player_startable(player)
          return [] unless player.player?

          fresh = @phase.available?('4') ? PLAYER_STARTABLE.map { |id| corporation_by_id(id) } : []
          fresh = fresh.select { |c| c.presidents_share.owner == c && !c.retired }
          (fresh + restartable_railways).select { |c| player_may_start?(player, c) }
        end

        # 5.6: the president's certificate of a company a player starts is one
        # certificate; the start must not take the player over the limit
        def certificate_room_for_start?(player)
          num_certs(player) + 1 <= cert_limit(player)
        end

        def player_may_start?(player, company)
          min = stock_market.par_prices.map(&:price).min
          player.cash >= min * 2 && certificate_room_for_start?(player) && control_ok?(player, company, company.presidents_share.percent)
        end

        # The player pays par x 2 to the bank for the president's
        # certificate; the other certificates go to the bank pool, sold at
        # par until the company floats; no market price until then
        def player_start(player, company, share_price)
          price = share_price.price * 2
          company.restart! if company.retired
          company.founding = true
          company.par_price = share_price
          company.share_price = share_price # the founding price; the marker is not on the market
          company.ipoed = true
          again = company.restarted ? ' again' : ''
          @log << "#{player.name} starts #{company.name}#{again} at par #{format_currency(share_price.price)}, paying " \
                  "#{format_currency(price)} to the bank for the #{company.presidents_share.percent}% president's certificate"
          share_pool.buy_shares(player, company.presidents_share, exchange: :free, allow_president_change: false, silent: true)
          player.spend(price, @bank)
          company.owner = player
          rest = company.shares_of(company).reject(&:president)
          share_pool.transfer_shares(ShareBundle.new(rest), share_pool, allow_president_change: false)
          @log << "#{ShareBundle.new(rest).percent}% of #{company.name} is placed in the bank pool, at " \
                  "#{format_currency(share_price.price)} each until it floats"
          # 10.1: a restarted Railway's home city is chosen, and its first token placed, now (so that it holds
          # the space), not at the float
          place_home_token(company) if company.restarted && tier(company) == 2
        end

        # The card's "% to float", shown only where a company floats by
        # certificates sold: a player-started Entre Rios, how much more must
        # be sold until 60% has been (never below 0). Every other company
        # floats by a charter or a start, so it shows no line.
        def float_str(entity)
          return if !entity.corporation? || !entity.founding

          "#{[share_pool.percent_of(entity) - FOUNDING_FLOAT_POOL, 0].max}% to float"
        end

        # The float at 60% sold: 10 x par from the bank, the home station, the
        # marker at the start of the next Operating Round
        def founding_float_check(company)
          return if !company.founding || share_pool.percent_of(company) > FOUNDING_FLOAT_POOL

          company.founding = false
          company.share_price = nil # 5.1: no market price until the marker is placed
          capital = company.par_price.price * FOUNDING_CAPITAL
          @bank.spend(capital, company)
          @log << "#{company.name} floats (60% sold); the bank pays #{format_currency(capital)} into its treasury"
          place_home_token(company) unless company.restarted # a restarted Railway placed its token at the start
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
          company.restart! if company.retired
          par = finance_house_par(amount)
          @log << "#{starter.name} starts #{company.name}#{company.restarted ? ' again' : ''} with " \
                  "#{format_currency(amount)} (par #{format_currency(par.price)})"
          share_pool.buy_shares(starter, company.presidents_share, exchange: :free)
          payers.each { |payer, pay| payer.spend(pay, company) if pay.positive? }
          if !NO_SUBSIDY.include?(company.id) && !company.restarted
            @bank.spend(par.price, company)
            @log << "bank pays #{company.name} subsidy #{format_currency(par.price)}"
          end
          company.par_price = par
          (@pending_markers ||= []) << company
          @log << "#{company.name}'s price marker waits beside the market " \
                  'until the next Operating Round'
          place_home_token(company) if company.restarted && tier(company) == 2 # its president chooses the home now
        end

        # The row of company cards in a Stock Round: started companies by
        # their operating order, a Railway whose marker is still waiting
        # beside the market (no market price yet) in the spot where it will
        # operate: by its par, after any company already in that cell or at a
        # better place (its marker goes on the bottom of the stack), several
        # waiting ones in the order their markers will be placed. Companies
        # never started stay at the end, as before. Display only.
        def sorted_corporations
          started, others = corporations.partition(&:ipoed)
          priced, waiting = started.partition(&:share_price)
          order = priced.sort
          key = ->(price) { [-price.price, -price.coordinates.last, price.coordinates.first] }
          pending = (@pending_markers || []) & waiting
          (pending + (waiting - pending)).each do |company|
            next unless company.par_price

            at = key.call(company.par_price)
            spot = order.rindex { |o| (key.call(o.share_price || o.par_price) <=> at) <= 0 }
            order.insert(spot ? spot + 1 : 0, company)
          end
          order + others
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

        # The merger style chosen at creation: :friendly (the default Merge
        # action), :contested (a Merger Round with a vote) or :control (a
        # Merger Round with an auction for control)
        def merge_style
          return :contested if optional_rules.include?(:contested_merger)
          return :control if optional_rules.include?(:purchase_of_control)

          :friendly
        end

        # With a merger variant, a Merger Round follows each Operating Round
        # set, before the next Stock Round
        def next_round!
          if @round.is_a?(G1887::Round::Merger)
            @round = new_stock_round
            return
          end
          return super if merge_style == :friendly || !@round.is_a?(Engine::Round::Operating) ||
                          @round.round_num < @operating_rounds || !mergers_allowed? # before green: no Merger Round

          @turn += 1
          or_round_finished
          or_set_finished
          @round = merger_round
        end

        def merger_round
          G1887::Round::Merger.new(self, [
            G1887::Step::MergeChoices,
            G1887::Step::MergeTokens,
            G1887::Step::DiscardTrain,
            G1887::Step::MergeVote,
            G1887::Step::MergeAuction,
            G1887::Step::MergeProposal,
          ])
        end

        def operating_round(round_num)
          place_pending_markers
          G1887::Round::Operating.new(self, [
            G1887::Step::HomeToken,
            G1887::Step::FinancialTurn,
            G1887::Step::MergeChoices,
            G1887::Step::MergeTokens,
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

        # Priority cards, as in The Old Prince 1871 (9, 10, 10.4): a player
        # who passes takes the lowest card no one else holds; acting returns
        # it and the others keep their order; the round ends when everyone
        # holds a card, and the next Stock Round follows the cards
        NEXT_SR_PLAYER_ORDER = :first_to_pass

        # 5.10: sold out when every certificate is held by players,
        # corporations or Lombard Street: none in the bank pool and none in
        # the company's own Treasury (the held-back BAWR certificates
        # included)
        def sold_out?(corporation)
          share_pool.percent_of(corporation).zero? && corporation.percent_of(corporation).zero?
        end

        attr_accessor :first_auctioneer

        # First Stock Round: least cash first; ties by the auction order (the
        # first auctioneer, then clockwise)
        def reorder_players(order = nil, **kwargs)
          if @round.is_a?(Engine::Round::Auction)
            order ||= :least_cash
            @players.rotate!(@players.index(@first_auctioneer)) if @players.include?(@first_auctioneer)
          end
          super(order, **kwargs)
        end

        # Card 1: in a Stock Round its holder for the next round (nobody until
        # someone passes), otherwise the player who goes first
        def priority_deal_player
          return @round.pass_order.first if @round.is_a?(Engine::Round::Stock)

          @players.reject(&:bankrupt).first
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
        # Player cards: the Lombard Street private closes when it is bought
        # (its buyer becomes the owner of Lombard Street), so the card lists
        # it as an extra row for the owner (display only; nobody's holdings change)
        # The operating-order row on the Game tab: a short type tag after the
        # company's name (display only)
        def entity_type_tag(entity)
          return unless entity.corporation?

          if finance_house?(entity)
            'FH'
          elsif financial?(entity)
            'CC'
          else
            'RR'
          end
        end

        def player_card_extra_companies(player)
          ls = company_by_id('LS')
          ls && lombard&.owner == player ? [ls] : []
        end

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
          players = turn_order_from(pres.player? ? pres : nil)
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

        # 5.4: a president may sell the president's certificate (it counts as
        # two certificates) when another holder has at least two. The holder
        # with the most takes it and hands two of their ordinary certificates
        # to the bank pool; a tie goes to the first in the current turn order
        # clockwise from the old president. Returns that holder, or nil.
        def presidency_taker(corporation, seller)
          cert = corporation.presidents_share
          return if !cert || cert.owner != seller || corporation.owner != seller

          candidates = [*turn_order_from(seller.player? ? seller : nil), *@minors,
                        *@corporations.reject { |c| c.closed? || c == corporation }] - [seller]
          top = candidates.max_by { |h| h.percent_of(corporation) }
          top if top && top.percent_of(corporation) >= 2 * corporation.share_percent
        end

        # The bundles holding the president's certificate that a player or
        # corporation may sell: the certificate with 0, 1, ... of its ordinary
        # certificates, within the pool limit (the swapped certificates count
        # as the certificate's two). Added to legal_bundles, never replacing it.
        def presidency_bundles(seller)
          seller.shares.group_by(&:corporation).flat_map do |corporation, shares|
            next [] if corporation == seller || !corporation.share_price || corporation.founding

            cert = shares.find(&:president)
            next [] if !cert || !presidency_taker(corporation, seller)

            ordinary = shares.select { |sh| sh.buyable && !sh.president }.sort_by(&:id)
            (0..ordinary.size).map { |n| [*ordinary.first(n), cert] }
                              .select { |some| share_pool.fit_in_bank?(ShareBundle.new(some)) }
          end
        end

        def presidency_bundle?(seller, shares)
          ids = shares.map(&:id).sort
          presidency_bundles(seller).any? { |some| some.map(&:id).sort == ids }
        end

        # Standard sell panel of a player: the president's bundles are listed too
        def bundles_for_corporation(holder, corporation, shares: nil)
          list = super
          return list if shares || !holder.player?

          extra = presidency_bundles(holder).select { |some| some.first.corporation == corporation }
                                            .map { |some| ShareBundle.new(some) }
                                            .reject { |x| list.any? { |b| !b.partial? && b.shares.map(&:id).sort == x.shares.map(&:id).sort } }
          (list + extra).sort_by(&:percent)
        end

        # The money for a bundle at the company's price: one price per
        # certificate, the president's certificate counting for two
        def sale_price(shares)
          corporation = shares.first.corporation
          corporation.share_price.price * shares.sum(&:percent).div(corporation.share_percent)
        end

        # 5.4: the president's certificate and any ordinary ones go to the
        # pool and are paid at the price per certificate; the taker gets the
        # certificate and hands two ordinary ones to the pool; one row down
        # per certificate sold (the president's counting for two)
        def sell_presidency_bundle(shares)
          corporation = shares.first.corporation
          cert = shares.find(&:president)
          seller = cert.owner
          taker = presidency_taker(corporation, seller)
          raise GameError, "No other holder of #{corporation.name} has two certificates" unless taker

          bundle = ShareBundle.new(shares)
          bundle.share_price = corporation.share_price.price
          count = shares.sum(&:percent).div(corporation.share_percent)
          share_pool.sell_shares(bundle, allow_president_change: false)
          share_pool.change_president(cert, share_pool, taker, seller)
          corporation.owner = taker
          @log << "#{taker.name} becomes the president of #{corporation.name}"
          count.times { price_down(corporation) }
        end

        # Sells certificates of one company together to the bank pool at the
        # current price per certificate; a presidency swap once, after the
        # whole bundle; then the price drops one row per certificate
        def sell_bundle(shares)
          return sell_presidency_bundle(shares) if shares.any?(&:president)

          corporation = shares.first.corporation
          bundle = ShareBundle.new(shares)
          bundle.share_price = corporation.share_price.price
          share_pool.sell_shares(bundle, allow_president_change: false)
          check_presidency(corporation)
          shares.size.times { price_down(corporation) }
        end

        # 12: scoring. A player's score: personal cash, every certificate
        # they hold at its final market price ($60 per certificate in a
        # company that never reached the market), privates at face value;
        # certificates held by a corporation in a company outside its own
        # chain count for the player at the top of that chain; Lombard
        # Street's cash and certificates count for its owner. Treasury
        # certificates and Railway-owned privates count for nobody.
        NEVER_ON_MARKET_VALUE = 60

        def on_market?(corporation)
          !corporation.founding && corporation.share_price&.corporations&.include?(corporation)
        end

        def certificate_value(share)
          corporation = share.corporation
          on_market?(corporation) ? corporation.share_price.price * share.num_shares : NEVER_ON_MARKET_VALUE
        end

        # A corporation's certificates in companies outside its own chain
        def corporate_holding_value(holder)
          chain = control_holders(holder)
          holder.shares.reject { |sh| chain.include?(sh.corporation) }.sum { |sh| certificate_value(sh) }
        end

        def player_value(player)
          value = player.cash + player.shares.sum { |sh| certificate_value(sh) } + player.companies.sum(&:value)
          actors = [player]
          if lombard&.owner == player
            value += lombard.cash + lombard.shares.sum { |sh| certificate_value(sh) }
            actors << lombard
          end
          value + @corporations.select { |c| actors.include?(control_actor(c)) }.sum { |c| corporate_holding_value(c) }
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

        # 9.9: a merged company may merge again once it has taken a turn in an
        # Operating Round. This marker (separate from the list above, which
        # decides who operates) is set by a merger and clears at the end of
        # the survivor's next turn.
        def merged_since_turn?(corporation)
          (@merged_since_turn ||= {}).key?(corporation)
        end

        # The turn in which a company merges does not count: when the survivor
        # is the one operating (it proposed), its current turn ends first
        def mark_merged!(corporation)
          operating = @round.respond_to?(:current_operator) && @round.current_operator == corporation
          (@merged_since_turn ||= {})[corporation] = operating ? :this_turn : :later
        end

        def after_end_of_operating_turn(operator)
          super
          if (@merged_since_turn ||= {})[operator] == :this_turn
            @merged_since_turn[operator] = :later
          else
            @merged_since_turn.delete(operator)
          end
          return if !operator.corporation? || operator.retired || completed_operating_turn?(operator)

          (@completed_operating_turns ||= []) << operator
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
          if count.to_s.start_with?('p') # "p1": the president's certificate and 1 ordinary one
            return presidency_bundles(seller).find { |some| some.first.corporation == corporation && some.size == count.to_s[1..].to_i + 1 }
          end

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
