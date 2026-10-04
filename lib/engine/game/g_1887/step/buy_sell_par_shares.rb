# frozen_string_literal: true

require_relative '../../../step/buy_sell_par_shares'

module Engine
  module Game
    module G1887
      module Step
        # Players never start (par) a corporation. They may buy only an
        # ordinary certificate of a corporation with a market price, from
        # the bank pool or from that corporation's own treasury.
        #
        # Lombard Street (section 3, as 1871's Union Bank): once per Stock
        # Round its owner may have it buy one certificate, instead of the
        # owner's own buy, or start an unstarted Construction Company or
        # Railway. Lombard pays what its treasury allows; the owner pays the
        # shortfall (the engine's purchase_for / borrow_from).
        class BuySellParShares < Engine::Step::BuySellParShares
          def round_state
            super.merge(lombard_bought: false)
          end

          # Baring & Robertson Credit's pull-back: a button in its owner's
          # turn that is not a buy
          def actions(entity)
            # 10.6 / the certificate limit: a required sale comes first, as
            # buttons at the top
            return %w[choose] if entity == current_entity && !forced_options(entity).empty?

            acts = super
            if entity == current_entity && !bought? && !@game.restartable_finance_houses(entity).empty?
              acts = (acts.empty? ? %w[pass] : acts) - %w[pass] + %w[bid pass]
            end
            return acts unless choice_available?(entity)

            (acts.empty? ? %w[pass] : acts) + %w[choose]
          end

          def choice_available?(entity)
            entity == current_entity && entity.player? &&
              (!forced_options(entity).empty? || @game.confidence_pull_back_allowed?(entity) ||
               !exchange_options(entity).empty?)
          end

          # Required sales, one button each: the 10.6 sell-down, or any legal
          # sale while over the certificate limit
          def forced_options(entity)
            return [] if !entity.player? || entity != current_entity

            bundles = forced_sales(entity)
            if bundles.empty? && @game.num_certs(entity) > @game.cert_limit(entity)
              bundles = entity.shares.map(&:corporation).uniq.flat_map do |c|
                @game.bundles_for_corporation(entity, c).select { |bb| can_sell?(entity, bb) }.map(&:shares)
              end
            end
            bundles.map do |shares|
              c = shares.first.corporation
              price = @game.format_currency(c.share_price.price * shares.sum(&:num_shares))
              ["forcedsell:#{c.id}:#{shares.map(&:id).join('+')}", "Sell #{shares.sum(&:percent)}% #{c.name} (#{price})", shares]
            end
          end

          def choice_explanation
            entity = current_entity
            return unless entity&.player?

            if (shares = forced_sales(entity).first)
              c = shares.first.corporation
              excess = @game.control_percent(entity, c) - @game.class::CONTROL_LIMIT
              ["#{entity.name} controls #{@game.control_percent(entity, c)}% of #{c.name} and must sell at least #{excess}%"]
            elsif !forced_options(entity).empty?
              ["#{entity.name} holds #{@game.num_certs(entity)} certificates; the limit is #{@game.cert_limit(entity)}"]
            end
          end

          # 10.4: one exchange per turn; it is not the turn's buy
          def exchange_options(entity)
            return [] if exchanged_this_turn? || @game.held_back_bawr.empty?

            @game.exchange_privates(entity)
          end

          def exchanged_this_turn?
            @round.current_actions.any? { |a| a.is_a?(Action::Choose) && a.choice.to_s.start_with?('exchange') }
          end

          def choice_name
            entity = current_entity
            return entity.name unless forced_options(entity).empty?
            return 'Confidence Track' if exchange_options(entity).empty?
            return 'BAWR' unless @game.confidence_pull_back_allowed?(entity)

            entity.name
          end

          def choices
            entity = current_entity
            forced = forced_options(entity)
            return forced.to_h { |key, label, _| [key, label] } unless forced.empty?

            list = exchange_options(entity).to_h { |c| ["exchange:#{c.id}", "Exchange #{c.name} for 10% BAWR"] }
            if @game.confidence_pull_back_allowed?(entity)
              list['pull_back'] = "Baring & Robertson Credit: pull the track back to space #{@game.confidence - 1}"
            end
            list
          end

          def process_choose(action)
            entity = action.entity
            forced = forced_options(entity)
            unless forced.empty?
              option = forced.find { |key, _, _| key == action.choice }
              raise GameError, "#{entity.name} must first sell: #{forced.map { |_, label, _| label }.join(', ')}" unless option

              bundle = ShareBundle.new(option[2])
              sell_shares(entity, bundle)
              track_action(action, bundle.corporation)
              return
            end
            kind, id = action.choice.split(':')
            if kind == 'exchange'
              company = exchange_options(entity).find { |c| c.id == id }
              raise GameError, "#{entity.name} cannot exchange #{id} now" unless company

              @game.exchange_bawr!(company)
              track_action(action, @game.corporation_by_id('BAWR'))
              return
            end
            raise GameError, 'The Confidence Track cannot be pulled back now' unless @game.confidence_pull_back_allowed?(entity)

            @game.pull_back_confidence!(entity)
            # an action: it returns a held priority card
            @round.last_to_act = entity
            @round.current_actions << action
          end

          # Presidency after a purchase follows 1887's own rule (players,
          # Lombard Street and corporations all count; a tie keeps the
          # president). The shared check counts players only.
          def buy_shares(entity, shares, **kwargs)
            super(entity, shares, **kwargs, allow_president_change: false)
            @game.check_presidency(shares.corporation)
            @game.founding_float_check(shares.corporation)
          end

          def can_ipo_any?(entity)
            return false if bought?

            !lombard_startable(entity).empty? || !@game.player_startable(entity).empty?
          end

          def can_buy?(entity, bundle, borrow_from: nil)
            return false unless bundle
            return lombard_can_buy?(bundle) if entity == @game.lombard

            corporation = bundle.corporation
            return false unless corporation.share_price
            return false if bundle.presidents_share

            sources = [corporation, @game.share_pool]
            return false unless sources.include?(bundle.owner)
            return false unless @game.control_ok?(entity, corporation, bundle.percent) # 10.6

            super(entity, bundle)
          end

          # Only a corporation's own certificates, not seeds it holds
          def can_buy_any_from_ipo?(entity)
            @game.corporations.any? do |c|
              c.share_price && can_buy_shares?(entity, c.shares_of(c))
            end
          end

          def can_buy_any?(entity)
            super || lombard_can_buy_any?(entity)
          end

          # The shared buy panel and par screen show "for Lombard" buttons
          def can_buy_for(entity)
            lombard = @game.lombard
            return [] if lombard.owner != entity || @round.lombard_bought || bought?

            [lombard]
          end

          def lombard_can_buy?(bundle)
            lombard = @game.lombard
            return false unless lombard.owner
            return false if !bundle.buyable || bundle.presidents_share

            corporation = bundle.corporation
            return false unless corporation.share_price
            return false unless [corporation, @game.share_pool].include?(bundle.owner)
            return false unless @game.control_ok?(lombard, corporation, bundle.percent) # 10.6

            lombard.cash + lombard.owner.cash >= lombard_price(bundle)
          end

          def lombard_can_buy_any?(entity)
            return false if can_buy_for(entity).empty?

            @game.corporations.any? do |c|
              (c.shares_of(c) + @game.share_pool.shares_of(c)).any? { |s| lombard_can_buy?(s.to_bundle) }
            end
          end

          # Price of one certificate for Lombard: the market price, one space
          # lower in the final Stock Round
          def lombard_price(bundle)
            return bundle.price unless @game.final_stock_round?

            @game.lower_price(bundle.corporation) * bundle.num_shares
          end

          def process_buy_shares(action)
            return super unless action.purchase_for == @game.lombard

            lombard = @game.lombard
            unless can_buy_for(action.entity).include?(lombard)
              raise GameError, "#{action.entity.name} cannot buy for #{lombard.full_name} now"
            end

            bundle = action.bundle
            corporation = bundle.corporation
            if @game.final_stock_round?
              bundle.share_price = @game.lower_price(corporation)
              @log << "Final Stock Round: #{lombard.full_name} buys one space lower on the market " \
                      "(#{@game.format_currency(bundle.price)})"
            end
            @round.players_bought[action.entity][corporation] += bundle.percent
            @round.bought_from_ipo = true if bundle.owner.corporation?
            buy_shares(lombard, bundle, borrow_from: action.borrow_from, allow_president_change: false)
            track_action(action, corporation)
            @round.lombard_bought = true
            @game.check_presidency(corporation)
            @game.advance_confidence!
          end

          # Starting a company: only for Lombard, through its owner
          def lombard_startable(entity)
            lombard = @game.lombard
            return [] if can_buy_for(entity).empty?
            return [] if lombard.cash + entity.cash < @game.stock_market.par_prices.map(&:price).min * 2

            @game.lombard_startable_companies.select { |c| @game.control_ok?(lombard, c, c.presidents_share.percent) } # 10.6
          end

          # A player starts a company as their buy for the turn (3.3)
          def process_player_start(action)
            entity = action.entity
            corporation = action.corporation
            raise GameError, "#{entity.name} has already bought this turn" if bought?
            unless get_par_prices(entity, corporation).include?(action.share_price)
              raise GameError, "#{entity.name} cannot start #{corporation.name} at that par"
            end

            @game.player_start(entity, corporation, action.share_price)
            track_action(action, corporation)
          end

          # 10.6: while a forced sale is due, only that sale
          # Both required sales (10.6 and the certificate limit) are shown as
          # buttons at the top (forced_options), not the standard way
          def must_sell?(_entity)
            false
          end

          # 10.6: due at the start of the player's turn (before anything but
          # forced sales); an excess arising mid-turn waits for the next turn
          def forced_sales(entity)
            return [] unless entity.player?
            return [] unless @round.current_actions.all? do |a|
              a.is_a?(Action::SellShares) || (a.is_a?(Action::Choose) && a.choice.to_s.start_with?('forcedsell'))
            end

            @game.forced_player_sales(entity)
          end

          def can_sell?(entity, bundle)
            return false if bundle.corporation.founding # nobody sells before it floats

            forced = forced_sales(entity)
            return forced.any? { |some| some.map(&:id).sort == bundle.shares.map(&:id).sort } unless forced.empty?

            super
          end

          # Part B: a retired Finance House is started again with an amount
          # (the standard amount box on its card); everything else by par
          def ipo_type(corporation)
            corporation.retired && @game.finance_house?(corporation) ? :bid : :par
          end

          def min_increment
            5
          end

          def min_bid(_corporation)
            @game.class::FINANCE_HOUSE_RESTART_MIN
          end

          def max_bid(entity, _corporation)
            entity.cash - (entity.cash % 5)
          end

          def bid_str(_corporation)
            'Start'
          end

          # The player cards and the shared auction screen ask these whenever
          # a 'bid' is possible: nothing is auctioned here
          def auctioning; end

          def active_auction; end

          def committed_cash(_player, _show_hidden = false)
            0
          end

          # The restart is the player's buy for the turn
          def bought?
            super || @round.current_actions.any? { |a| a.is_a?(Action::Bid) }
          end

          def process_bid(action)
            entity = action.entity
            house = action.corporation
            amount = action.price
            raise GameError, "#{entity.name} has already bought this turn" if bought?
            unless @game.restartable_finance_houses(entity).include?(house)
              raise GameError, "#{entity.name} cannot start #{house&.name} again now"
            end

            fmt = ->(v) { @game.format_currency(v) }
            raise GameError, "The amount must be at least #{fmt[min_bid(house)]}" if amount < min_bid(house)
            raise GameError, "The amount must be a multiple of #{fmt[5]}" unless (amount % 5).zero?
            raise GameError, "#{entity.name} has only #{fmt[entity.cash]}" if amount > entity.cash

            @game.restart_finance_house!(entity, house, amount)
            track_action(action, house)
          end

          # Par prices for a player starting a company (3.3): par x 2 to pay
          def get_par_prices(entity, corporation)
            return [] if bought? || !@game.player_startable(entity).include?(corporation)

            @game.stock_market.par_prices.select { |p| p.price * 2 <= entity.cash }
          end

          def get_par_prices_with_help(entity, _corporation, extra_cash: 0)
            @game.stock_market.par_prices.select { |p| p.price * 2 <= entity.cash + extra_cash }
          end

          def par_price_only(_corporation, _share_price)
            true
          end

          def process_par(action)
            lombard = @game.lombard
            entity = action.entity
            corporation = action.corporation
            return process_player_start(action) if action.purchase_for != lombard && corporation.id != lombard&.id &&
                                                   @game.player_startable(entity).include?(corporation)

            if action.purchase_for != lombard || !lombard_startable(entity).include?(corporation)
              raise GameError, "#{corporation.name} cannot be started now"
            end

            price = action.share_price.price * 2
            if lombard.cash + entity.cash < price
              raise GameError, "#{lombard.full_name} and #{entity.name} cannot pay #{@game.format_currency(price)}"
            end

            @game.lombard_start(corporation, action.share_price)
            track_action(action, corporation)
            @round.lombard_bought = true
            @game.advance_confidence!
          end
        end
      end
    end
  end
end
