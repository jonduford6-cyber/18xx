# frozen_string_literal: true

require_relative '../../../step/buy_train'
require_relative 'railway_only'

module Engine
  module Game
    module G1887
      module Step
        # Buying trains (11.8, 11.9, 12). A Railway with a route and no train
        # must buy one. If it cannot afford the cheapest train in the depot,
        # the money is raised one tier at a time, with buttons ('choose'):
        #  1. the Railway issues certificates from its own treasury;
        #  2. a corporation president gives what it can (a gift), raising
        #     cash by selling certificates it holds or by Reissue; if it
        #     still cannot cover the shortfall, its price moves left and the
        #     call climbs to its own president;
        #  3. the player at the top pays from personal cash, then sells; if
        #     that is still not enough, the player is bankrupt and the game
        #     ends.
        # The Railway's presidency never changes during this. Then the
        # purchase completes as normal. Nobody contributes in the engine's
        # own way (president_may_contribute? is off).
        class BuyTrain < Engine::Step::BuyTrain
          include RailwayOnly

          def setup
            super
            @emergency_issued = false
            @payer = nil
          end

          def actions(entity)
            return [] unless entity == current_entity
            return %w[choose] if emergency?(entity)
            return %w[buy_train] if must_buy_train?(entity)

            super
          end

          def president_may_contribute?(_entity, _shell = nil)
            false
          end

          def process_buy_train(action)
            entity = action.entity
            raise GameError, "#{entity.name} has only #{@game.format_currency(entity.cash)}" if action.price > entity.cash

            super
          end

          # The Railway must buy a train and cannot afford the cheapest one
          def emergency?(entity)
            entity.corporation? && must_buy_train?(entity) && shortfall(entity).positive?
          end

          def shortfall(entity)
            @depot.min_depot_price - entity.cash
          end

          # Who pays now: the Railway (issuing), a corporation, or the player
          # at the top (with Lombard Street, its owner)
          def payer(entity)
            return entity if !@emergency_issued && !emergency_issue_shares(entity).empty?

            @payer || entity.owner
          end

          def top_player(payer)
            payer.minor? ? payer.owner : payer
          end

          # Certificates the Railway issues: as many as cover the shortfall,
          # or all it can
          def emergency_issue_shares(entity)
            shares = @game.reissuable_shares(entity)
            price = entity.share_price&.price.to_i
            return [] if shares.empty? || price.zero?

            needed = (shortfall(entity) + price - 1).div(price)
            shares.first(needed)
          end

          # Sales a payer may make: never the Railway's presidency changed
          def emergency_sellable(railway, seller)
            shares = seller.minor? ? [] : sellable_for(seller)
            shares.select do |share|
              share.corporation != railway ||
                @game.president_after(railway, seller => -share.percent) == railway.owner
            end
          end

          def sellable_for(seller)
            return @game.sellable_shares(seller) if seller.corporation?

            seller.shares.group_by(&:corporation).filter_map do |corporation, shares|
              next unless corporation.share_price

              share = shares.find { |sh| sh.buyable && !sh.president }
              share if share && @game.share_pool.fit_in_bank?(share.to_bundle)
            end
          end

          def choice_name
            entity = current_entity
            train = @depot.min_depot_train
            text = "#{entity.name} must buy a #{train.name} train (#{@game.format_currency(train.price)}) and has " \
                   "#{@game.format_currency(entity.cash)}: short #{@game.format_currency(shortfall(entity))}"
            pay = payer(entity)
            return "#{text}. First #{entity.name} issues" if pay == entity

            who = pay.minor? ? "#{pay.full_name} (#{pay.owner.name})" : pay.name
            cash = pay.minor? ? pay.cash + pay.owner.cash : pay.cash
            "#{text}. Now #{who}, with #{@game.format_currency(cash)}"
          end

          def choices
            entity = current_entity
            short = shortfall(entity)
            fmt = ->(v) { @game.format_currency(v) }
            pay = payer(entity)
            if pay == entity
              shares = emergency_issue_shares(entity)
              total = entity.share_price.price * shares.size
              return { 'issue' => "#{entity.name} issues #{shares.sum(&:percent)}% Treasury Shares (#{fmt[total]})" }
            end

            if pay.corporation?
              return { 'give' => "#{pay.name} gives #{fmt[short]} to #{entity.name}" } if pay.cash >= short

              list = emergency_sellable(entity, pay).to_h do |share|
                ["sell:#{share.id}", "#{pay.name} sells #{share.percent}% #{share.corporation.name} Share " \
                                     "(#{fmt[share.corporation.share_price.price]})"]
              end
              shares = @game.reissuable_shares(pay)
              shares.size.downto(1) do |n|
                list["reissue:#{n}"] = "#{pay.name} reissues #{shares.first(n).sum(&:percent)}% Treasury Shares " \
                                       "(#{fmt[pay.share_price.price * n]})"
              end
              return list unless list.empty?

              up = pay.owner.minor? ? pay.owner.full_name : pay.owner.name
              gives = pay.cash.positive? ? "gives its #{fmt[pay.cash]}" : 'has nothing to give'
              return {
                'climb' => "#{pay.name} #{gives}; the remaining #{fmt[short - pay.cash]} goes to #{up} " \
                           "(#{pay.name}'s price moves left)",
              }
            end

            player = top_player(pay)
            cash = (pay.minor? ? pay.cash : 0) + player.cash
            return { 'pay' => pay_label(pay, player, short) } if cash >= short

            list = emergency_sellable(entity, player).to_h do |share|
              ["sell:#{share.id}", "#{player.name} sells #{share.percent}% #{share.corporation.name} Share " \
                                   "(#{fmt[share.corporation.share_price.price]})"]
            end
            return list unless list.empty?

            { 'bankrupt' => "#{player.name} is bankrupt (cannot cover the remaining #{fmt[short - cash]})" }
          end

          def pay_label(pay, player, short)
            fmt = ->(v) { @game.format_currency(v) }
            from_lombard = pay.minor? ? [pay.cash, short].min : 0
            from_player = short - from_lombard
            parts = []
            parts << "#{pay.full_name} pays #{fmt[from_lombard]}" if from_lombard.positive?
            parts << "#{player.name} pays #{fmt[from_player]}" if from_player.positive?
            "#{parts.join(' and ')} to #{current_entity.name}"
          end

          def process_choose(action)
            entity = action.entity
            raise GameError, "#{entity.name} is not short of money for a train" unless emergency?(entity)

            choice = action.choice
            raise GameError, "Not a choice now: #{choice}" unless choices.key?(choice)

            short = shortfall(entity)
            pay = payer(entity)
            kind, arg = choice.split(':')
            case kind
            when 'issue'
              @game.issue_shares(entity, emergency_issue_shares(entity))
              @emergency_issued = true
            when 'give'
              pay.spend(short, entity)
              @log << "#{pay.name} gives #{@game.format_currency(short)} to #{entity.name}"
            when 'sell'
              share = (pay.corporation? ? pay : top_player(pay)).shares.find { |s| s.id == arg }
              @game.sell_share(share)
            when 'reissue'
              @game.issue_shares(pay, @game.reissuable_shares(pay).first(arg.to_i), verb: 'reissues')
            when 'climb'
              climb(entity, pay, short)
            when 'pay'
              pay_up(entity, pay, short)
            when 'bankrupt'
              bankrupt(entity, top_player(pay), short - (pay.minor? ? pay.cash : 0) - top_player(pay).cash)
            end
            @emergency_issued = true if pay != entity
          end

          def climb(entity, pay, short)
            if pay.cash.positive?
              @log << "#{pay.name} gives #{@game.format_currency(pay.cash)} to #{entity.name}"
              short -= pay.cash
              pay.spend(pay.cash, entity)
            end
            @log << "#{pay.name} cannot cover the remaining #{@game.format_currency(short)}; " \
                    "the call goes to #{pay.owner.minor? ? pay.owner.full_name : pay.owner.name}"
            @game.price_left(pay)
            @payer = pay.owner
          end

          def pay_up(entity, pay, short)
            player = top_player(pay)
            if pay.minor? && (from = [pay.cash, short].min).positive?
              pay.spend(from, entity)
              @log << "#{pay.full_name} pays #{@game.format_currency(from)} to #{entity.name}"
              short -= from
            end
            return unless short.positive?

            player.spend(short, entity)
            @log << "#{player.name} pays #{@game.format_currency(short)} to #{entity.name}"
          end

          def bankrupt(entity, player, short)
            @log << "-- #{player.name} is bankrupt: #{@game.format_currency(short)} short for #{entity.name}'s " \
                    'train after selling everything allowed. The game ends --'
            @game.declare_bankrupt(player)
          end
        end
      end
    end
  end
end
