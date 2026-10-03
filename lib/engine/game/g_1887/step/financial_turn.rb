# frozen_string_literal: true

require_relative '../../../step/base'
require_relative '../../../step/auctioner'

module Engine
  module Game
    module G1887
      module Step
        # The operating turn of a Finance House or Construction Company
        # (11.3.3): Buy one certificate, Start a Construction Company (a
        # Finance House only), or Pass. The other financial actions are not
        # built yet.
        #
        # Start is offered as a 'bid' (the amount paid), which makes the
        # site show its auction screen: the startable companies as cards,
        # and an amount box for the selected one.
        #
        # Buy is offered as a 'choose': one button per legal, affordable
        # purchase, with the targets' cards below. When Start is possible
        # too, a 'Start a Construction Company' button opens the Start
        # screen.
        class FinancialTurn < Engine::Step::Base
          include Engine::Step::Auctioner

          START_MIN = 120

          def actions(entity)
            return [] unless entity == current_entity
            return %w[bid pass] if @start_chosen
            return %w[choose pass] unless buy_options(entity).empty?

            available.empty? ? %w[pass] : %w[bid pass]
          end

          def active?
            @game.financial?(current_entity) && super
          end

          def setup
            setup_auction
            @start_chosen = false
          end

          def description
            'Financial Turn'
          end

          def pass_description
            'Pass (price moves left)'
          end

          # Button text on the shared amount box
          def bid_str(_corporation)
            'Buy'
          end

          # Companies this corporation may start now: a Finance House starts
          # Construction Companies, a Construction Company starts Railways
          def available
            entity = current_entity
            return [] unless @game.financial?(entity)
            return [] if entity.cash < START_MIN
            return @game.startable_construction_companies if @game.finance_house?(entity)

            @game.startable_railways
          end

          def ipo_type(_corporation)
            :bid
          end

          # The shared auction screen and player cards call these. Starting
          # is not an auction: nothing is being auctioned and no cash is
          # committed to bids. (Auctioner's auctioning is protected, which
          # the server enforces but the browser-compiled code does not.)
          def auctioning; end

          def active_auction; end

          def committed_cash(_player, _show_hidden = false)
            0
          end

          def min_bid(_corporation)
            START_MIN
          end

          def max_bid(entity, _corporation)
            entity.cash
          end

          def process_bid(action)
            entity = action.entity
            company = action.corporation
            amount = action.price
            if (refusal = start_refusal(entity, company))
              raise GameError, refusal
            end

            fmt = ->(v) { @game.format_currency(v) }
            raise GameError, "The amount must be a multiple of #{fmt[min_increment]}" unless (amount % min_increment).zero?
            raise GameError, "The amount must be at least #{fmt[START_MIN]}" if amount < START_MIN
            if amount > entity.cash
              raise GameError, "The amount must not be more than #{entity.name}'s treasury (#{fmt[entity.cash]})"
            end

            @game.start_company(entity, company, amount)
            pass!
          end

          # Why this corporation cannot start that company now (nil if it can)
          def start_refusal(entity, company)
            return if available.include?(company)
            return 'Choose a company to start' unless company&.corporation?

            name = company.name
            return "#{name} was floated at Setup and cannot be started" if @game.class::PREFLOATED.key?(company.id)
            return "#{name} is a Finance House and cannot be started" if @game.finance_house?(company)

            if @game.financial?(company)
              return "Only a Finance House can start #{name}" unless @game.finance_house?(entity)
            else
              return "A Finance House cannot start a Railway (#{name})" if @game.finance_house?(entity)
              return "Only a Construction Company can start #{name}" unless @game.financial?(entity)
              return "#{name} can be started only from phase 4" if company.id == 'ER' && !@game.phase.available?('4')
            end
            return "#{name} has already been started" unless company.presidents_share.owner == company
            if entity.cash < START_MIN
              return "#{entity.name} needs at least #{@game.format_currency(START_MIN)} to start a company"
            end

            "#{entity.name} cannot start #{name}"
          end

          # Corporations below the buyer's tier with a market price; one
          # ordinary certificate from the target's Treasury or the bank
          # pool, at the target's market price, if the buyer can pay it.
          def buy_options(entity)
            return [] unless @game.financial?(entity)

            targets = @game.corporations.select do |c|
              c.share_price && @game.tier(c) > @game.tier(entity)
            end
            targets.sort_by { |c| [@game.tier(c), c.name] }.flat_map do |target|
              price = target.share_price.price
              next [] if entity.cash < price

              { 'Treasury' => target, 'Market' => @game.share_pool }.filter_map do |source, holder|
                share = holder.shares_of(target).find { |s| s.buyable && !s.president }
                next unless share

                {
                  choice: "#{source}:#{target.id}",
                  share: share,
                  price: price,
                  label: "Buy #{share.percent}% #{target.name} #{source} Share " \
                         "(#{@game.format_currency(price)})",
                }
              end
            end
          end

          def choices
            entity = current_entity
            list = buy_options(entity).to_h { |o| [o[:choice], o[:label]] }
            unless available.empty?
              list['start'] = @game.finance_house?(entity) ? 'Start a Construction Company' : 'Start a Railway'
            end
            list
          end

          def choice_name
            available.empty? ? 'Buy' : 'Buy or Start'
          end

          # Cards of the corporations offered, below the buyer's own card
          def show_other
            buy_options(current_entity).map { |o| o[:share].corporation }.uniq
          end

          def process_choose(action)
            entity = action.entity
            if action.choice == 'start'
              raise GameError, "#{entity.name} cannot start a company" if available.empty?

              @start_chosen = true
              return
            end

            option = buy_options(entity).find { |o| o[:choice] == action.choice }
            raise GameError, "#{entity.name} cannot buy #{action.choice}" unless option

            @game.corporate_buy(entity, option[:share], option[:price])
            pass!
          end

          # 11.3: taking no action moves the price one space left (down a
          # row at the left edge of the market).
          def process_pass(action)
            super
            entity = action.entity
            old_price = entity.share_price
            @game.stock_market.move_left(entity)
            @game.log_share_price(entity, old_price)
          end
        end
      end
    end
  end
end
