# frozen_string_literal: true

require_relative '../../../step/base'
require_relative '../../../step/auctioner'

module Engine
  module Game
    module G1887
      module Step
        # The operating turn of a Finance House or Construction Company
        # (11.3, 11.3.3): first it may sell certificates it holds in other
        # companies (11.3.2), then one action: Buy one certificate, Start a
        # company, Redeem one of its own certificates, Reissue certificates
        # from its own treasury (11.3.1), Merge two companies (11.3.4), or
        # Pass.
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
            return %w[choose pass] if !buy_options(entity).empty? || !other_options(entity).empty? ||
                                      !@game.merge_options(entity).empty?

            available.empty? ? %w[pass] : %w[bid pass]
          end

          def active?
            @game.financial?(current_entity) && super
          end

          def setup
            setup_auction
            @start_chosen = false
            @sold = false
            @sold_companies = [] # 7.2: no buying back a company sold in the same turn
          end

          def description
            'Financial Turn'
          end

          def pass_description
            @sold ? 'Pass' : 'Pass (price moves left)'
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

            list = @game.finance_house?(entity) ? @game.startable_construction_companies : @game.startable_railways
            list.select { |c| @game.control_ok?(entity, c, c.presidents_share.percent) } # 10.6
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
              c.share_price && !c.founding && @game.tier(c) > @game.tier(entity)
            end
            targets.sort_by { |c| [@game.tier(c), c.name] }.flat_map do |target|
              price = target.share_price.price
              next [] if entity.cash < price
              next [] if (@sold_companies ||= []).include?(target)

              { 'Treasury' => target, 'Market' => @game.share_pool }.filter_map do |source, holder|
                share = holder.shares_of(target).find { |s| s.buyable && !s.president }
                next unless share
                next unless @game.control_ok?(entity, target, share.percent) # 10.6

                {
                  choice: "#{source}:#{target.id}",
                  share: share,
                  price: price,
                  label: "Buy #{@game.count_of([share])} #{target.name} #{source} Share " \
                         "(#{@game.format_currency(price)})",
                }
              end
            end
          end

          # Sell (before the action), Redeem and Reissue buttons
          def other_options(entity)
            return [] unless @game.financial?(entity)

            fmt = ->(v) { @game.format_currency(v) }
            list = @game.legal_bundles(entity).map do |some|
              share = some.first
              target = share.corporation
              {
                choice: "sell:#{target.id}:#{some.size}",
                share: share,
                shares: some,
                label: "Sell #{@game.count_of(some)} #{target.name} (#{fmt[target.share_price.price * some.size]})",
              }
            end
            # 5.4: the president's certificate, with "p<n>" ordinary ones
            # (one button per number of shares: the certificate only when the
            # count is more than the seller's ordinary shares)
            list.concat(@game.presidency_bundles(entity).reject do |some|
              ordinary = entity.shares_of(some.first.corporation).count { |sh| sh.buyable && !sh.president }
              @game.count_of(some) <= ordinary
            end.map do |some|
              target = some.first.corporation
              {
                choice: "sell:#{target.id}:p#{some.size - 1}",
                share: some.first,
                shares: some,
                label: "Sell #{@game.count_of(some)} #{target.name} (#{fmt[@game.sale_price(some)]})",
              }
            end)
            if (share = @game.redeemable_share(entity))
              list << {
                choice: 'redeem',
                share: share,
                label: "Redeem #{@game.count_of([share])} Market Share (#{fmt[entity.share_price.price]})",
              }
            end
            shares = @game.reissuable_shares(entity)
            shares.size.downto(1) do |n|
              some = shares.first(n)
              list << {
                choice: "reissue:#{n}",
                share: some.first,
                label: "Issue #{@game.count_of(some)} Treasury #{n == 1 ? 'Share' : 'Shares'} " \
                       "(#{fmt[entity.share_price.price * n]})",
              }
            end
            list
          end

          # The turn menu: Start, Merge, Issue and Redeem (Pass is the Pass
          # button). Selling and buying shares of other companies are on those
          # companies' cards (card_choices).
          def choices
            entity = current_entity
            list = {}
            unless available.empty?
              list['start'] = @game.finance_house?(entity) ? 'Start a Construction Company' : 'Start a Railway'
            end
            list.merge!(@game.merge_options(entity).to_h { |choice, label, _, _| [choice, label] })
            others = other_options(entity).reject { |o| o[:choice].start_with?('sell:') }
            list.merge!(others.sort_by { |o| o[:choice] == 'redeem' ? 1 : 0 }.to_h { |o| [o[:choice], o[:label]] })
            list
          end

          # The shared Choose view draws nothing when the menu is empty
          def render_choices?
            !choices.empty?
          end

          # The company's name before the menu
          def choice_name
            current_entity.name
          end

          # The buttons on another company's card: this corporation's legal
          # sales and purchases of that company's shares, with the same
          # choices (and so the same actions and log lines) the menu had.
          def card_choices(corporation)
            entity = current_entity
            return [] unless @game.financial?(entity)

            fmt = ->(v) { @game.format_currency(v) }
            sells = other_options(entity).select { |o| o[:choice].start_with?('sell:') && o[:share].corporation == corporation }
                                         .map { |o| [o[:choice], "Sell #{@game.count_of(o[:shares])} (#{fmt[@game.sale_price(o[:shares])]})"] }
            buys = buy_options(entity).select { |o| o[:share].corporation == corporation }.map do |o|
              source = o[:choice].split(':').first
              [o[:choice], "Buy #{@game.count_of([o[:share]])} #{source} Share (#{fmt[o[:price]]})"]
            end
            sells + buys
          end

          # Cards of the corporations offered, below the acting corporation's
          # own card: those with sales or purchases, and a merge's two
          # companies
          def show_other
            entity = current_entity
            ((buy_options(entity) + other_options(entity).select { |o| o[:choice].start_with?('sell:') }).map { |o| o[:share].corporation } +
             @game.merge_options(entity).flat_map { |_, _, s, r| [s, r] }).uniq - [entity]
          end

          def process_choose(action)
            entity = action.entity
            kind, arg, count = action.choice.split(':')
            if kind == 'sell'
              shares = @game.bundle_for(entity, arg, count)
              raise GameError, "#{entity.name} cannot sell #{arg} now" unless shares

              @game.sell_bundle(shares)
              @sold = true
              (@sold_companies ||= []) << shares.first.corporation
              return
            end
            if %w[redeem reissue].include?(kind)
              option = other_options(entity).find { |o| o[:choice] == action.choice }
              raise GameError, "#{entity.name} cannot #{kind} now" unless option

              case kind
              when 'redeem'
                @game.redeem_share(entity, option[:share])
              when 'reissue'
                @game.issue_shares(entity, @game.reissuable_shares(entity).first(arg.to_i))
              end
              return pass!
            end

            if kind == 'merge'
              option = @game.merge_options(entity).find { |choice, _, _, _| choice == action.choice }
              raise GameError, "#{entity.name} cannot make that merge now" unless option

              @game.perform_merge!(entity, option[2], option[3])
              return pass! # the turn's action; no pass penalty
            end

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
          # row at the left edge of the market), unless it sold this turn.
          def process_pass(action)
            super
            return if @sold

            entity = action.entity
            old_price = entity.share_price
            @game.stock_market.move_left(entity)
            @game.log_share_price(entity, old_price)
            @game.recheck_operating_order
          end
        end
      end
    end
  end
end
