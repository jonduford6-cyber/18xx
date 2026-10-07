# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G1887
      module Step
        # 14.4: at the start of phase 6 the president of the Railway that owns
        # Kilometric Guarantee pays what the Railway could not. This step
        # exists only while a president must sell shares to raise that money
        # (Game#kilometric_debt is set); otherwise it never blocks. Selling
        # follows emergency money: ordinary certificates only, within the pool
        # limit, never the needy Railway's presidency, no more than needed.
        # If the president cannot cover it even after selling everything, the
        # game has already ended in bankruptcy (Game#kilometric_president_pays).
        class KilometricPayment < Engine::Step::Base
          def debt
            @game.kilometric_debt
          end

          def blocks?
            !debt.nil?
          end

          def active_entities
            debt ? [debt[:player]] : []
          end

          def actions(entity)
            debt && entity == debt[:player] ? %w[sell_shares] : []
          end

          def description
            'Pay Kilometric Guarantee'
          end

          def cash_crisis?
            !debt.nil?
          end

          def needed_cash(_entity)
            debt ? debt[:rest] : 0
          end

          def need
            debt[:rest] - debt[:player].cash
          end

          # The bundles on offer (lists of certificates): a bundle only if one
          # certificate fewer would not be enough, and either it covers what
          # is needed or it is all the player may sell of that company (so no
          # later sale is hurt by this one's price drop)
          def options
            return [] unless debt

            player = debt[:player]
            all = @game.kilometric_bundles(player, debt[:railway])
            all.select do |some|
              price = some.first.corporation.share_price.price
              biggest = all.select { |o| o.first.corporation == some.first.corporation }.map(&:size).max
              price * (some.size - 1) < need && (price * some.size >= need || some.size == biggest)
            end
          end

          def can_sell?(entity, bundle)
            return false if !debt || entity != debt[:player] || bundle.owner != entity

            return false unless bundle.shares.all? { |sh| sh.owner == entity && sh.buyable && !sh.president }

            corporation = bundle.corporation
            options.any? do |some|
              some.first.corporation == corporation && some.size == bundle.shares.size
            end
          end

          def process_sell_shares(action)
            bundle = action.bundle
            unless can_sell?(action.entity, bundle)
              raise GameError, "Cannot sell #{bundle.percent}% of #{bundle.corporation.name} now"
            end

            @game.sell_bundle(bundle.shares)
            player = debt[:player]
            if player.cash >= debt[:rest]
              @game.kilometric_pay!(player, debt[:railway], debt[:rest])
            elsif options.empty?
              # nothing left to sell that would help: bankrupt (8.10)
              @game.kilometric_bankrupt!(player, debt[:railway], debt[:rest])
            end
          end
        end
      end
    end
  end
end
