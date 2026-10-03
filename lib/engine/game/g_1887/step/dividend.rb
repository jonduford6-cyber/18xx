# frozen_string_literal: true

require_relative '../../../step/dividend'
require_relative 'railway_only'

module Engine
  module Game
    module G1887
      module Step
        # 11.7: a Railway pays or withholds its earnings.
        # PAY: whole dollars per share (earnings / 10, remainder discarded);
        # each holder gets that times its shares. Certificates in the
        # Railway's own treasury pay the Railway, those in the bank pool
        # pay nobody (the money stays in the bank), and the remainder goes
        # to the Railway. The price moves right. WITHHOLD: everything to
        # the Railway, price left.
        class Dividend < Engine::Step::Dividend
          include RailwayOnly

          # (div: whole-dollar division in the browser-compiled code too,
          # where / on whole numbers gives a fraction)
          def payout(entity, revenue)
            per_share = payout_per_share(entity, revenue)
            { corporation: revenue - (per_share * entity.total_shares), per_share: per_share }
          end

          def payout_per_share(entity, revenue)
            revenue.to_i.div(entity.total_shares)
          end

          def dividends_for_entity(entity, holder, per_share)
            holder.num_shares_of(entity) * per_share
          end

          # Own-treasury certificates pay the Railway (every Railway)
          def holder_for_corporation(entity)
            entity
          end

          # A payment to the corporation presiding over the Railway climbs
          # the chain (Game#chain_receive) once the Railway's own payout and
          # price move are done
          def process_dividend(action)
            @chain_receipt = nil
            super
            return unless (receipt = @chain_receipt)

            @chain_receipt = nil
            @game.chain_receive(receipt[0], receipt[1], action.entity)
          end

          def payout_entity(entity, holder, per_share, payouts)
            super
            presides = holder.corporation? && holder != entity && entity.owner == holder
            @chain_receipt = [holder, payouts[holder]] if presides && payouts[holder]
          end

          # 11.1: the Railway's own price move rechecks the order
          def change_share_price(entity, payout)
            super
            @game.recheck_operating_order
          end

          # PAY always moves right, WITHHOLD left, whatever the remainder
          def dividend_options(entity)
            options = super
            dividend_types.to_h do |type|
              [type, options[type].merge(share_direction: type == :payout ? :right : :left, share_times: 1)]
            end
          end

          def log_run_payout(entity, kind, revenue, subsidy, action, payout)
            return super unless kind == :payout

            @remainder = payout[:corporation]
            log_payout_shares(entity, revenue - @remainder, 0, '') if payout[:per_share].zero?
          end

          private

          def log_payout_shares(entity, revenue, per_share, receivers)
            fmt = ->(v) { @game.format_currency(v) }
            msg = "#{entity.name} pays out #{fmt[revenue + @remainder]}: #{fmt[per_share]} per share"
            msg += " (#{receivers})" unless receivers.empty?
            @log << msg
            pool = @game.share_pool.num_shares_of(entity) * per_share
            pool_pct = @game.share_pool.percent_of(entity)
            @log << "#{fmt[pool]} for the bank pool's #{pool_pct}% stays with the bank" if pool.positive?
            @log << "#{entity.name} keeps the #{fmt[@remainder]} remainder" if @remainder.positive?
          end
        end
      end
    end
  end
end
