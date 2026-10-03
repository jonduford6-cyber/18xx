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
            acts = super
            return acts unless choice_available?(entity)

            (acts.empty? ? %w[pass] : acts) + %w[choose]
          end

          def choice_available?(entity)
            entity == current_entity && entity.player? && @game.confidence_pull_back_allowed?(entity)
          end

          def choice_name
            'Confidence Track'
          end

          def choices
            { 'pull_back' => "Baring & Robertson Credit: pull the track back to space #{@game.confidence - 1}" }
          end

          def process_choose(action)
            raise GameError, 'The Confidence Track cannot be pulled back now' unless choice_available?(action.entity)

            @game.pull_back_confidence!(action.entity)
          end

          # Presidency after a purchase follows 1887's own rule (players,
          # Lombard Street and corporations all count; a tie keeps the
          # president). The shared check counts players only.
          def buy_shares(entity, shares, **kwargs)
            super(entity, shares, **kwargs, allow_president_change: false)
            @game.check_presidency(shares.corporation)
          end

          def can_ipo_any?(entity)
            !lombard_startable(entity).empty?
          end

          def can_buy?(entity, bundle, borrow_from: nil)
            return false unless bundle
            return lombard_can_buy?(bundle) if entity == @game.lombard

            corporation = bundle.corporation
            return false unless corporation.share_price
            return false if bundle.presidents_share

            sources = [corporation, @game.share_pool]
            return false unless sources.include?(bundle.owner)

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

            @game.lombard_startable_companies
          end

          def ipo_type(_corporation)
            :par
          end

          def get_par_prices(_entity, _corporation)
            []
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
