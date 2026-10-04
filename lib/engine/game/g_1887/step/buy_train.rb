# frozen_string_literal: true

require_relative '../../../step/buy_train'
require_relative 'railway_only'

module Engine
  module Game
    module G1887
      module Step
        # Buying trains (11.8, 11.9, 12), in the site's standard format. A
        # Railway with a route and no train must buy the cheapest train in
        # the depot. If it cannot pay, the money is raised one tier at a time
        # (as 1841 does for chains of corporations):
        #  1. the Railway issues as many certificates as needed, or all it
        #     can (the standard emergency Issue panel);
        #  2. a corporation president's treasury is swept into the Railway
        #     (a gift); it then issues, or sells certificates it holds, in
        #     the same panel, each sale swept in at once; when it has nothing
        #     left, its price moves one space left and the call climbs to its
        #     own president (settle!, automatic, with log lines);
        #  3. Lombard Street's treasury is swept in; the player at the top
        #     sells with the standard sell buttons and contributes the rest
        #     when buying; a player who cannot cover declares bankruptcy
        #     (the standard button; see Step::Bankrupt).
        # Instead of the depot train, the Railway may buy another Railway's
        # train at an agreed price of $1 or more (the standard list), the
        # player's contribution not capped at face value.
        # Nobody sells more than is needed; no sale changes the Railway's
        # presidency.
        class BuyTrain < Engine::Step::BuyTrain
          include RailwayOnly

          def setup
            super
            @issued = false
            @payer = nil
          end

          def actions(entity)
            railway = current_entity
            if railway && emergency?(railway)
              return issuable_shares(railway).empty? ? %w[buy_train] : %w[buy_train sell_shares] if entity == railway
              return %w[sell_shares] if entity == top_player(railway) && player_stage?(railway)

              return []
            end
            return [] unless entity == railway
            return %w[buy_train] if must_buy_train?(entity)

            super
          end

          # Contributions are made by settle! and process_buy_train, never by
          # the engine's own path
          def president_may_contribute?(_entity, _shell = nil)
            false
          end

          # The Railway must buy a train and cannot afford the cheapest one
          def emergency?(entity)
            entity.corporation? && must_buy_train?(entity) && shortfall(entity).positive?
          end

          def shortfall(entity)
            @depot.min_depot_price - entity.cash
          end

          # The price a Railway may offer for another Railway's train: $1 up
          # to its own treasury; in an emergency, once the call has reached
          # the player, plus the player's cash (no cap at face value)
          def spend_minmax(entity, _train)
            extra = emergency?(entity) && player_stage?(entity) ? top_player(entity).cash : 0
            [1, entity.cash + extra]
          end

          # The tier the call has reached: the Railway's president, or higher
          # (the climb applies only to the Railway in the emergency)
          def payer(railway)
            (railway == current_entity && @payer) || railway.owner
          end

          # The player at the top: the payer if a player, Lombard Street's
          # owner, or the player above the corporations
          def top_player(railway)
            tier = payer(railway)
            tier = tier.owner while tier&.corporation?
            tier&.minor? ? tier.owner : tier
          end

          # Standard screen hooks: whose cash and sell buttons are shown
          def corp_owner(railway)
            top_player(railway)
          end

          def real_owner(railway)
            top_player(railway)
          end

          def railway_issue_pending?(railway)
            !@issued && !railway_issue_bundle(railway).empty?
          end

          def player_stage?(railway)
            emergency?(railway) && !railway_issue_pending?(railway) && !payer(railway).corporation?
          end

          # The Railway's emergency issue: as many certificates as cover the
          # shortfall, or all it may (one bundle, sold together)
          def railway_issue_bundle(railway)
            shares = @game.reissuable_shares(railway)
            price = railway.share_price&.price.to_i
            return [] if shares.empty? || price.zero?

            shares.first((shortfall(railway) + price - 1).div(price))
          end

          # The standard emergency Issue panel: the Railway's own issue, or
          # the bundles of the corporation the call has reached
          def issuable_shares(railway)
            return [] if !railway.corporation? || !emergency?(railway)
            return [bundle_of(railway_issue_bundle(railway))] if railway_issue_pending?(railway)

            tier = payer(railway)
            return [] unless tier.corporation?

            corporation_bundles(railway, tier).map { |some| bundle_of(some) }
          end

          def bundle_of(shares)
            bundle = ShareBundle.new(shares)
            bundle.share_price = shares.first.corporation.share_price.price
            bundle
          end

          # A corporation's bundles: its own certificates (issue) and those it
          # holds in other companies, never more than needed, never one that
          # changes the Railway's presidency
          def corporation_bundles(railway, corporation)
            need = shortfall(railway) - corporation.cash
            return [] unless need.positive?

            own = @game.reissuable_shares(corporation)
            issues = (1..own.size).map { |n| own.first(n) }
            sales = @game.legal_bundles(corporation).reject { |some| changes_presidency?(railway, corporation, some) }
            (issues + sales).select { |some| no_more_than_needed?(some, need) }
          end

          def changes_presidency?(railway, seller, shares)
            shares.first.corporation == railway &&
              @game.president_after(railway, seller => -shares.sum(&:percent)) != railway.owner
          end

          # The standard rule: a bundle is allowed only if one certificate
          # fewer would not be enough
          def no_more_than_needed?(shares, need)
            price = shares.first.corporation.share_price.price
            price * (shares.size - 1) < need
          end

          # The player's bundles (standard sell buttons)
          def player_bundles(railway)
            player = top_player(railway)
            need = shortfall(railway) - player.cash
            return [] unless need.positive?

            @game.legal_bundles(player)
                 .reject { |some| changes_presidency?(railway, player, some) }
                 .select { |some| no_more_than_needed?(some, need) }
          end

          def can_sell?(entity, bundle)
            railway = current_entity
            return false if !railway || !emergency?(railway)

            wanted = bundle.shares.map(&:id).sort
            if entity == railway
              issuable_shares(railway).any? { |b| b.shares.map(&:id).sort == wanted }
            else
              entity == top_player(railway) && player_stage?(railway) && bundle.owner == entity &&
                player_bundles(railway).any? { |some| some.map(&:id).sort == wanted }
            end
          end

          # Off, so that the standard screen does not suggest buying a train
          # from another company (1887 allows only the cheapest depot train);
          # the issue still comes first, as the panel and actions enforce
          def must_issue_before_ebuy?(_railway)
            false
          end

          def ebuy_president_can_contribute?(railway)
            player_stage?(railway)
          end

          def issue_text(railway)
            tier = railway_issue_pending?(railway) ? railway : payer(railway)
            tier == railway ? 'Emergency Issue' : "#{tier.name} Emergency Issue or Sell (for #{railway.name})"
          end

          def issue_verb(railway)
            railway_issue_pending?(railway) ? 'issue' : 'issue or sell'
          end

          def issuing_corporation(railway)
            railway_issue_pending?(railway) || !payer(railway).corporation? ? railway : payer(railway)
          end

          def issue_corp_name(bundle)
            bundle.corporation == bundle.owner ? 'Treasury ' : "#{bundle.corporation.name} "
          end

          def process_sell_shares(action)
            railway = current_entity
            bundle = action.bundle
            unless can_sell?(action.entity, bundle)
              raise GameError, "Cannot sell #{bundle.percent}% of #{bundle.corporation.name} now"
            end

            owner = bundle.owner
            if owner == bundle.corporation
              @game.issue_shares(owner, bundle.shares)
              @issued = true if owner == railway
            else
              @game.sell_bundle(bundle.shares)
            end
            settle!(railway)
          end

          # The automatic part, run after every action of the emergency: the
          # corporations' cash is swept into the Railway, and the call climbs
          # past each corporation that has nothing left to give or sell (its
          # price one space left). Lombard Street's treasury is swept in when
          # the call reaches it.
          def settle!(railway)
            return if !railway&.corporation? || !emergency?(railway)
            return if railway_issue_pending?(railway)

            loop do
              short = shortfall(railway)
              tier = payer(railway)
              break if short <= 0 || tier.nil?

              if tier.corporation?
                sweep(tier, railway, short)
                break if shortfall(railway) <= 0 || !corporation_bundles(railway, tier).empty?

                up = tier.owner
                @log << "#{tier.name} cannot cover the remaining #{@game.format_currency(shortfall(railway))}; " \
                        "the call goes to #{up.minor? ? up.full_name : up.name}"
                @game.price_left(tier)
                @payer = up
              else
                sweep(tier, railway, short) if tier.minor?
                break
              end
            end
          end

          def sweep(from, railway, short)
            amount = [from.cash, short].min
            return unless amount.positive?

            from.spend(amount, railway)
            @log << "Sweeping #{@game.format_currency(amount)} from #{from.minor? ? from.full_name : from.name} " \
                    "to #{railway.name}"
          end

          # The player at the top cannot cover what is still missing for the
          # cheapest depot train, even after selling everything they may, and
          # no other Railway has a train on offer
          def player_cannot_cover?(player, railway)
            return false if !railway&.corporation? || !player_stage?(railway) || player != top_player(railway)
            return false if buyable_trains(railway).any? { |t| t.owner != @depot }

            value = @game.legal_bundles(player)
                         .reject { |some| changes_presidency?(railway, player, some) }
                         .group_by { |some| some.first.corporation }
                         .sum { |corporation, bundles| corporation.share_price.price * bundles.map(&:size).max }
            player.cash + value < shortfall(railway)
          end

          # In an emergency the Railway may buy the cheapest depot train or
          # another Railway's train (at an agreed price of $1 or more); the
          # player contributes what its treasury lacks, with no cap
          def process_buy_train(action)
            railway = action.entity
            from_depot = action.train.owner == @depot
            settle!(railway)
            need = action.price - railway.cash
            if emergency?(railway) && need.positive?
              raise GameError, "#{railway.name} must first issue" unless player_stage?(railway)

              player = top_player(railway)
              raise GameError, "#{player.name} must sell certificates first" if player.cash < need

              player.spend(need, railway)
              @log << "#{player.name} contributes #{@game.format_currency(need)}"
            end
            raise GameError, "#{railway.name} has only #{@game.format_currency(railway.cash)}" if action.price > railway.cash

            super
            # Robert Stephenson pays after the purchase (and its phase events,
            # so the first 5-train closes it before it pays)
            @game.stephenson_pays!(railway, action.train, action.price) if from_depot
          end
        end
      end
    end
  end
end
